"""Validate the generated Colab notebook: JSON, Python syntax, wiring."""
import ast
import json
from pathlib import Path

NB = Path(r'C:\xampp\htdocs\Farmspot\zip files datasets\train_merged_9class_colab.ipynb')
CLASSES = ['kamatis', 'lettuce', 'cabbage', 'cucumber', 'chili',
           'green_bean', 'chayote', 'bok_choy', 'not_crop']

nb = json.loads(NB.read_text(encoding='utf-8'))
print(f'nbformat {nb["nbformat"]}.{nb["nbformat_minor"]}, {len(nb["cells"])} cells')


def strip_magic(src):
    """Drop IPython shell/line magic, which is valid in Colab but not Python."""
    return '\n'.join(
        '' if ln.lstrip().startswith(('!', '%')) else ln
        for ln in src.splitlines()
    )


code_srcs = [''.join(c['source']) for c in nb['cells'] if c['cell_type'] == 'code']

bad = []
for i, src in enumerate(code_srcs):
    try:
        ast.parse(strip_magic(src))
    except SyntaxError as exc:
        bad.append((i, exc))
        print(f'  cell {i}: SYNTAX line {exc.lineno}: {exc.msg}')
        lines = src.splitlines()
        for ln in range(max(0, exc.lineno - 2), min(len(lines), exc.lineno + 1)):
            print(f'      {ln + 1:3} | {lines[ln]}')

print(f'code cells : {len(code_srcs)}, syntax errors: {len(bad)}')

# Pull the real TRAIN_ARGS dict out of the notebook instead of string-matching.
# The call is model.train(**{...}), so the single keyword has arg=None.
train_src = next(s for s in code_srcs if 'model.train(' in s)
tree = ast.parse(strip_magic(train_src))
kwargs = None
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and getattr(node.func, 'attr', '') == 'train':
        for kw in node.keywords:
            if kw.arg is None:              # ** unpacking
                kwargs = ast.literal_eval(kw.value)
            else:
                kwargs = {kw.arg: ast.literal_eval(kw.value)}
print(f'train kwargs: {sorted(kwargs) if kwargs else "NOT LITERAL"}')

# Cross-check every override against the installed ultralytics config schema.
schema = None
try:
    from ultralytics.cfg import DEFAULT_CFG
    try:
        schema = set(DEFAULT_CFG.keys())
    except Exception:
        schema = set(dict(DEFAULT_CFG).keys())
except Exception as exc:
    print(f'  (ultralytics schema unavailable: {exc})')
if schema is None:
    raise SystemExit('schema check could not run - not trusting a vacuous pass')
invalid = sorted(k for k in (kwargs or {}) if k not in schema)
print(f'schema check: {"all valid" if not invalid else "INVALID " + str(invalid)}')

expected = {
    'epochs': 100, 'imgsz': 640, 'batch': 16, 'patience': 50,
    'cos_lr': True, 'close_mosaic': 10, 'fliplr': 0.5, 'flipud': 0.5,
    'mosaic': 1.0, 'mixup': 0.1, 'degrees': 10.0,
}
merged = '\n'.join(code_srcs)

checks = {
    'notebook JSON parses': True,
    'all code cells parse': not bad,
    'train kwargs are literals': kwargs is not None,
    'overrides match ultralytics schema': not invalid,
    'epochs=100': kwargs and kwargs.get('epochs') == 100,
    'imgsz=640': kwargs and kwargs.get('imgsz') == 640,
    'batch=16': kwargs and kwargs.get('batch') == 16,
    'yolo11m base weights': "YOLO('yolo11m.pt')" in merged,
    'auto-downloads ultralytics': 'pip -q install ultralytics' in merged,
    'expects dataset zip': 'merged_9class_dataset.zip' in merged,
    'rewrites data.yaml for Colab': 'path: /content/merged_9class' in merged,
    'all 9 class names present': all(c in merged for c in CLASSES),
    'class count is 9': 'nc: {len(CLASSES)}' in merged or 'nc: 9' in merged,
    'val split wired': "val: images/val" in merged,
    'test split wired': "split='test'" in merged,
    'per-class metrics table': 'metrics.box.map50' in merged,
    'downloads best.pt': 'weights/best.pt' in merged,
    'real photo sanity check': 'real_photos' in merged,
    'not_crop excluded from hits': "== 'not_crop'" in merged,
}
print()
for name, ok in checks.items():
    print(f'  [{"ok" if ok else "FAIL"}] {name}')

failed = [n for n, ok in checks.items() if not ok]
print()
print('ALL CHECKS PASSED' if not failed else f'FAILED: {failed}')