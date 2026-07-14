from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

from production_pipeline_common import file_sha256, now_ms

def extract_audio(input_path: str, output: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg not found")
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        input_path,
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-sample_fmt",
        "s16",
        str(output),
    ]
    subprocess.run(command, check=True)


def prepare_audio(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "audio-16k-mono.wav"
    extract_audio(args.input, output)
    print(json.dumps({"audio_path": str(output)}, sort_keys=True))
    return 0


def prepare_media(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_audio = output_dir / "audio-16k-mono.wav"
    vocals_audio = output_dir / "vocals-16k-mono.wav"
    started_at = now_ms()
    extract_audio(args.input, raw_audio)

    isolation: dict[str, Any] = {"enabled": False}
    selected_audio = raw_audio
    if args.vocal_isolation_command:
        command = args.vocal_isolation_command.format(
            input=str(raw_audio),
            output=str(vocals_audio),
            output_dir=str(output_dir),
        )
        subprocess.run(command, shell=True, check=True)
        if not vocals_audio.exists():
            raise SystemExit(f"vocal isolation command did not create {vocals_audio}")
        selected_audio = vocals_audio
        isolation = {
            "enabled": True,
            "command": args.vocal_isolation_command,
            "output_path": str(vocals_audio),
            "sha256": file_sha256(vocals_audio),
        }

    artifacts = {
        "input_path": args.input,
        "started_at_ms": started_at,
        "completed_at_ms": now_ms(),
        "raw_audio": {
            "path": str(raw_audio),
            "sample_rate_hz": 16000,
            "channels": 1,
            "sample_format": "s16",
            "sha256": file_sha256(raw_audio),
        },
        "selected_audio_path": str(selected_audio),
        "vocal_isolation": isolation,
    }
    artifact_path = output_dir / "preprocessing-artifacts.json"
    artifact_path.write_text(json.dumps(artifacts, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "audio_path": str(selected_audio),
                "artifacts_path": str(artifact_path),
                "vocal_isolation": isolation["enabled"],
            },
            sort_keys=True,
        )
    )
    return 0


