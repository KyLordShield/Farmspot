"""Generate the Kaggle notebook for merged_9class_v2 fine-tuning."""
from __future__ import annotations

import json
from pathlib import Path
from pprint import pformat

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "zip files datasets" / "train_merged_9class_v2_kaggle.ipynb"

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

TRAIN_ARGS = dict(
    epochs=30,
    imgsz=640,
    batch=16,
    device=0,
    workers=2,
    patience=10,
    project="/kaggle/working/runs",
    name="merged_9class_v2",
    exist_ok=True,
    seed=1234,
    cos_lr=True,
    close_mosaic=10,
    lr0=0.001,
    lrf=0.01,
    hsv_h=0.015,
    hsv_s=0.7,
    hsv_v=0.4,
    degrees=10.0,
    translate=0.1,
    scale=0.5,
    shear=1.0,
    fliplr=0.5,
    flipud=0.5,
    mosaic=1.0,
    mixup=0.1,
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
    f"""
# FarmSpot mixed-crop fine-tune (merged_9class_v2)

This fine-tunes the existing 9-class detector on the curated Bangladesh
mixed-vegetable set plus the current FarmSpot training data.

| class | train boxes |
|---|---|
| kamatis | 4763 boxes |
| lettuce | 621 |
| cabbage | 1078 |
| cucumber | 4087 |
| chili | 2404 |
| green_bean | 2653 |
| chayote | 389 |
| bok_choy | 175 |
| not_crop | 2529 |

Training images: 3,628. Validation: 496. Test: 363.
Mixed-crop training images: 957. Target+unknown: 952.

The Bangladesh validation/test videos are held out by video, so the metrics are
not inflated by near-identical frames leaking across splits.

**Kaggle GPU is free.** Use a phone-verified account, enable a GPU accelerator,
and run this notebook. This run is sized for a 16 GB T4/P100. If you get CUDA
out-of-memory, change `batch` to 8.
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
if torch.cuda.is_available():
    print(torch.cuda.get_device_name(0))
"""
)

md(
    """
## 1. Unpack the Kaggle dataset

Upload `merged_9class_v2_kaggle.zip` as a Kaggle Dataset. The notebook handles
both cases: Kaggle extracted the zip, or the zip is still intact.
"""
)

code(
    """
import glob, shutil, zipfile
from pathlib import Path

CLASSES = __CLASSES__
INPUT = Path('/kaggle/input')
WORK = Path('/kaggle/working')

def find_dataset():
    matches = [p.parent for p in INPUT.rglob('data.yaml') if 'merged_9class_v2' in str(p)]
    if matches:
        return matches[0]
    for zip_path in INPUT.rglob('*.zip'):
        with zipfile.ZipFile(zip_path) as zf:
            has_dataset = any(
                name.endswith('merged_9class_v2/data.yaml') for name in zf.namelist()
            )
        if not has_dataset:
            continue
        extract = WORK / 'bundle'
        shutil.rmtree(extract, ignore_errors=True)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract)
        matches = list(extract.rglob('merged_9class_v2/data.yaml'))
        if matches:
            return matches[0].parent
    raise FileNotFoundError('merged_9class_v2/data.yaml not found under /kaggle/input')

src = find_dataset()
dst = WORK / 'merged_9class_v2'
if src.resolve() != dst.resolve():
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)

# data.yaml is rewritten because the local build carries a Windows path.
yaml_text = (
    f'path: {dst}\\n'
    'train: images/train\\n'
    'val: images/val\\n'
    'test: images/test\\n'
    f'nc: {len(CLASSES)}\\n'
    'names: [' + ', '.join(CLASSES) + ']\\n'
)
(dst / 'data.yaml').write_text(yaml_text)
print((dst / 'data.yaml').read_text())

ckpts = list(INPUT.rglob('farmspot_9class_best.pt')) + list(WORK.rglob('farmspot_9class_best.pt'))
CKPT = str(ckpts[0]) if ckpts else 'yolo11m.pt'
print('checkpoint:', CKPT)
""".replace("__CLASSES__", repr(CLASSES))
)

md("## 2. Sanity-check the dataset")
code(
    """
from collections import Counter
from pathlib import Path

root = Path('/kaggle/working/merged_9class_v2')
for split in ('train', 'val', 'test'):
    imgs = [p for p in (root / 'images' / split).iterdir()
            if p.suffix.lower() in {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}]
    labels = list((root / 'labels' / split).glob('*.txt'))
    boxes = Counter()
    mixed = 0
    for label in labels:
        classes = set()
        for line in label.read_text().splitlines():
            parts = line.split()
            if len(parts) == 5 and parts[0].isdigit():
                c = int(parts[0])
                boxes[c] += 1
                classes.add(c)
        if len(classes - {8}) >= 2:
            mixed += 1
    print(f'{split:6} images={len(imgs):5} labels={len(labels):5} mixed={mixed:5}')
    print('       boxes:', {i: boxes.get(i, 0) for i in range(9)})
"""
)

md("## 3. Optional smoke test")

code(
    """
RUN_SMOKE = True

if RUN_SMOKE:
    from ultralytics import YOLO
    smoke = YOLO(CKPT)
    smoke.train(
        data=str(root / 'data.yaml'),
        epochs=2,
        imgsz=640,
        batch=8,
        device=0,
        workers=2,
        project='/kaggle/working/runs',
        name='smoke',
        exist_ok=True,
        plots=False,
        verbose=False,
    )
    print('smoke test OK')
"""
)

md(
    """
## 4. Full fine-tune

30 epochs from the existing checkpoint, low learning rate so the current
classes are not destroyed. Expect roughly 3-5 hours on a T4. If Kaggle
disconnects, use **Save & Run All (Commit)** so it keeps running in the
background.
"""
)

code(
    """
from ultralytics import YOLO

model = YOLO(CKPT)
model.train(data=str(root / 'data.yaml'), **__TRAIN_ARGS__)
print('best:', model.trainer.best)
""".replace("__TRAIN_ARGS__", pformat(TRAIN_ARGS, indent=4, width=78))
)

md(
    """
## 5. Test metrics at 640 and 960

The old model was trained at 640 but the API serves 960, which is one reason
mixed photos behaved badly. Compare both sizes here and use the better one for
serving.
"""
)

code(
    """
from ultralytics import YOLO

best = YOLO('/kaggle/working/runs/merged_9class_v2/weights/best.pt')
for size in (640, 800, 960):
    metrics = best.val(
        data=str(root / 'data.yaml'),
        imgsz=size,
        batch=8,
        split='test',
        plots=(size == 640),
        verbose=False,
    )
    print(f'\\n=== imgsz={size} ===')
    print('%-12s %8s %8s %8s %8s' % ('class', 'P', 'R', 'mAP50', 'mAP50-95'))
    index = {c: j for j, c in enumerate(metrics.box.ap_class_index)}
    for i, name in enumerate(__CLASSES__):
        if i in index:
            p, r, ap50, ap = metrics.box.class_result(index[i])
            print('%-12s %8.3f %8.3f %8.3f %8.3f' % (name, p, r, ap50, ap))
        else:
            print('%-12s %8s %8s %8s %8s' % (name, '-', '-', '-', '-'))
""".replace("__CLASSES__", repr(CLASSES))
)

md("## 6. Visual check on held-out mixed crops")
code(
    """
import cv2
import matplotlib.pyplot as plt
from pathlib import Path

test_root = root / 'images' / 'test'
label_root = root / 'labels' / 'test'
ranked = []
for img in sorted(test_root.glob('*')):
    label = label_root / (img.stem + '.txt')
    if not label.exists():
        continue
    classes = {int(line.split()[0]) for line in label.read_text().splitlines()
               if len(line.split()) == 5 and line.split()[0].isdigit()}
    targets = classes - {8}
    if len(targets) >= 2:
        ranked.append((len(targets), img))
ranked.sort(key=lambda item: (-item[0], item[1].name))
picks = [img for _, img in ranked[:8]]
print('showing', [p.name for p in picks])

fig, axes = plt.subplots(2, 4, figsize=(20, 10))
for ax, img in zip(axes.flat, picks):
    result = best.predict(str(img), imgsz=640, conf=0.25, verbose=False)[0]
    ax.imshow(cv2.cvtColor(result.plot(), cv2.COLOR_BGR2RGB))
    ax.set_title(img.name, fontsize=8)
    ax.axis('off')
for ax in axes.ravel()[len(picks):]:
    ax.axis('off')
plt.tight_layout()
plt.show()
"""
)

md(
    """
## 7. Download the checkpoint

The important file is `farmspot_9class_v2_best.pt`. Download it from the Kaggle
output panel, or fetch the zip. Send back the test metrics and the checkpoint;
we will then decide whether to serve at 640, 800, or 960 before changing the API.
"""
)

code(
    """
import shutil, zipfile
from pathlib import Path

run = Path('/kaggle/working/runs/merged_9class_v2')
best_path = run / 'weights' / 'best.pt'
shutil.copy2(best_path, '/kaggle/working/farmspot_9class_v2_best.pt')

result_zip = Path('/kaggle/working/farmspot_9class_v2_results.zip')
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

print('checkpoint:', '/kaggle/working/farmspot_9class_v2_best.pt')
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
print(f'wrote {OUT} ({OUT.stat().st_size / 1024:.1f} KB)')
