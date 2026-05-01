from __future__ import annotations

import argparse
import base64
import os
import re
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from inference_sdk import InferenceHTTPClient
from inference_sdk.webrtc import StreamConfig, VideoFileSource, VideoMetadata

_ENV_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]{16,256}$")
_SLUG_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{1,127}$")
_HOST_PATTERN = re.compile(r"^https://[A-Za-z0-9.-]{3,255}$")


def _validate_non_empty(value: Any, field_name: str, min_len: int, max_len: int) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field_name} must be a string.")
    trimmed = value.strip()
    if len(trimmed) < min_len or len(trimmed) > max_len:
        raise ValueError(f"{field_name} must be between {min_len} and {max_len} characters.")
    return trimmed


def _validate_api_url(value: str) -> str:
    url = _validate_non_empty(value, "ROBOFLOW_API_URL", 12, 255)
    if not _HOST_PATTERN.match(url):
        raise ValueError("ROBOFLOW_API_URL must be a valid https URL.")
    return url


def _validate_api_key(value: str) -> str:
    key = _validate_non_empty(value, "ROBOFLOW_API_KEY", 16, 256)
    if not _ENV_KEY_PATTERN.match(key):
        raise ValueError("ROBOFLOW_API_KEY format is invalid.")
    return key


def _validate_slug(value: str, field_name: str) -> str:
    slug = _validate_non_empty(value, field_name, 2, 128)
    if not _SLUG_PATTERN.match(slug):
        raise ValueError(f"{field_name} must be lowercase letters, numbers, or hyphens.")
    return slug


def _validate_plan(value: str) -> str:
    return _validate_non_empty(value, "ROBOFLOW_PLAN", 3, 64)


def _validate_region(value: str) -> str:
    return _validate_non_empty(value, "ROBOFLOW_REGION", 2, 16).lower()


def _validate_video_path(value: str) -> Path:
    path_text = _validate_non_empty(value, "video path", 3, 4096)
    path = Path(path_text).expanduser().resolve()
    if path.suffix.lower() not in {".mp4", ".mov", ".mkv", ".avi"}:
        raise ValueError("video path must be a supported video file extension (.mp4/.mov/.mkv/.avi).")
    if not path.exists() or not path.is_file():
        raise ValueError(f"video file does not exist: {path}")
    if path.stat().st_size <= 0:
        raise ValueError(f"video file is empty: {path}")
    return path


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run Roboflow workflow on a local video file.")
    parser.add_argument("--video", required=True, help="Absolute or relative path to input video.")
    parser.add_argument("--workspace", help="Roboflow workspace slug. Defaults to ROBOFLOW_WORKSPACE.")
    parser.add_argument("--workflow", help="Roboflow workflow slug. Defaults to ROBOFLOW_WORKFLOW.")
    parser.add_argument(
        "--output-video",
        default="",
        help="Optional output video path. If omitted, only prediction data is streamed/logged.",
    )
    parser.add_argument(
        "--api-url",
        default=os.getenv("ROBOFLOW_API_URL", "https://serverless.roboflow.com"),
        help="Roboflow API URL. Defaults to ROBOFLOW_API_URL or serverless endpoint.",
    )
    parser.add_argument(
        "--plan",
        default=os.getenv("ROBOFLOW_PLAN", "webrtc-gpu-medium"),
        help="Requested Roboflow stream plan.",
    )
    parser.add_argument(
        "--region",
        default=os.getenv("ROBOFLOW_REGION", "us"),
        help="Requested Roboflow region.",
    )
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    api_key_raw = os.getenv("ROBOFLOW_API_KEY", "")
    workspace_raw = args.workspace or os.getenv("ROBOFLOW_WORKSPACE", "")
    workflow_raw = args.workflow or os.getenv("ROBOFLOW_WORKFLOW", "")

    try:
        video_path = _validate_video_path(args.video)
        api_url = _validate_api_url(args.api_url)
        api_key = _validate_api_key(api_key_raw)
        workspace = _validate_slug(workspace_raw, "ROBOFLOW_WORKSPACE")
        workflow = _validate_slug(workflow_raw, "ROBOFLOW_WORKFLOW")
        plan = _validate_plan(args.plan)
        region = _validate_region(args.region)
    except ValueError as exc:
        parser.error(str(exc))
        return

    output_video_path: Path | None = None
    if args.output_video.strip():
        output_video_text = _validate_non_empty(args.output_video, "output video path", 3, 4096)
        output_video_path = Path(output_video_text).expanduser().resolve()
        if output_video_path.suffix.lower() != ".mp4":
            parser.error("output video path must be an .mp4 file.")
            return
        output_video_path.parent.mkdir(parents=True, exist_ok=True)

    client = InferenceHTTPClient.init(api_url=api_url, api_key=api_key)
    source = VideoFileSource(str(video_path), realtime_processing=False)

    config = StreamConfig(
        stream_output=[],
        data_output=["predictions"] + (["output_image"] if output_video_path else []),
        requested_plan=plan,
        requested_region=region,
    )

    session = client.webrtc.stream(
        source=source,
        workflow=workflow,
        workspace=workspace,
        image_input="image",
        config=config,
    )

    frames: list[tuple[float, int, np.ndarray]] = []

    @session.on_data()
    def handle_data(data: dict[str, Any], metadata: VideoMetadata) -> None:
        predictions = data.get("predictions")
        if predictions is not None:
            count = len(predictions.get("predictions", [])) if isinstance(predictions, dict) else 0
            print(f"Processed frame {metadata.frame_id} | predictions={count}")
        else:
            print(f"Processed frame {metadata.frame_id} | predictions=0")

        if not output_video_path:
            return

        output_image = data.get("output_image")
        if not isinstance(output_image, dict):
            return

        encoded = output_image.get("value")
        if not isinstance(encoded, str) or not encoded:
            return

        try:
            decoded = base64.b64decode(encoded)
            frame = cv2.imdecode(np.frombuffer(decoded, np.uint8), cv2.IMREAD_COLOR)
        except Exception:
            return

        if frame is None or frame.size == 0:
            return

        timestamp_ms = float(metadata.pts) * float(metadata.time_base) * 1000.0
        frames.append((timestamp_ms, int(metadata.frame_id), frame))

    session.run()

    if not output_video_path:
        print("Completed stream (prediction data only).")
        return

    if not frames:
        print("Completed stream but no output video frames were returned.")
        return

    frames.sort(key=lambda item: item[1])
    fps = 30.0
    if len(frames) > 1:
        elapsed_seconds = (frames[-1][0] - frames[0][0]) / 1000.0
        if elapsed_seconds > 0:
            fps = (len(frames) - 1) / elapsed_seconds

    height, width = frames[0][2].shape[:2]
    writer = cv2.VideoWriter(
        str(output_video_path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError(f"Failed to open video writer for {output_video_path}")

    for _, _, frame in frames:
        writer.write(frame)
    writer.release()

    print(f"Wrote {len(frames)} processed frames to {output_video_path} at {fps:.2f} FPS.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted by user.", file=sys.stderr)
        raise SystemExit(130)
