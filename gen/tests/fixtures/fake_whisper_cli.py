#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


def _option(argv: list[str], name: str) -> str | None:
    if name in argv:
        return argv[argv.index(name) + 1]
    return None


def main() -> int:
    argv = sys.argv[1:]
    mode = os.environ.get("LISTEN_GEN_FAKE_WHISPER_MODE", "success")
    observed = os.environ.get("LISTEN_GEN_FAKE_WHISPER_OBSERVED")
    model_path = _option(argv, "-m")
    media_path = _option(argv, "-f")
    output_prefix = _option(argv, "-of")
    language = _option(argv, "-l")
    observation = {
        "argv": list(argv),
        "pid": os.getpid(),
        "model_path": model_path,
        "media_path": media_path,
        "output_prefix": output_prefix,
        "language": language,
        "translate": "-tr" in argv,
    }
    if observed:
        Path(observed).write_text(json.dumps(observation), encoding="utf-8")
    if mode == "fail":
        print("must-not-leak", file=sys.stderr)
        return 23
    if mode == "invalid-json":
        if output_prefix:
            Path(f"{output_prefix}.json").write_text(
                '{"result": {"language": "en"}, "transcription": [',
                encoding="utf-8",
            )
        return 0
    if mode == "invalid-shape":
        if output_prefix:
            Path(f"{output_prefix}.json").write_text(
                json.dumps(
                    {
                        "result": {"language": "en"},
                        "transcription": [
                            {"offsets": {"from": 900, "to": 100}, "text": "bad"}
                        ],
                    }
                ),
                encoding="utf-8",
            )
        return 0
    if mode == "no-output":
        return 0
    if mode == "sleep":
        time.sleep(30)
        return 0
    if mode == "hang-with-child":
        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(3600)"]
        )
        if observed:
            observation["child_pid"] = child.pid
            Path(observed).write_text(json.dumps(observation), encoding="utf-8")
        while True:
            time.sleep(3600)
    detected_language = os.environ.get("LISTEN_GEN_FAKE_WHISPER_LANGUAGE", "en")
    if output_prefix:
        Path(f"{output_prefix}.json").write_text(
            json.dumps(
                {
                    "result": {"language": detected_language},
                    "transcription": [
                        {"offsets": {"from": 120, "to": 840}, "text": "  Example text  "},
                        {"offsets": {"from": 900, "to": 2100}, "text": " Second line. "},
                    ],
                }
            ),
            encoding="utf-8",
        )
    return 0


raise SystemExit(main())
