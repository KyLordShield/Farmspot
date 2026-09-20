import os
import shutil

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = r"C:\Users\Dell\AppData\Local\Temp\opencode\tomato-repo\farm1\annotations_and_images"
OUT = os.path.join(BASE, "dataset", "kamatis")

# YOLO needs this exact layout: images/... + labels/... pairs in each split.
IMAGES = os.path.join(OUT, "images")
LABELS = os.path.join(OUT, "labels")
for split in ("train", "val"):
    os.makedirs(os.path.join(IMAGES, split), exist_ok=True)
    os.makedirs(os.path.join(LABELS, split), exist_ok=True)

# Deterministic pick: first 20 filenames, 16 for training, 4 for validation.
names = sorted(f for f in os.listdir(os.path.join(SRC, "images")) if f.endswith(".jpeg"))
picked = names[:20]
train, val = picked[:16], picked[16:]


def copy_set(sel, split):
    for img in sel:
        stem = os.path.splitext(img)[0]
        shutil.copy(os.path.join(SRC, "images", img),
                    os.path.join(IMAGES, split, img))
        with open(os.path.join(SRC, "labels", f"{stem}.txt"), encoding="utf-8") as f:
            lines = f.read().splitlines()
        with open(os.path.join(LABELS, split, f"{stem}.txt"),
                  "w", encoding="utf-8") as f:
            for line in lines:
                parts = line.split()
                if parts:
                    parts[0] = "0"  # merge all ripeness classes -> kamatis
                    f.write(" ".join(parts) + "\n")


copy_set(train, "train")
copy_set(val, "val")

with open(os.path.join(OUT, "data.yaml"), "w", encoding="utf-8") as f:
    f.write(f"path: {OUT.replace('\\\\', '/')}\n")
    f.write("train: images/train\n")
    f.write("val: images/val\n")
    f.write("names:\n")
    f.write("  0: kamatis\n")

print(f"OK: {len(train)} train + {len(val)} val (20 total) ready in {OUT}")