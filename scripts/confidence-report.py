import cv2
import base64
from inference_sdk import InferenceHTTPClient

client = InferenceHTTPClient(api_url="http://localhost:9001", api_key="BvdnAQD1Qwzg2MLpNOS5")

VIDEO = "test-video.mp4"
MODEL = "open-guard-pass/1"

cap = cv2.VideoCapture(VIDEO)
fps = cap.get(cv2.CAP_PROP_FPS)
frame_num = 0
confidences = []
class_counts = {}

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break
    if frame_num % int(fps) == 0:
        _, buf = cv2.imencode(".jpg", frame)
        result = client.infer(base64.b64encode(buf).decode(), model_id=MODEL)
        for p in result.get("predictions", []):
            confidences.append(p["confidence"])
            class_counts[p["class"]] = class_counts.get(p["class"], 0) + 1
    frame_num += 1

cap.release()

print(f"Sampled {frame_num // int(fps)} frames — {len(confidences)} total detections\n")

print("--- Confidence threshold breakdown ---")
for threshold in [0.5, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]:
    kept = sum(1 for c in confidences if c >= threshold)
    print(f"  {threshold}  →  {kept} detections")

print("\n--- Detections by class ---")
for cls, count in sorted(class_counts.items(), key=lambda x: -x[1]):
    print(f"  {cls}: {count}")
