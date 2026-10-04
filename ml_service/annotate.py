"""Draw every box the model found on a photo, so the detections can be checked
by eye instead of inferred from a results screen.

Shows boxes BELOW the acceptance bar too, which is the whole point: it answers
"did the model miss this crop entirely, or did it find it and get filtered out?"

    .venv\\Scripts\\python.exe annotate.py uploads\\some.jpg
    .venv\\Scripts\\python.exe annotate.py uploads\\some.jpg --augment
    .venv\\Scripts\\python.exe annotate.py uploads\\some.jpg --conf 0.05 --imgsz 1280

Box colours:
    green  - accepted, this is what the app shows
    orange - detected but below the bar, so the app hides it
    grey   - not_crop, rejected on purpose
"""

import argparse
import pathlib

from PIL import Image, ImageDraw, ImageFont
from ultralytics import YOLO

ROOT = pathlib.Path(__file__).parent
MODEL = ROOT / "farmspot_9class_best.pt"

# Must mirror CLASS_MIN_CONF in app.py, otherwise the picture lies about what
# the app would actually show.
DEFAULT_BAR = 0.35
KAMATIS_BAR = 0.60


def font(size: int):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--out", default=None)
    ap.add_argument("--conf", type=float, default=0.01,
                    help="draw floor; keep low to reveal suppressed boxes")
    ap.add_argument("--imgsz", type=int, default=960)
    # These MUST mirror app.py. Leaving iou at the ultralytics default of 0.7
    # while the app runs 0.5 changes which boxes survive NMS, so the annotated
    # picture then disagrees with what the endpoint actually returned.
    ap.add_argument("--iou", type=float, default=0.5)
    ap.add_argument("--max-det", type=int, default=100)
    ap.add_argument("--augment", action="store_true")
    ap.add_argument("--bar", type=float, default=DEFAULT_BAR)
    ap.add_argument("--kamatis-bar", type=float, default=KAMATIS_BAR)
    args = ap.parse_args()

    image = Image.open(args.image).convert("RGB")
    model = YOLO(str(MODEL))
    result = model.predict(
        args.image, conf=args.conf, imgsz=args.imgsz, iou=args.iou,
        max_det=args.max_det, augment=args.augment, verbose=False,
    )[0]

    draw = ImageDraw.Draw(image)
    scale = max(image.size) / 900
    line = max(3, int(5 * scale))
    f = font(max(16, int(30 * scale)))

    print(f"{args.image}  {image.size[0]}x{image.size[1]}  "
          f"imgsz={args.imgsz} augment={args.augment} draw_floor={args.conf}")
    print("-" * 78)

    boxes = []
    for b in result.boxes:
        name = result.names[int(b.cls)]
        score = float(b.conf)
        boxes.append((name, score, [int(x) for x in b.xyxy[0]]))

    # Draw the weakest first so the strongest box ends up on top where crops
    # overlap.
    for name, score, xyxy in sorted(boxes, key=lambda t: t[1]):
        if name == "not_crop":
            colour, verdict = (150, 150, 150), "rejected (not_crop)"
        else:
            bar = args.kamatis_bar if name == "kamatis" else args.bar
            if score >= bar:
                colour, verdict = (0, 170, 60), "ACCEPTED"
            else:
                colour, verdict = (255, 140, 0), f"below bar {bar}"

        draw.rectangle(xyxy, outline=colour, width=line)
        caption = f"{name} {score:.2f}  {verdict}"
        tb = draw.textbbox((0, 0), caption, font=f)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        ty = max(0, xyxy[1] - th - 12 * scale)
        draw.rectangle(
            [xyxy[0], ty, xyxy[0] + tw + 14 * scale, ty + th + 10 * scale],
            fill=colour,
        )
        draw.text((xyxy[0] + 7 * scale, ty + 5 * scale), caption,
                  fill=(255, 255, 255), font=f)
        print(f"  {name:<12} {score:.3f}  {verdict}")

    if not boxes:
        print("  (no boxes at all, even at draw floor "
              f"{args.conf} -- the model sees nothing here)")

    out = args.out or str(ROOT / f"annotated_{pathlib.Path(args.image).stem}.jpg")
    image.save(out, quality=92)
    print("-" * 78)
    print(f"saved: {out}")


if __name__ == "__main__":
    main()