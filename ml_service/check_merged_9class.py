"""Integrity check for the merged dataset."""
from collections import Counter
from pathlib import Path

import build_merged_9class as B

OUT = B.OUT
problems = []

per_split = {}
for split in ('train', 'val', 'test'):
    idir = OUT / 'images' / split
    ldir = OUT / 'labels' / split
    imgs = {p.stem for p in idir.glob('*') if p.suffix.lower() in ('.jpg', '.jpeg', '.png')}
    lb = {p.stem: p for p in ldir.glob('*.txt')}
    if imgs - set(lb):
        problems.append(f'{split}: {len(imgs - set(lb))} images without labels')
    if set(lb) - imgs:
        problems.append(f'{split}: {len(set(lb) - imgs)} labels without images')
    counts = Counter()
    empty = 0
    for stem, path in lb.items():
        boxes = B.read_boxes(path)
        if not boxes:
            empty += 1
        for cid, rest in boxes:
            if not 0 <= cid < len(B.CLASSES):
                problems.append(f'{split}/{stem}: bad class {cid}')
            counts[cid] += 1
            vals = [float(v) for v in rest]
            if len(vals) != 4:
                problems.append(f'{split}/{stem}: bad box arity {len(vals)}')
            elif not all(0.0 <= v <= 1.0 for v in vals):
                problems.append(f'{split}/{stem}: coords out of range {vals}')
    per_split[split] = counts
    print(f'{split:6} images={len(imgs):5} labels={len(lb):5} empty_labels={empty}')

print()
print('%-4s %-12s %8s %8s %8s' % ('id', 'class', 'train', 'val', 'test'))
for cid, name in enumerate(B.CLASSES):
    print('%-4d %-12s %8d %8d %8d' % (
        cid, name, per_split['train'].get(cid, 0),
        per_split['val'].get(cid, 0), per_split['test'].get(cid, 0)))

missing_val = [B.CLASSES[c] for c in range(len(B.CLASSES))
               if per_split['val'].get(c, 0) == 0]
missing_test = [B.CLASSES[c] for c in range(len(B.CLASSES))
                if per_split['test'].get(c, 0) == 0]
if missing_val:
    problems.append(f'val split missing classes: {missing_val}')
if missing_test:
    problems.append(f'test split missing classes: {missing_test}')

print()
if problems:
    print('PROBLEMS:')
    for p in problems[:40]:
        print('  -', p)
else:
    print('ALL CHECKS PASSED')