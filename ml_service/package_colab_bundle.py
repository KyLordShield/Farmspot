"""Package the merged dataset into a single zip for Colab upload."""
import time
import zipfile
from pathlib import Path

SRC = Path(r'C:\xampp\htdocs\Farmspot\ml_service\dataset\merged_9class')
DST = Path(r'C:\xampp\htdocs\Farmspot\zip files datasets\merged_9class_dataset.zip')

start = time.time()
count = 0
with zipfile.ZipFile(DST, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    for path in sorted(SRC.rglob('*')):
        if path.is_file():
            zf.write(path, Path('merged_9class') / path.relative_to(SRC))
            count += 1

print(f'files zipped : {count}')
print(f'elapsed      : {time.time() - start:.1f}s')
print(f'size         : {DST.stat().st_size / 1024 / 1024:.1f} MB')
print(f'path         : {DST}')

with zipfile.ZipFile(DST) as zf:
    bad = zf.testzip()
    names = zf.namelist()
    print(f'verify       : {"OK" if bad is None else "CORRUPT: " + bad}')
    print(f'entries      : {len(names)}')
    print(f'has data.yaml: {"merged_9class/data.yaml" in names}')