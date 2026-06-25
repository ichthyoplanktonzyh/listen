#!/usr/bin/env python3
"""Download wav2vec2 phoneme model via huggingface_hub with progress reporting.

Outputs JSON lines to stdout for progress tracking:
  {"status": "downloading", "progress": 0.0, "message": "Starting download..."}
  {"status": "downloading", "progress": 45.2, "message": "Downloading model files..."}
  {"status": "completed", "progress": 100.0, "path": "/path/to/model"}
  {"status": "failed", "message": "error details"}
"""
import argparse
import json
import sys
import os


def emit(obj):
    print(json.dumps(obj), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument(
        "--repo-id",
        default="facebook/wav2vec2-lv-60-espeak-cv-ft",
    )
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

        emit(
            {
                "status": "downloading",
                "progress": 5.0,
                "message": "Downloading model files...",
            }
        )

        snapshot_download(
            repo_id=args.repo_id,
            local_dir=model_dir,
            local_dir_use_symlinks=False,
        )

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
