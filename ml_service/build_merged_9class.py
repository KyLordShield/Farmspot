"""Build the 9-class merged training set.

Combines the Vietnamese Vegetation Detection release (v41) with the existing
hand-collected kamatis/lettuce/not_kamatis data into a single YOLO dataset.

Source classes are collapsed from 26 -> 9:

    0 kamatis     Tomato            (+ existing kamatis)
    1 lettuce     Lettuce           (+ existing lettuce)
    2 cabbage     Cabbage
    3 cucumber    Cucumber
    4 chili       Chilli
    5 green_bean  Green Beans
    6 chayote     Chayote
    7 bok_choy    Bokchoy
    8 not_crop    the 18 unused veg classes (+ existing not_kamatis)

Images that contain no target crop become not_crop examples, sampled down to
keep the rejection class from dominating training.
"""

import hashlib
import random
import shutil
from collections import Counter
from pathlib import Path

ROOT = Path(r'C:\xampp\htdocs\Farmspot')
VIET = ROOT / 'zip files datasets' / 'veggie_v41_raw'
OWN = ROOT / 'ml_service' / 'dataset' / 'merged_3class'
NEG_DIR = ROOT / 'ml_service' / 'negatives'
OUT = ROOT / 'ml_service' / 'dataset' / 'merged_9class'

CLASSES = ['kamatis', 'lettuce', 'cabbage', 'cucumber', 'chili',
           'green_bean', 'chayote', 'bok_choy', 'not_crop']
NOT_CROP = 8

VIET_MAP = {
    22: 0,   # Tomato
    17: 1,   # Lettuce
    5: 2,    # Cabbage
    11: 3,   # Cucumber
    9: 4,    # Chilli
    15: 5,   # Green Beans
    8: 6,    # Chayote
    3: 7,    # Bokchoy
}
# Per-split budgets, so rejection is measurable on val/test instead of all
# landing in train. not_crop is the class that guards against false positives,
# so it has to be validated.
NEG_BOX_BUDGET = {'train': 1500, 'val': 190, 'test': 200}
SPLITS = {'train': 'train', 'valid': 'val', 'test': 'test'}


def read_boxes(path):
    out = []
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[0].isdigit():
            out.append((int(parts[0]), parts[1:]))
    return out


def digest(path):
    return hashlib.md5(path.read_bytes()).hexdigest()


def write_label(path, boxes):
    path.write_text(''.join(f'{c} {" ".join(rest)}\n' for c, rest in boxes),
                    encoding='utf-8')


def main():
    random.seed(1234)
    if OUT.exists():
        shutil.rmtree(OUT)
    # Canonical YOLO layout: images/<split> and labels/<split>, because
    # ultralytics joins data.yaml entries onto `path` directly, so the split
    # has to be the middle component.
    for name in SPLITS.values():
        (OUT / 'images' / name).mkdir(parents=True)
        (OUT / 'labels' / name).mkdir(parents=True)

    stats = Counter()
    seen = set()
    neg_boxes = 0

    # Vietnamese positives, then sampled Vietnamese negatives.
    for vsplit, osplit in SPLITS.items():
        vimg = VIET / vsplit / 'images'
        vlbl = VIET / vsplit / 'labels'
        negatives = []
        for img in sorted(vimg.glob('*')):
            if img.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
                continue
            lbl = vlbl / (img.stem + '.txt')
            if not lbl.exists():
                continue
            h = digest(img)
            if h in seen:
                stats['dup'] += 1
                continue
            seen.add(h)
            boxes = read_boxes(lbl)
            targets = [(VIET_MAP[c], r) for c, r in boxes if c in VIET_MAP]
            if targets:
                emit(img, targets, osplit, f'viet_{vsplit}', stats)
            elif boxes:
                negatives.append((img, [(NOT_CROP, r) for c, r in boxes]))

        random.shuffle(negatives)
        budget = NEG_BOX_BUDGET[osplit]
        used = 0
        for img, nboxes in negatives:
            if used >= budget:
                stats['neg_skipped'] += 1
                continue
            emit(img, nboxes, osplit, f'vietneg_{vsplit}', stats)
            used += len(nboxes)
        neg_boxes += used

    # Existing hand-collected data: 0/1/2 -> 0/1/8.
    for osplit in SPLITS.values():
        oimg = OWN / 'images' / osplit
        olbl = OWN / 'labels' / osplit
        if not oimg.is_dir():
            continue
        for img in sorted(oimg.glob('*')):
            if img.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
                continue
            lbl = olbl / (img.stem + '.txt')
            if not lbl.exists():
                continue
            h = digest(img)
            if h in seen:
                stats['dup'] += 1
                continue
            seen.add(h)
            remapped = []
            for c, rest in read_boxes(lbl):
                if c == 0:
                    remapped.append((0, rest))
                elif c == 1:
                    remapped.append((1, rest))
                else:
                    remapped.append((NOT_CROP, rest))
            emit(img, remapped, osplit, 'own', stats)

    # Unlabelled negatives stay as true background images (empty label file),
    # which teaches the model to output nothing at all.
    if NEG_DIR.is_dir():
        for img in sorted(NEG_DIR.glob('*')):
            if img.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
                continue
            h = digest(img)
            if h in seen:
                continue
            seen.add(h)
            dst_img = OUT / 'images' / 'train' / f'bg_{img.name}'
            dst_lbl = OUT / 'labels' / 'train' / f'bg_{img.stem}.txt'
            shutil.copy2(img, dst_img)
            dst_lbl.write_text('', encoding='utf-8')
            stats['bg'] += 1

    # Report
    counts = Counter()
    images = 0
    for split in SPLITS.values():
        for lbl in (OUT / 'labels' / split).glob('*.txt'):
            images += 1
            for c, _ in read_boxes(lbl):
                counts[c] += 1

    total = sum(counts.values())
    print(f'images written : {images}')
    print(f'boxes written  : {total}')
    print(f'dupes skipped  : {stats["dup"]}')
    print(f'neg skipped    : {stats["neg_skipped"]}')
    print(f'background imgs: {stats["bg"]}')
    print()
    print('%-4s %-12s %8s %8s' % ('id', 'class', 'boxes', 'share'))
    for cid, name in enumerate(CLASSES):
        n = counts.get(cid, 0)
        print('%-4d %-12s %8d %7.1f%%' % (cid, name, n, 100 * n / total if total else 0))

    yaml = [f'path: {OUT.as_posix()}']
    yaml.append('train: images/train')
    yaml.append('val: images/val')
    yaml.append('test: images/test')
    yaml.append(f'nc: {len(CLASSES)}')
    yaml.append('names: [' + ', '.join(CLASSES) + ']')
    (OUT / 'data.yaml').write_text('\n'.join(yaml) + '\n', encoding='utf-8')
    print(f'\ndata.yaml -> {OUT / "data.yaml"}')


def emit(img, boxes, osplit, tag, stats):
    dst_img = OUT / 'images' / osplit / f'{tag}_{img.name}'
    dst_lbl = OUT / 'labels' / osplit / f'{tag}_{img.stem}.txt'
    shutil.copy2(img, dst_img)
    write_label(dst_lbl, boxes)
    stats[tag] += 1


if __name__ == '__main__':
    main()