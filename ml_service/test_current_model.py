import sys
from pathlib import Path
from ultralytics import YOLO

# Root all paths at this script's folder so it works from any CWD.
HERE = Path(__file__).resolve().parent

# Our current 3-class model (kamatis / lettuce / not_kamatis).
model = YOLO(HERE / 'farmspot_3class_best.pt')

# Optional CLI arg: the image to test. Defaults to test.jpg like first_detect.py.
image_path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / 'test.jpg'

result = model(image_path)
result = result[0]

print(f'image: {image_path}')
print(f'classes: {result.names}')
print('detections:')
for box in result.boxes:
    class_id = int(box.cls)
    name = result.names[class_id]
    confidence = float(box.conf)
    x1, y1, x2, y2 = [int(v) for v in box.xyxy[0]]
    print(f'  {name}: {confidence:.2f}  box=[{x1}, {y1}, {x2}, {y2}]')

if not result.boxes:
    print('  (no detections above default threshold)')

# Save an annotated COPY of the image with boxes, labels, and confidence drawn.
out_name = HERE / 'annotated_current_model.jpg'
result.save(str(out_name))
print(f'saved annotated copy: {out_name}')