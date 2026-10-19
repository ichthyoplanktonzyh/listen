#!/usr/bin/env python3
"""Download wav2vec2 phoneme model via huggingface_hub with progress reporting.

Outputs JSON lines to stdout for progress tracking:
  {"status": "downloading", "progress": 0.0, "message": "Starting download..."}
  {"status": "downloading", "progress": 45.2, "message": "model.safetensors (580/1260 MB)"}
  {"status": "completed", "progress": 100.0, "path": "/path/to/model"}
  {"status": "failed", "message": "error details"}
"""
import argparse
import json
import sys
import os
import threading
import time


def emit(obj):
    print(json.dumps(obj), flush=True)


def watch_progress(model_dir, expected_bytes, stop_event):
    """Poll the model directory size and emit progress updates."""
    while not stop_event.is_set():
        try:
            total = 0
            for dirpath, _, filenames in os.walk(model_dir):
                for f in filenames:
                    fp = os.path.join(dirpath, f)
                    try:
                        total += os.path.getsize(fp)
                    except OSError:
                        pass
            if expected_bytes > 0:
                pct = min(99.0, total / expected_bytes * 100.0)
                mb = total / (1024 * 1024)
                total_mb = expected_bytes / (1024 * 1024)
                emit(
                    {
                        "status": "downloading",
                        "progress": round(pct, 1),
                        "message": f"Downloading... ({mb:.0f}/{total_mb:.0f} MB)",
                    }
                )
        except Exception:
            pass
        stop_event.wait(3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument(
        "--repo-id",
        default="facebook/wav2vec2-lv-60-espeak-cv-ft",
    )
    parser.add_argument("--expected-bytes", type=int, default=1_260_000_000)
    args = parser.parse_args()

    model_dir = args.model_dir

    if os.path.isdir(model_dir) and os.path.isfile(
        os.path.join(model_dir, "config.json")
    ):
        emit(
            {
                "status": "completed",
                "progress": 100.0,
                "path": model_dir,
                "message": "Model already installed",
            }
        )
        return

    emit({"status": "downloading", "progress": 0.0, "message": "Starting download..."})

    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        emit(
            {
                "status": "failed",
                "message": "huggingface_hub not installed. Run: pip3 install huggingface_hub",
            }
        )
        sys.exit(1)

    try:
        os.makedirs(model_dir, exist_ok=True)

        stop_event = threading.Event()
        watcher = threading.Thread(
            target=watch_progress,
            args=(model_dir, args.expected_bytes, stop_event),
            daemon=True,
        )
        watcher.start()

        snapshot_download(
            repo_id=args.repo_id,
            local_dir=model_dir,
            local_dir_use_symlinks=False,
        )

        stop_event.set()
        watcher.join(timeout=1)

        if os.path.isfile(os.path.join(model_dir, "config.json")):
            emit(
                {
                    "status": "completed",
                    "progress": 100.0,
                    "path": model_dir,
                    "message": "Download complete",
                }
            )
        else:
            emit(
                {
                    "status": "failed",
                    "message": "Download finished but config.json not found",
                }
            )
            sys.exit(1)
    except KeyboardInterrupt:
        emit({"status": "failed", "message": "Download cancelled"})
        sys.exit(1)
    except Exception as e:
        emit({"status": "failed", "message": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
