"""Report RAW detections for the real phone photos, including not_crop.

Loads the model directly so nothing is filtered. This is what you need when
diagnosing a false positive: you want the score the model actually gave the crop
it wrongly called, not just the post-threshold result the API returns.

    .venv\\Scripts\\python.exe inspect_photos.py
    .venv\\Scripts\\python.exe inspect_photos.py --limit 40 --conf 0.05
    .venv\\Scripts\\python.exe inspect_photos.py --augment

Photos are deduped by content hash because uploads/ accumulates re-sends.
"""

import argparse
import hashlib
from pathlib import Path

from ultralytics import YOLO

ROOT = Path(__file__).parent
MODEL = ROOT / "farmspot_9class_best.pt"
UPLOADS = ROOT / "uploads"


def distinct_photos(limit: int) -> list[Path]:
    seen: set[str] = set()
    picked: list[Path] = []
    for p in sorted(
        UPLOADS.glob("*.jpg"), key=lambda f: f.stat().st_mtime, reverse=True
    ):
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        picked.append(p)
        if len(picked) >= limit:
            break
    return picked


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=14)
    ap.add_argument("--conf", type=float, default=0.05)
    ap.add_argument("--imgsz", type=int, default=960)
    ap.add_argument("--augment", action="store_true")
    ap.add_argument(
        "--only",
        default=None,
        help="only show photos whose strongest crop is this class name",
    )
    ap.add_argument(
        "--full",
        action="store_true",
        help="print the whole filename instead of a truncated suffix",
    )
    args = ap.parse_args()

    photos = distinct_photos(args.limit)
    model = YOLO(str(MODEL))

    print(
        f"{len(photos)} distinct photo(s) | conf>={args.conf} "
        f"imgsz={args.imgsz} augment={args.augment}\n"
    )
    for p in photos:
        result = model.predict(
            str(p),
            conf=args.conf,
            imgsz=args.imgsz,
            augment=args.augment,
            verbose=False,
        )[0]
        hits = sorted(
            ((result.names[int(b.cls)], float(b.conf)) for b in result.boxes),
            key=lambda t: -t[1],
        )
        if args.only and (not hits or hits[0][0] != args.only):
            continue
        shown = ", ".join(f"{n} {c:.2f}" for n, c in hits[:4]) or "(nothing)"
        label = p.name if args.full else p.name[-22:]
        print(f"{label:<26} {shown}")


if __name__ == "__main__":
    main()