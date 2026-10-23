"""Build a merged 9-class set from the current data plus Bangladesh crops.

The Bangladesh release is the only downloaded source with real mixed-crop
scenes. Its original train/valid/test split leaks frames from the same videos,
so this script re-splits by video:

    validation  VID_20250228_125747
    test        VID_20250228_135247
    train       the other 8 videos

Training frames are chosen every N frames when two or more target crops are
present, with a smaller sample of one-target-plus-unknown frames. `--train-stride`
controls N (3 for v2, 1 for v3). Cabbage is boosted because it is the rarest of
the five Bangladesh target crops. At most one non-target box per image is kept
as not_crop so the rejection class does not swamp the training set.

Output is a normal YOLO dataset:

    ml_service/dataset/merged_9class_v2/
        images/{train,val,test}/
        labels/{train,val,test}/
        data.yaml
        manifest_bangladesh.csv
        build_summary.json
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import zipfile
from bisect import bisect_left
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BD_ROOT = (
    ROOT
    / "zip files datasets"
    / "bangladesh mixed vegetable datasets"
    / "Vegetable Object Detection Dataset from Bangladesh"
    / "Original Dataset"
)
CURRENT = ROOT / "ml_service" / "dataset" / "merged_9class"
CHECKPOINT = ROOT / "ml_service" / "farmspot_9class_best.pt"
DEFAULT_OUT = ROOT / "ml_service" / "dataset" / "merged_9class_v2"
DEFAULT_ZIP = ROOT / "zip files datasets" / "merged_9class_v2_kaggle.zip"
NOTEBOOK = ROOT / "zip files datasets" / "train_merged_9class_v2_kaggle.ipynb"
REAL_PHOTOS_ZIP = ROOT / "zip files datasets" / "real_photos_162.zip"

CLASSES = [
    "kamatis",
    "lettuce",
    "cabbage",
    "cucumber",
    "chili",
    "green_bean",
    "chayote",
    "bok_choy",
    "not_crop",
]
NOT_CROP = 8
TARGET_MAP = {
    "Tomato": 0,
    "Cabbage": 2,
    "Cucumber": 3,
    "Green Chilli": 4,
    "Green Beans": 5,
}
VAL_VIDEO = "VID_20250228_125747"
TEST_VIDEO = "VID_20250228_135247"
SPLITS = ("train", "val", "test")
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

VIDEO_RE = re.compile(r"(VID_\d{8}_\d{6})")
FRAME_RE = re.compile(r"-(\d+)_jpg\.rf\.")


@dataclass(frozen=True)
class Box:
    name: str
    xmin: float
    ymin: float
    xmax: float
    ymax: float

    @property
    def area(self) -> float:
        return max(0.0, self.xmax - self.xmin) * max(0.0, self.ymax - self.ymin)


@dataclass
class Frame:
    xml: Path
    video: str
    frame: int
    width: float
    height: float
    boxes: list[Box]

    @property
    def target_boxes(self) -> list[Box]:
        return [b for b in self.boxes if b.name in TARGET_MAP]

    @property
    def target_names(self) -> set[str]:
        return {b.name for b in self.target_boxes}

    @property
    def other_boxes(self) -> list[Box]:
        return [b for b in self.boxes if b.name not in TARGET_MAP]


def parse_voc(xml_path: Path) -> Frame:
    root = ET.parse(xml_path).getroot()
    size = root.find("size")
    width = float(size.findtext("width")) if size is not None and size.findtext("width") else 640.0
    height = float(size.findtext("height")) if size is not None and size.findtext("height") else 360.0
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid image size {width}x{height}")

    boxes: list[Box] = []
    for obj in root.findall("object"):
        name = (obj.findtext("name") or "").strip()
        node = obj.find("bndbox")
        if not name or node is None:
            continue
        try:
            xmin = float(node.findtext("xmin"))
            ymin = float(node.findtext("ymin"))
            xmax = float(node.findtext("xmax"))
            ymax = float(node.findtext("ymax"))
        except (TypeError, ValueError):
            continue
        xmin, xmax = sorted((max(0.0, xmin), min(width, xmax)))
        ymin, ymax = sorted((max(0.0, ymin), min(height, ymax)))
        if xmax - xmin < 2 or ymax - ymin < 2:
            continue
        boxes.append(Box(name, xmin, ymin, xmax, ymax))

    match = VIDEO_RE.search(xml_path.stem)
    if not match:
        raise ValueError("video id not found in filename")
    frame_match = FRAME_RE.search(xml_path.stem)
    frame = int(frame_match.group(1)) if frame_match else 0
    return Frame(xml_path, match.group(1), frame, width, height, boxes)


def load_frames() -> list[Frame]:
    if not BD_ROOT.is_dir():
        raise SystemExit(f"Bangladesh dataset not found: {BD_ROOT}")
    frames: list[Frame] = []
    for xml_path in sorted(BD_ROOT.rglob("*.xml")):
        try:
            frames.append(parse_voc(xml_path))
        except Exception as exc:
            print(f"skip {xml_path.name}: {exc}")
    if not frames:
        raise SystemExit(f"no XML annotations found under {BD_ROOT}")
    return frames


def image_for(xml_path: Path) -> Path | None:
    for suffix in (".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG"):
        candidate = xml_path.with_suffix(suffix)
        if candidate.exists():
            return candidate
    for candidate in xml_path.parent.iterdir():
        if candidate.stem == xml_path.stem and candidate.suffix.lower() in IMAGE_EXTS:
            return candidate
    return None


def select_frames(
    frames: list[Frame], stride: int, cabbage_images: int = 0
) -> list[Frame]:
    ordered = sorted(frames, key=lambda f: (f.video, f.frame, str(f.xml)))
    selected: list[Frame] = []
    last: dict[str, int] = defaultdict(lambda: -10**9)
    for frame in ordered:
        if len(frame.target_names) >= 2 and frame.frame - last[frame.video] >= stride:
            selected.append(frame)
            last[frame.video] = frame.frame
        elif (
            len(frame.target_names) == 1
            and frame.other_boxes
            and frame.frame - last[frame.video] >= stride * 2
        ):
            selected.append(frame)
            last[frame.video] = frame.frame

    if cabbage_images <= 0:
        return selected

    have = sum("Cabbage" in f.target_names for f in selected)
    if have >= cabbage_images:
        return selected

    by_video: dict[str, list[int]] = defaultdict(list)
    chosen = {f.xml for f in selected}
    for frame in selected:
        by_video[frame.video].append(frame.frame)
    for values in by_video.values():
        values.sort()

    def far_enough(video: str, number: int, gap: int) -> bool:
        values = by_video[video]
        pos = bisect_left(values, number)
        for idx in (pos - 1, pos):
            if 0 <= idx < len(values) and abs(values[idx] - number) < gap:
                return False
        return True

    for gap in (6, 4, 3, 2, 1):
        candidates: dict[str, list[Frame]] = defaultdict(list)
        for frame in ordered:
            if "Cabbage" in frame.target_names and frame.xml not in chosen:
                candidates[frame.video].append(frame)
        progressed = True
        while have < cabbage_images and progressed:
            progressed = False
            for video in sorted(candidates):
                while candidates[video]:
                    frame = candidates[video].pop(0)
                    if frame.xml in chosen:
                        continue
                    if not far_enough(video, frame.frame, gap):
                        continue
                    selected.append(frame)
                    chosen.add(frame.xml)
                    by_video[video].append(frame.frame)
                    by_video[video].sort()
                    have += 1
                    progressed = True
                    break
                if have >= cabbage_images:
                    break
        if have >= cabbage_images:
            break
    return selected


def iou(a: Box, b: Box) -> float:
    xmin = max(a.xmin, b.xmin)
    ymin = max(a.ymin, b.ymin)
    xmax = min(a.xmax, b.xmax)
    ymax = min(a.ymax, b.ymax)
    inter = max(0.0, xmax - xmin) * max(0.0, ymax - ymin)
    union = a.area + b.area - inter
    return inter / union if union > 0 else 0.0


def pick_not_crop(frame: Frame, limit: int) -> list[Box]:
    if limit <= 0:
        return []
    targets = frame.target_boxes
    min_area = 0.005 * frame.width * frame.height
    candidates = []
    for box in frame.other_boxes:
        if box.area < min_area:
            continue
        if any(iou(box, target) > 0.4 for target in targets):
            continue
        candidates.append(box)
    candidates.sort(key=lambda b: b.area, reverse=True)
    return candidates[:limit]


def yolo_rows(frame: Frame, not_crop_limit: int) -> list[str]:
    rows = []
    for box in frame.target_boxes:
        cls = TARGET_MAP[box.name]
        xc = ((box.xmin + box.xmax) / 2.0) / frame.width
        yc = ((box.ymin + box.ymax) / 2.0) / frame.height
        bw = (box.xmax - box.xmin) / frame.width
        bh = (box.ymax - box.ymin) / frame.height
        rows.append(f"{cls} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}")
    for box in pick_not_crop(frame, not_crop_limit):
        xc = ((box.xmin + box.xmax) / 2.0) / frame.width
        yc = ((box.ymin + box.ymax) / 2.0) / frame.height
        bw = (box.xmax - box.xmin) / frame.width
        bh = (box.ymax - box.ymin) / frame.height
        rows.append(f"{NOT_CROP} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}")
    return rows


def copy_current(out: Path) -> dict[str, int]:
    counts = {}
    for split in SPLITS:
        src_img = CURRENT / "images" / split
        src_lbl = CURRENT / "labels" / split
        if not src_img.is_dir() or not src_lbl.is_dir():
            raise SystemExit(f"current dataset split missing: {src_img} / {src_lbl}")
        dst_img = out / "images" / split
        dst_lbl = out / "labels" / split
        dst_img.mkdir(parents=True, exist_ok=True)
        dst_lbl.mkdir(parents=True, exist_ok=True)
        images = sorted(
            p for p in src_img.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS
        )
        for index, image in enumerate(images, 1):
            stem = f"img_{index:06d}"
            shutil.copy2(image, dst_img / f"{stem}{image.suffix.lower()}")
            source_label = src_lbl / f"{image.stem}.txt"
            target_label = dst_lbl / f"{stem}.txt"
            if source_label.exists():
                shutil.copy2(source_label, target_label)
            else:
                target_label.write_text("", encoding="utf-8")
        counts[split] = len(images)
    return counts


def emit(
    frame: Frame, split: str, out: Path, not_crop_limit: int, index: int
) -> dict[str, str]:
    image = image_for(frame.xml)
    if image is None:
        raise FileNotFoundError(f"image missing for {frame.xml}")
    stem = f"img_{index:06d}"
    dst_img = out / "images" / split / f"{stem}{image.suffix.lower()}"
    dst_lbl = out / "labels" / split / f"{stem}.txt"
    shutil.copy2(image, dst_img)
    rows = yolo_rows(frame, not_crop_limit)
    dst_lbl.write_text("".join(row + "\n" for row in rows), encoding="utf-8")
    return {
        "split": split,
        "image": dst_img.name,
        "source_image": image.name,
        "video": frame.video,
        "frame": str(frame.frame),
        "targets": "|".join(sorted(frame.target_names)),
        "target_boxes": str(len(frame.target_boxes)),
        "not_crop_boxes": str(sum(1 for row in rows if row.startswith(f"{NOT_CROP} "))),
    }


def read_yolo(path: Path) -> list[tuple[int, list[str]]]:
    out = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[0].isdigit():
            out.append((int(parts[0]), parts[1:]))
    return out


def summarize(out: Path) -> dict:
    summary = {"images": {}, "boxes": {}, "mixed_images": {}, "target_unknown_images": {}}
    for split in SPLITS:
        images = [
            p
            for p in (out / "images" / split).iterdir()
            if p.is_file() and p.suffix.lower() in IMAGE_EXTS
        ]
        boxes = Counter()
        mixed = 0
        target_unknown = 0
        for label in (out / "labels" / split).glob("*.txt"):
            rows = read_yolo(label)
            classes = {c for c, _ in rows}
            boxes.update(c for c, _ in rows)
            if len(classes - {NOT_CROP}) >= 2:
                mixed += 1
            if classes - {NOT_CROP} and NOT_CROP in classes:
                target_unknown += 1
        summary["images"][split] = len(images)
        summary["boxes"][split] = {CLASSES[c]: boxes.get(c, 0) for c in range(len(CLASSES))}
        summary["mixed_images"][split] = mixed
        summary["target_unknown_images"][split] = target_unknown
    return summary


def write_yaml(out: Path) -> None:
    lines = [
        f"path: {out.as_posix()}",
        "train: images/train",
        "val: images/val",
        "test: images/test",
        f"nc: {len(CLASSES)}",
        "names: [" + ", ".join(CLASSES) + "]",
    ]
    (out / "data.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_zip(out: Path, zip_path: Path, notebook: Path = NOTEBOOK) -> None:
    if zip_path.exists():
        zip_path.unlink()
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    readme = (
        f"FarmSpot {out.name} Kaggle bundle\n"
        "=======================================\n\n"
        f"Upload this zip as a Kaggle Dataset, then open {notebook.name}.\n"
        f"The notebook extracts {out.name}/ and loads farmspot_9class_best.pt.\n"
        "real_photos_162.zip is optional and used only for the final sanity check.\n"
    )
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=3) as zf:
        def add_file(arcname: Path, source: Path) -> None:
            name = str(arcname).replace("\\", "/")
            size = len(name.encode("utf-8"))
            if size > 248:
                raise ValueError(f"archive entry is {size} bytes: {name}")
            zf.write(source, name)

        for path in sorted(out.rglob("*")):
            if path.is_file():
                add_file(Path(out.name) / path.relative_to(out), path)
        if CHECKPOINT.exists():
            add_file(Path(CHECKPOINT.name), CHECKPOINT)
        if notebook.exists():
            add_file(Path(notebook.name), notebook)
        if REAL_PHOTOS_ZIP.exists():
            add_file(Path(REAL_PHOTOS_ZIP.name), REAL_PHOTOS_ZIP)
        zf.writestr("KAGGLE_README.txt", readme)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--zip", action="store_true", help="also create the Kaggle upload zip")
    parser.add_argument("--zip-path", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--cabbage-images", type=int, default=350)
    parser.add_argument("--not-crop-per-image", type=int, default=1)
    parser.add_argument("--train-stride", type=int, default=3)
    parser.add_argument("--notebook", type=Path, default=NOTEBOOK)
    args = parser.parse_args()

    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True)

    current_counts = copy_current(args.out)

    frames = load_frames()
    videos = sorted({f.video for f in frames})
    print(f"videos: {len(videos)}")
    for video in videos:
        n = sum(f.video == video for f in frames)
        print(f"  {video}: {n} frames")

    train = [f for f in frames if f.video not in {VAL_VIDEO, TEST_VIDEO}]
    val = [f for f in frames if f.video == VAL_VIDEO]
    test = [f for f in frames if f.video == TEST_VIDEO]
    if not train or not val or not test:
        raise SystemExit("one of the video splits is empty")

    chosen = {
        "train": select_frames(train, stride=args.train_stride, cabbage_images=args.cabbage_images),
        "val": select_frames(val, stride=2),
        "test": select_frames(test, stride=2),
    }

    rows = []
    for split in SPLITS:
        start = current_counts[split]
        ordered = sorted(chosen[split], key=lambda f: (f.video, f.frame, str(f.xml)))
        for offset, frame in enumerate(ordered, 1):
            rows.append(
                emit(frame, split, args.out, args.not_crop_per_image, start + offset)
            )

    manifest = args.out / "manifest_bangladesh.csv"
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    summary = summarize(args.out)
    summary["current_images"] = current_counts
    summary["bangladesh_images"] = {split: sum(r["split"] == split for r in rows) for split in SPLITS}
    summary["videos"] = videos
    summary["selection"] = {
        "train_stride": args.train_stride,
        "val_stride": 2,
        "test_stride": 2,
        "cabbage_target_images": args.cabbage_images,
        "not_crop_boxes_per_image": args.not_crop_per_image,
        "val_video": VAL_VIDEO,
        "test_video": TEST_VIDEO,
    }
    (args.out / "build_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    write_yaml(args.out)

    print()
    print("split     current  bangladesh  total   mixed  target+unknown")
    for split in SPLITS:
        print(
            f"{split:9} {current_counts[split]:7} {summary['bangladesh_images'][split]:11} "
            f"{summary['images'][split]:6} {summary['mixed_images'][split]:7} "
            f"{summary['target_unknown_images'][split]:15}"
        )
    print()
    print("train boxes by class")
    for name, count in summary["boxes"]["train"].items():
        print(f"  {name:12} {count:6}")
    print()
    print(f"dataset: {args.out}")
    print(f"yaml   : {args.out / 'data.yaml'}")

    if args.zip:
        make_zip(args.out, args.zip_path, args.notebook)
        print(f"zip    : {args.zip_path} ({args.zip_path.stat().st_size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
