"""Generate the evaluation-only Kaggle notebook for the trained v2 checkpoint."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "zip files datasets" / "eval_merged_9class_v2_kaggle.ipynb"

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
# FarmSpot v2 — evaluation only

Training already completed. The previous run failed only while printing
per-class metrics. This notebook loads the trained `best.pt`, evaluates it at
640 / 800 / 960, and exports the results. **No retraining.**

You need two Kaggle datasets attached:

1. `merged_9class_v2_kaggle.zip` — the original private dataset
2. The trained checkpoint, ideally uploaded as `best.pt` or `farmspot_9class_v2_best.pt`

Use **GPU T4 x2** and **Internet On**.
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

md("## 1. Unpack the dataset and locate the trained checkpoint")
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
            if not any(n.endswith('merged_9class_v2/data.yaml') for n in zf.namelist()):
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

candidates = []
for pattern in ('farmspot_9class_v2_best.pt', 'best.pt', 'farmspot_9class_best.pt'):
    candidates += sorted(INPUT.rglob(pattern))
    candidates += sorted(WORK.rglob(pattern))
seen = set()
checkpoints = []
for path in candidates:
    key = str(path.resolve())
    if key not in seen:
        seen.add(key)
        checkpoints.append(path)
print('checkpoints found:')
for path in checkpoints:
    print(' ', path)
if not checkpoints:
    raise FileNotFoundError('Upload the trained best.pt as a Kaggle dataset or file first.')
CKPT = checkpoints[0]
print('using checkpoint:', CKPT)
""".replace("__CLASSES__", repr(CLASSES))
)

md("## 2. Dataset sanity check")
code(
    """
from collections import Counter

for split in ('train', 'val', 'test'):
    imgs = [p for p in (dst / 'images' / split).iterdir()
            if p.suffix.lower() in {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}]
    labels = list((dst / 'labels' / split).glob('*.txt'))
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

md(
    """
## 3. Evaluate at 640 / 800 / 960

The old notebook used `metrics.box.map50[i]`, but `map50` is a scalar in
Ultralytics 8.4. This version uses per-class `class_result()`, which is the
correct API.
"""
)

code(
    """
import csv
from ultralytics import YOLO

best = YOLO(str(CKPT))
print('classes:', best.names)

sizes = (640, 800, 960)
all_metrics = {}
for size in sizes:
    batch = 8 if size <= 800 else 4
    metrics = best.val(
        data=str(dst / 'data.yaml'),
        imgsz=size,
        batch=batch,
        split='test',
        plots=(size == 640),
        verbose=False,
    )
    all_metrics[size] = metrics
    index = {c: j for j, c in enumerate(metrics.box.ap_class_index)}

    print(f'\\n=== imgsz={size} ===')
    print('overall  P=%.3f  R=%.3f  mAP50=%.3f  mAP50-95=%.3f' % (
        metrics.box.mp, metrics.box.mr, metrics.box.map50, metrics.box.map))
    print('%-12s %8s %8s %8s %8s' % ('class', 'P', 'R', 'mAP50', 'mAP50-95'))

    rows = []
    for i, name in enumerate(CLASSES):
        if i in index:
            p, r, ap50, ap = metrics.box.class_result(index[i])
            print('%-12s %8.3f %8.3f %8.3f %8.3f' % (name, p, r, ap50, ap))
            rows.append([name, float(p), float(r), float(ap50), float(ap)])
        else:
            print('%-12s %8s %8s %8s %8s' % (name, '-', '-', '-', '-'))
            rows.append([name, '', '', '', ''])

    with open(f'/kaggle/working/metrics_{size}.csv', 'w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['class', 'P', 'R', 'mAP50', 'mAP50-95'])
        writer.writerows(rows)

BEST_SIZE = max(all_metrics, key=lambda s: all_metrics[s].box.map)
print('\\nbest test size by mAP50-95:', BEST_SIZE)
print({s: round(float(all_metrics[s].box.map), 4) for s in sizes})
"""
)

md("## 4. Visual check on held-out mixed crops")
code(
    """
import cv2
import matplotlib.pyplot as plt

test_root = dst / 'images' / 'test'
label_root = dst / 'labels' / 'test'
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
    result = best.predict(str(img), imgsz=BEST_SIZE, conf=0.25, verbose=False)[0]
    ax.imshow(cv2.cvtColor(result.plot(), cv2.COLOR_BGR2RGB))
    ax.set_title(img.name, fontsize=8)
    ax.axis('off')
for ax in axes.ravel()[len(picks):]:
    ax.axis('off')
plt.tight_layout()
plt.show()
"""
)

md("## 5. Export the checkpoint and metrics")
code(
    """
import json
import shutil
import zipfile
from pathlib import Path

shutil.copy2(CKPT, '/kaggle/working/farmspot_9class_v2_best.pt')

summary = {
    'checkpoint': str(CKPT),
    'best_size': BEST_SIZE,
    'overall': {
        str(size): {
            'P': round(float(all_metrics[size].box.mp), 4),
            'R': round(float(all_metrics[size].box.mr), 4),
            'mAP50': round(float(all_metrics[size].box.map50), 4),
            'mAP50-95': round(float(all_metrics[size].box.map), 4),
        }
        for size in sizes
    },
}
with open('/kaggle/working/metrics_summary.json', 'w') as handle:
    json.dump(summary, handle, indent=2)
print(json.dumps(summary, indent=2))

result_zip = Path('/kaggle/working/farmspot_9class_v2_eval.zip')
with zipfile.ZipFile(result_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.write('/kaggle/working/farmspot_9class_v2_best.pt', 'best.pt')
    for size in sizes:
        zf.write(f'/kaggle/working/metrics_{size}.csv', f'metrics_{size}.csv')
    zf.write('/kaggle/working/metrics_summary.json', 'metrics_summary.json')
    for name in ('confusion_matrix.png', 'confusion_matrix_normalized.png', 'results.png'):
        path = Path('/kaggle/working/runs/detect/val') / name
        if path.exists():
            zf.write(path, name)

print('download:', result_zip, f'{result_zip.stat().st_size / 1024 / 1024:.1f} MB')
"""
)

notebook = {
    "cells": cells,
    "metadata": {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"name": "python", "version": "3.11"},
        "accelerator": "GPU",
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(notebook, indent=1) + "\n", encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")
