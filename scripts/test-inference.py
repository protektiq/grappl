import cv2
import base64
from inference_sdk import InferenceHTTPClient

client = InferenceHTTPClient(api_url="http://localhost:9001", api_key="BvdnAQD1Qwzg2MLpNOS5")

VIDEO = "test-video.mp4"
MODEL = "open-guard-pass/1"

cap = cv2.VideoCapture(VIDEO)
fps = cap.get(cv2.CAP_PROP_FPS)
frame_interval = int(fps)  # 1 frame per second

frame_num = 0
results = []

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break
    if frame_num % frame_interval == 0:
        _, buf = cv2.imencode(".jpg", frame)
        b64 = base64.b64encode(buf).decode("utf-8")
        result = client.infer(b64, model_id=MODEL)
        ts = frame_num / fps
        predictions = result.get("predictions", [])
        print(f"t={ts:.1f}s  detections={len(predictions)}")
        for p in predictions:
            print(f"  {p['class']} {p['confidence']:.2f}  bbox=({p['x']:.0f},{p['y']:.0f},{p['width']:.0f},{p['height']:.0f})")
        results.append((ts, result))
    frame_num += 1

cap.release()
print(f"\nDone. Sampled {len(results)} frames, total detections={sum(len(r.get('predictions',[])) for _,r in results)}.")
