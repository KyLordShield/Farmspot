"""Generate the short v4 domain-adaptation notebook.

v4 starts from the 100-epoch v3 checkpoint, pseudo-labels the 162 unlabeled
FarmSpot real photos with the old 960px model (including the not_crop reclass
pass), adds them to the v3 train split in place, and fine-tunes for 12 epochs.
"""
from __future__ import annotations

import json
from pathlib import Path
from pprint import pformat

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "zip files datasets" / "train_merged_9class_v4_domain_kaggle.ipynb"

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

BARS = {
    "kamatis": 0.60,
    "lettuce": 0.35,
    "cabbage": 0.35,
    "cucumber": 0.35,
    "chili": 0.35,
    "green_bean": 0.35,
    "chayote": 0.35,
    "bok_choy": 0.35,
}

TRAIN_ARGS = dict(
    epochs=12,
    imgsz=640,
    batch=16,
    device=0,
    workers=2,
    patience=8,
    project="/kaggle/working/runs",
    name="merged_9class_v4",
    exist_ok=True,
    seed=1234,
    cos_lr=True,
    close_mosaic=5,
    lr0=0.0005,
    lrf=0.01,
    hsv_h=0.015,
    hsv_s=0.5,
    hsv_v=0.3,
    degrees=5.0,
    translate=0.05,
    scale=0.2,
    shear=0.0,
    fliplr=0.5,
    flipud=0.0,
    mosaic=0.5,
    mixup=0.0,
    plots=True,
    verbose=True,
)

cells = []


def md(text: str) -> None:
    cells.append(
        {
            "cell_type": "markdown",
            "metadata": {},
            "source": text.strip().splitlines(True),
        }
    )


def code(text: str) -> None:
    cells.append(
        {
            "cell_type": "code",
            "execution_count": None,
            "metadata": {},
            "outputs": [],
            "source": text.strip().splitlines(True),
        }
    )


md(
    """
# FarmSpot v4 domain adaptation (short fine-tune)

v4 is **not** a full retrain. It starts from the 100-epoch v3 checkpoint and
fine-tunes for 12 epochs on the FarmSpot real-phone domain.

It does three things in one run:

1. Loads the old `farmspot_9class_best.pt` at 960 and auto-labels the 162
   unlabeled real photos, including the `not_crop` reclass pass.
2. Uses the v3 train split in place and adds the real photos 5x so the model
   actually sees the phone domain.
3. Fine-tunes v3 for 12 epochs at 640 with gentler augmentation.

### Required Kaggle inputs

- `merged_9class_v3_kaggle.zip` dataset (already uploaded). It contains the v3
  data and the old checkpoint.
- `farmspot_9class_v3_best.pt` uploaded as a small separate Kaggle dataset.
- `real_photos_162.zip` uploaded as a separate dataset if the v3 dataset does
  not already expose a `real_photos/` folder.

Use **GPU T4 x2** and **Save & Run All (Commit)**. Expect about 20-40 minutes.
"""
)

code(
    """
!nvidia-smi
!pip -q install -U ultralytics
import os
os.environ['WANDB_DISABLED'] = 'true'
import torch, ultralytics
print('ultralytics', ultralytics.__version__)
print('torch', torch.__version__)
print('cuda', torch.cuda.is_available())
"""
)

md("## 1. Locate the v3 dataset and checkpoints")

code(
    """
import shutil, zipfile
from pathlib import Path

INPUT = Path('/kaggle/input')
WORK = Path('/kaggle/working')
BUNDLE = WORK / 'bundle'
CLASSES = __CLASSES__

def find_v3_dataset():
    matches = [p.parent for p in INPUT.rglob('data.yaml') if 'merged_9class_v3' in str(p)]
    if matches:
        return matches[0]
    for zip_path in INPUT.rglob('*.zip'):
        try:
            with zipfile.ZipFile(zip_path) as zf:
                has_data = any(
                    n.endswith('merged_9class_v3/data.yaml') for n in zf.namelist()
                )
            if not has_data:
                continue
            shutil.rmtree(BUNDLE, ignore_errors=True)
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(BUNDLE)
            matches = list(BUNDLE.rglob('merged_9class_v3/data.yaml'))
            if matches:
                return matches[0].parent
        except zipfile.BadZipFile:
            continue
    raise FileNotFoundError('Attach the merged_9class_v3_kaggle dataset first')

def find_file(name):
    hits = list(INPUT.rglob(name)) + list(BUNDLE.rglob(name))
    return hits[0] if hits else None

src = find_v3_dataset()
V3_CKPT = find_file('farmspot_9class_v3_best.pt')
OLD_CKPT = find_file('farmspot_9class_best.pt')
if V3_CKPT is None:
    raise FileNotFoundError(
        'Attach farmspot_9class_v3_best.pt as a Kaggle dataset, and keep the exact name'
    )
if OLD_CKPT is None:
    raise FileNotFoundError('farmspot_9class_best.pt not found inside the v3 bundle')

print('dataset :', src)
print('v3 ckpt :', V3_CKPT)
print('old ckpt:', OLD_CKPT)
""".replace("__CLASSES__", repr(CLASSES))
)

md("## 2. Create a small writable v4 folder for the real photos")

code(
    """
dst = WORK / 'merged_9class_v4'
shutil.rmtree(dst, ignore_errors=True)
(dst / 'images' / 'train').mkdir(parents=True)
(dst / 'labels' / 'train').mkdir(parents=True)

yaml_text = (
    f'path: {dst.as_posix()}\\n'
    'train:\\n'
    f'  - {(src / "images" / "train").as_posix()}\\n'
    f'  - {(dst / "images" / "train").as_posix()}\\n'
    f'val: {(src / "images" / "val").as_posix()}\\n'
    f'test: {(src / "images" / "test").as_posix()}\\n'
    f'nc: {len(CLASSES)}\\n'
    'names: [' + ', '.join(CLASSES) + ']\\n'
)
(dst / 'data.yaml').write_text(yaml_text)
print((dst / 'data.yaml').read_text())
"""
)

md("## 3. Auto-label the 162 real photos with the old 960px model")

code(
    """
import gc
from collections import Counter
from pathlib import Path
from PIL import Image
from ultralytics import YOLO

BARS = __BARS__
REJECT = 'not_crop'
REPEAT = 5
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}

real_zip = find_file('real_photos_162.zip')
real_images = []
if real_zip is not None:
    real_root = WORK / 'real_photos_extract'
    shutil.rmtree(real_root, ignore_errors=True)
    real_root.mkdir(parents=True)
    with zipfile.ZipFile(real_zip) as zf:
        zf.extractall(real_root)
    real_images = sorted(
        p for p in real_root.rglob('*') if p.suffix.lower() in IMAGE_EXTS
    )
else:
    # Kaggle often extracts an uploaded zip, so also accept a real_photos/ dir.
    for root in INPUT.rglob('real_photos*'):
        if not root.is_dir():
            continue
        images = sorted(
            p for p in root.rglob('*') if p.suffix.lower() in IMAGE_EXTS
        )
        if len(images) >= 50:
            real_images = images
            print('real photo folder:', root)
            break

if not real_images:
    raise FileNotFoundError(
        'No real photos found. Upload real_photos_162.zip as a separate Kaggle dataset.'
    )
print('real photos:', len(real_images))

old = YOLO(str(OLD_CKPT))

def pseudo_label(image):
    result = old.predict(
        image,
        conf=0.25,
        iou=0.5,
        imgsz=960,
        augment=False,
        max_det=100,
        device=0,
        verbose=False,
    )[0]
    width, height = image.size
    area = width * height
    best = {}

    for box in result.boxes:
        label = result.names[int(box.cls)]
        if label == REJECT or label not in BARS:
            continue
        score = float(box.conf)
        if score < BARS[label]:
            continue
        if score > best.get(label, (0.0, None))[0]:
            best[label] = (score, [float(v) for v in box.xyxy[0]])

    for box in result.boxes:
        label = result.names[int(box.cls)]
        if label != REJECT:
            continue
        x1, y1, x2, y2 = (float(v) for v in box.xyxy[0])
        box_w, box_h = x2 - x1, y2 - y1
        if box_w < 60 or box_h < 60:
            continue
        if not 0.005 <= (box_w * box_h) / area <= 0.20:
            continue
        pad = int(0.12 * max(box_w, box_h))
        origin_x = max(0, int(x1) - pad)
        origin_y = max(0, int(y1) - pad)
        crop = image.crop((
            origin_x,
            origin_y,
            min(width, int(x2) + pad),
            min(height, int(y2) + pad),
        ))
        sub = old.predict(
            crop,
            conf=0.25,
            iou=0.5,
            imgsz=960,
            augment=False,
            max_det=100,
            device=0,
            verbose=False,
        )[0]
        for sbox in sub.boxes:
            slabel = sub.names[int(sbox.cls)]
            if slabel == REJECT or slabel not in BARS or slabel in best:
                continue
            score = float(sbox.conf)
            if score < max(0.70, BARS[slabel]):
                continue
            sx1, sy1, sx2, sy2 = (float(v) for v in sbox.xyxy[0])
            best[slabel] = (
                score,
                [sx1 + origin_x, sy1 + origin_y, sx2 + origin_x, sy2 + origin_y],
            )

    return best

added = 0
skipped = 0
label_counts = Counter()
train_images = dst / 'images' / 'train'
train_labels = dst / 'labels' / 'train'

for index, image_path in enumerate(real_images, 1):
    image = Image.open(image_path).convert('RGB')
    width, height = image.size
    best = pseudo_label(image)
    if not best:
        skipped += 1
        continue

    rows = []
    for label, (score, box) in best.items():
        x1, y1, x2, y2 = box
        x1, x2 = max(0.0, min(width, x1)), max(0.0, min(width, x2))
        y1, y2 = max(0.0, min(height, y1)), max(0.0, min(height, y2))
        if x2 - x1 < 2 or y2 - y1 < 2:
            continue
        xc = ((x1 + x2) / 2.0) / width
        yc = ((y1 + y2) / 2.0) / height
        bw = (x2 - x1) / width
        bh = (y2 - y1) / height
        rows.append(
            f'{CLASSES.index(label)} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}'
        )
        label_counts[label] += 1

    if not rows:
        skipped += 1
        continue

    for repeat in range(REPEAT):
        stem = f'real_{index:03d}_{repeat}'
        shutil.copy2(image_path, train_images / f'{stem}{image_path.suffix.lower()}')
        (train_labels / f'{stem}.txt').write_text(
            ''.join(row + '\\n' for row in rows), encoding='utf-8'
        )
    added += 1

print(f'real photos added: {added} (x{REPEAT}) skipped: {skipped}')
print('pseudo-label boxes:', dict(label_counts))
print('real train images:', len(list(train_images.iterdir())))
print('real train labels:', len(list(train_labels.iterdir())))
print('v3 train images:', len(list((src / 'images' / 'train').iterdir())))

del old
gc.collect()
torch.cuda.empty_cache()
""".replace("__BARS__", pformat(BARS, indent=4, width=78))
)

md("## 4. Short fine-tune from v3")

code(
    """
from ultralytics import YOLO

model = YOLO(str(V3_CKPT))
model.train(data=str(dst / 'data.yaml'), **__TRAIN_ARGS__)
print('best:', model.trainer.best)
""".replace("__TRAIN_ARGS__", pformat(TRAIN_ARGS, indent=4, width=78))
)

md("## 5. Test metrics at 640, 800, and 960")

code(
    """
from ultralytics import YOLO

best = YOLO('/kaggle/working/runs/merged_9class_v4/weights/best.pt')
for size in (640, 800, 960):
    metrics = best.val(
        data=str(dst / 'data.yaml'),
        imgsz=size,
        batch=8,
        split='test',
        plots=False,
        verbose=False,
    )
    print(f'\\n=== imgsz={size} ===')
    print('%-12s %8s %8s %8s %8s' % ('class', 'P', 'R', 'mAP50', 'mAP50-95'))
    index = {c: j for j, c in enumerate(metrics.box.ap_class_index)}
    for i, name in enumerate(CLASSES):
        if i in index:
            p, r, ap50, ap = metrics.box.class_result(index[i])
            print('%-12s %8.3f %8.3f %8.3f %8.3f' % (name, p, r, ap50, ap))
        else:
            print('%-12s %8s %8s %8s %8s' % (name, '-', '-', '-', '-'))
    print('overall mAP50 %.3f  mAP50-95 %.3f' % (metrics.box.map50, metrics.box.map))
"""
)

md("## 6. Save the v4 checkpoint")

code(
    """
import shutil, zipfile
from pathlib import Path

run = Path('/kaggle/working/runs/merged_9class_v4')
best_path = run / 'weights' / 'best.pt'
shutil.copy2(best_path, '/kaggle/working/farmspot_9class_v4_best.pt')

result_zip = Path('/kaggle/working/farmspot_9class_v4_results.zip')
with zipfile.ZipFile(result_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.write(best_path, 'best.pt')
    for name in (
        'results.csv',
        'results.png',
        'confusion_matrix.png',
        'confusion_matrix_normalized.png',
        'labels.jpg',
    ):
        path = run / name
        if path.exists():
            zf.write(path, name)

print('checkpoint:', '/kaggle/working/farmspot_9class_v4_best.pt')
print('results  :', result_zip, f'{result_zip.stat().st_size / 1024 / 1024:.1f} MB')
"""
)

notebook = {
    "cells": cells,
    "metadata": {
        "kernelspec": {
            "display_name": "Python 3",
            "language": "python",
            "name": "python3",
        },
        "language_info": {
            "name": "python",
            "version": "3.11",
        },
        "accelerator": "GPU",
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(notebook, indent=1) + "\n", encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")
