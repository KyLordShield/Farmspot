from ultralytics import YOLO

model = YOLO('yolov8n.pt')

result = model('test.jpg')
result = result[0]

for box in result.boxes:
    class_id = int(box.cls)
    name = result.names[class_id]
    confidence = float(box.conf)

    print(f'{name}: {confidence:.2f}')

result.save('annonated.jpg')