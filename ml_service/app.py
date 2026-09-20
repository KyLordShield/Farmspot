import io
import time
import pathlib
from PIL import Image
from fastapi import FastAPI, UploadFile
from ultralytics import YOLO

app = FastAPI()
model = YOLO('C:/xampp/htdocs/Farmspot/runs/detect/train-4/weights/best.pt')
MIN_CONF = 0.6  # demo default: keeps everyday phone shots alive; raising it kills apples but also dim tomatoes
UPLOADS = pathlib.Path('C:/xampp/htdocs/Farmspot/ml_service/uploads')

@app.post('/detect')
async def detect(file: UploadFile):
    photo_bytes = await file.read()             # the raw 0s-and-1s of the photo
    UPLOADS.mkdir(exist_ok=True)                # keep a copy of every upload
    (UPLOADS / f'{time.time_ns()}.jpg').write_bytes(photo_bytes)
    image = Image.open(io.BytesIO(photo_bytes)) # decode it into a real image
    results = model(image)                      # now YOLO can read it
    detections = []
    for box in results[0].boxes:
        if float(box.conf) < MIN_CONF:
            continue
        detections.append({
            'name': results[0].names[int(box.cls)],
            'confidence': round(float(box.conf), 3),
            'box': [int(x) for x in box.xyxy[0]],
        })
    return {'detections': detections}