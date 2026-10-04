"""Build a numbered contact sheet of upload photos so they can be labelled fast."""
from pathlib import Path
from PIL import Image, ImageDraw

UPLOADS = Path(r'C:\xampp\htdocs\Farmspot\ml_service\uploads')
OUT = Path(r'C:\xampp\htdocs\Farmspot\zip files datasets\label_sheet.jpg')

photos = sorted(p for p in UPLOADS.glob('*.jpg') if p.stat().st_size > 0)
COLS, ROWS = 5, 4
CELL_W, CELL_H = 300, 260
PAD = 6

n = COLS * ROWS
picked = photos[:n]

sheet = Image.new('RGB', (COLS * CELL_W, ROWS * CELL_H), 'white')
draw = ImageDraw.Draw(sheet)

for idx, p in enumerate(picked):
    row, col = divmod(idx, COLS)
    x0 = col * CELL_W
    y0 = row * CELL_H
    try:
        im = Image.open(p).convert('RGB')
        im.thumbnail((CELL_W - 2 * PAD, CELL_H - 2 * PAD - 22))
        x = x0 + (CELL_W - im.width) // 2
        y = y0 + PAD + 18
        sheet.paste(im, (x, y))
    except Exception as exc:
        draw.text((x0 + 8, y0 + 30), f'ERR {exc}', fill='red')

    draw.rectangle([x0 + 2, y0 + 2, x0 + CELL_W - 3, y0 + CELL_H - 3], outline='black')
    draw.rectangle([x0 + 2, y0 + 2, x0 + 40, y0 + 20], fill='yellow')
    draw.text((x0 + 10, y0 + 6), str(idx), fill='black')

OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUT, quality=88)

with OUT.with_suffix('.txt').open('w', encoding='utf-8') as fh:
    for idx, p in enumerate(picked):
        fh.write(f'{idx}\t{p.name}\n')

print(f'sheet : {OUT}')
print(f'tiles : {len(picked)}')
print(f'index : {OUT.with_suffix(".txt")}')
print('open the JPG, then list what each numbered photo contains')