"""Package real phone photos + generate the Colab training notebook."""
import json
import time
import zipfile
from pathlib import Path
from pprint import pformat

ROOT = Path(r'C:\xampp\htdocs\Farmspot')
UPLOADS = ROOT / 'ml_service' / 'uploads'
OUTDIR = ROOT / 'zip files datasets'
PHOTOS_ZIP = OUTDIR / 'real_photos_162.zip'
NOTEBOOK = OUTDIR / 'train_merged_9class_colab.ipynb'

# ---------------------------------------------------------------- photo bundle
if PHOTOS_ZIP.exists():
    PHOTOS_ZIP.unlink()
start = time.time()
n_photos = 0
with zipfile.ZipFile(PHOTOS_ZIP, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    for p in sorted(UPLOADS.glob('*')):
        if p.suffix.lower() in ('.jpg', '.jpeg', '.png'):
            zf.write(p, Path('real_photos') / p.name)
            n_photos += 1
print(f'photos  : {n_photos} -> {PHOTOS_ZIP.name} '
      f'({PHOTOS_ZIP.stat().st_size / 1024 / 1024:.1f} MB, '
      f'{time.time() - start:.1f}s)')

CLASSES = ['kamatis', 'lettuce', 'cabbage', 'cucumber', 'chili',
           'green_bean', 'chayote', 'bok_choy', 'not_crop']

TRAIN_ARGS = dict(
    data='merged_9class/data.yaml',
    epochs=100,
    imgsz=640,
    batch=16,
    device=0,
    workers=2,
    patience=50,
    project='/content/runs',
    name='merged_9class',
    exist_ok=True,
    seed=1234,
    cos_lr=True,
    close_mosaic=10,
    # Augmented past the Vietnamese defaults on purpose: real buyer photos are
    # handheld, badly lit and shot at arbitrary angles.
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
)

cells = []
def md(text):
    cells.append({'cell_type': 'markdown', 'metadata': {},
                  'source': text.strip().splitlines(True)})

def code(text):
    cells.append({'cell_type': 'code', 'execution_count': None, 'metadata': {},
                  'outputs': [], 'source': text.strip().splitlines(True)})

md(f"""
# FarmSpot 9-class crop detector

Trains a single YOLO model on the Vietnamese Vegetation Detection v41 release
merged with hand-collected kamatis/lettuce data.

| id | class | boxes |
|----|-------|-------|
| 0 | kamatis | 1167 |
| 1 | lettuce | 803 |
| 2 | cabbage | 330 |
| 3 | cucumber | 1025 |
| 4 | chili | 676 |
| 5 | green_bean | 268 |
| 6 | chayote | 455 |
| 7 | bok_choy | 223 |
| 8 | not_crop | 1977 |

`not_crop` is a real class, not a filter: it is what stops the model from
matching a banana to a crop. `green_bean` and `bok_choy` are the thin classes,
so check their recall in the results cell before trusting them.

Upload `merged_9class_dataset.zip` (~180 MB) to Drive, or use the direct
upload fallback in the next cell.
""")

code("""
# 8.4.156 is the version the training overrides were validated against.
!pip -q install ultralytics==8.4.156
import torch, ultralytics
print('ultralytics', ultralytics.__version__)
print('cuda', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')
""")

code("""
# Drive first (fast, reusable), direct upload as fallback.
import os, shutil
from pathlib import Path

ZIP_NAME = 'merged_9class_dataset.zip'

def from_drive():
    from google.colab import drive
    drive.mount('/content/drive')
    for root, _dirs, files in os.walk('/content/drive/MyDrive'):
        if ZIP_NAME in files:
            shutil.copy2(os.path.join(root, ZIP_NAME), '/content/' + ZIP_NAME)
            print('found on Drive at', root)
            return True
    return False

def from_upload():
    from google.colab import files
    print('Upload merged_9class_dataset.zip (180 MB) ...')
    files.upload()
    for f in os.listdir('/content'):
        if f == ZIP_NAME:
            os.rename('/content/' + f, '/content/' + ZIP_NAME)
    return os.path.exists('/content/' + ZIP_NAME)

if not Path('/content/' + ZIP_NAME).exists():
    try:
        ok = from_drive()
    except Exception as exc:
        print('drive failed:', exc)
        ok = False
    if not ok:
        from_upload()

p = Path('/content/' + ZIP_NAME)
assert p.exists(), ZIP_NAME + ' not found'
print(f'{ZIP_NAME}: {p.stat().st_size / 1024 / 1024:.1f} MB')
""")

code("""
import shutil, zipfile
from pathlib import Path

shutil.rmtree('/content/merged_9class', ignore_errors=True)
with zipfile.ZipFile('/content/merged_9class_dataset.zip') as zf:
    zf.extractall('/content')

root = Path('/content/merged_9class')
for split in ('train', 'val', 'test'):
    imgs = [p for p in (root / 'images' / split).glob('*') if p.suffix.lower() in ('.jpg', '.jpeg', '.png')]
    lb = list((root / 'labels' / split).glob('*.txt'))
    print(f'{split:6} images={len(imgs):5} labels={len(lb):5}')

# The shipped data.yaml carries a Windows absolute path; rewrite it for Colab.
(root / 'data.yaml').write_text(
    'path: /content/merged_9class\\n'
    'train: images/train\\n'
    'val: images/val\\n'
    'test: images/test\\n'
    f'nc: {len(CLASSES)}\\n'
    'names: [' + ', '.join(CLASSES) + ']\\n'
)
print((root / 'data.yaml').read_text())
""")

md("""
## Optional smoke test

Two minutes, and it catches a broken `data.yaml`, a CUDA problem or an
out-of-memory batch size before you spend three hours. Set `RUN_SMOKE = True`.
Drop the batch to 8 if the cell below hits CUDA OOM.
""")

code("""
RUN_SMOKE = False

if RUN_SMOKE:
    from ultralytics import YOLO
    YOLO('yolo11m.pt').train(data='merged_9class/data.yaml', epochs=2, imgsz=640,
                             batch=8, device=0, workers=2, project='/content/runs',
                             name='smoke', exist_ok=True, plots=False, verbose=False)
    print('smoke test OK')
""")

md("""
## Full training

~2.5-3.5 h on a T4. Patience 50 means it can stop early if validation
plateaus, which usually saves 30-60 min.
""")

code("""
from ultralytics import YOLO

model = YOLO('yolo11m.pt')
model.train(**__TRAIN_ARGS__)
print('best:', model.trainer.best)
""".replace('__TRAIN_ARGS__', pformat(TRAIN_ARGS, indent=4, width=78)))

code("""
# Per-class metrics. Pay attention to green_bean and bok_choy recall.
from ultralytics import YOLO
from IPython.display import Image, display

best = YOLO('/content/runs/merged_9class/weights/best.pt')
metrics = best.val(data='merged_9class/data.yaml', imgsz=640, batch=16,
                   split='test', plots=True, verbose=True)

print()
print('%-12s %8s %8s %8s %8s' % ('class', 'P', 'R', 'mAP50', 'mAP50-95'))
for i, name in enumerate(__CLASSES__):
    print('%-12s %8.3f %8.3f %8.3f %8.3f' % (
        name, metrics.box.p[i], metrics.box.r[i],
        metrics.box.map50[i], metrics.box.map[i]))
""".replace('__CLASSES__', repr(CLASSES)))

code("""
import glob
from IPython.display import Image, display

for pat in ('confusion_matrix*.png', 'results.png'):
    for f in glob.glob('/content/runs/merged_9class/' + pat):
        display(Image(filename=f, width=900))
""")

md("""
## Sanity check on real buyer photos

These 162 photos were never in training, so they are the closest thing to the
real use case. Upload `real_photos_162.zip` to run this.

Look at two things: a real crop always comes back as a crop, and a non-crop
(hand, basket, plastic bag, soil) comes back as `not_crop` or nothing at all.
A confident wrong crop is the failure that matters.
""")

code("""
import shutil, zipfile
from pathlib import Path

if Path('/content/real_photos_162.zip').exists():
    shutil.rmtree('/content/real_photos', ignore_errors=True)
    with zipfile.ZipFile('/content/real_photos_162.zip') as zf:
        zf.extractall('/content')
    print(len(list(Path('/content/real_photos').glob('*'))), 'photos ready')

from ultralytics import YOLO
best = YOLO('/content/runs/merged_9class/weights/best.pt')
CONF = 0.25

hits, wrong = {}, {}
photos = sorted(Path('/content/real_photos').glob('*'))
for p in photos:
    for box in best.predict(str(p), conf=CONF)[0].boxes:
        name = best.names[int(box.cls)]
        if name == 'not_crop':
            continue
        hits[name] = hits.get(name, 0) + 1

print('detections across', len(photos), 'real photos (conf >= %.2f)' % CONF)
for k in sorted(hits, key=lambda x: -hits[x]):
    print(f'  {k:12} {hits[k]}')
""")

code("""
from google.colab import files
files.download('/content/runs/merged_9class/weights/best.pt')
""")

notebook = {
    'cells': cells,
    'metadata': {
        'accelerator': 'GPU',
        'colab': {'name': NOTEBOOK.name, 'provenance': []},
        'kernelspec': {'display_name': 'Python 3', 'name': 'python3'},
        'language_info': {'name': 'python'},
    },
    'nbformat': 4,
    'nbformat_minor': 0,
}
NOTEBOOK.write_text(json.dumps(notebook, indent=1), encoding='utf-8')
print(f'notebook : {NOTEBOOK.name} ({NOTEBOOK.stat().st_size / 1024:.0f} KB, '
      f'{len(cells)} cells)')