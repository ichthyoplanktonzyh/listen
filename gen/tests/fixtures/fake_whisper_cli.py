#!/usr/bin/env python3
"""Fake whisper-cli for deterministic offline tests.

It mirrors the whisper.cpp CLI surface that listen-gen uses: ``-m``/``-f``/
``-oj``/``-ojf``/``-of``/``-l`` and ``-tr``. In ``-oj`` mode it writes a
segment-only transcription document; in ``-ojf`` (full JSON) mode it also
writes per-token text/offsets/probability arrays so the first-class whisper.cpp
aligner has real token timing to parse.

Every invocation records itself into the observation file (as a ``runs`` list
plus last-run convenience fields), so multi-stage pipelines (ASR then
alignment) can be asserted exactly.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

SEGMENTS = [
    {"from": 120, "to": 840, "text": "Example text"},
    {"from": 900, "to": 2100, "text": "Second line."},
]

TOKENS = {
    0: [
        {"text": " Example", "from": 120, "to": 480, "p": 0.99},
        {"text": " text", "from": 500, "to": 840, "p": 0.98},
    ],
    1: [
        {"text": " Second", "from": 900, "to": 1500, "p": 0.97},
        {"text": " line.", "from": 1550, "to": 2100, "p": 0.95},
    ],
}


def _option(argv: list[str], name: str) -> str | None:
    if name in argv:
        return argv[argv.index(name) + 1]
    return None


def _success_document(language: str, full: bool) -> dict[str, object]:
    transcription = []
    for index, segment in enumerate(SEGMENTS):
        entry: dict[str, object] = {
            "offsets": {"from": segment["from"], "to": segment["to"]},
            "text": segment["text"],
        }
        if full:
            entry["tokens"] = [
                {
                    "text": token["text"],
                    "offsets": {"from": token["from"], "to": token["to"]},
                    "p": token["p"],
                }
                for token in TOKENS[index]
            ]
        transcription.append(entry)
    return {"result": {"language": language}, "transcription": transcription}


def main() -> int:
    argv = sys.argv[1:]
    mode = os.environ.get("LISTEN_GEN_FAKE_WHISPER_MODE", "success")
    observed = os.environ.get("LISTEN_GEN_FAKE_WHISPER_OBSERVED")
    model_path = _option(argv, "-m")
    media_path = _option(argv, "-f")
    output_prefix = _option(argv, "-of")
    language = _option(argv, "-l")
    full_json = "-ojf" in argv

    # ``align-*`` modes apply only to the alignment run (full JSON); the ASR
    # run of the same pipeline keeps succeeding so alignment degradation is
    # tested in isolation.
    if mode.startswith("align-") and not full_json:
        mode = "success"
    handler_mode = mode[6:] if mode.startswith("align-") else mode

    observation = {
        "argv": list(argv),
        "pid": os.getpid(),
        "model_path": model_path,
        "media_path": media_path,
        "output_prefix": output_prefix,
        "language": language,
        "translate": "-tr" in argv,
    }
    if handler_mode == "hang-with-child":
        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(3600)"]
        )
        observation["child_pid"] = child.pid
    if observed:
        runs: list[dict[str, object]] = []
        existing = Path(observed)
        if existing.is_file():
            try:
                previous = json.loads(existing.read_text(encoding="utf-8"))
                prior = previous.get("runs")
                if isinstance(prior, list):
                    runs = [item for item in prior if isinstance(item, dict)]
            except (OSError, ValueError):
                runs = []
        runs.append(observation)
        document = dict(observation)
        document["runs"] = runs
        existing.write_text(json.dumps(document), encoding="utf-8")

    if handler_mode == "fail":
        print("must-not-leak", file=sys.stderr)
        return 23
    if handler_mode == "invalid-json":
        if output_prefix:
            Path(f"{output_prefix}.json").write_text(
                '{"result": {"language": "en"}, "transcription": [',
                encoding="utf-8",
            )
        return 0
    if handler_mode == "invalid-shape":
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
    if handler_mode == "no-output":
        return 0
    if handler_mode == "delete-model":
        if model_path:
            Path(model_path).unlink()
    if handler_mode == "sleep":
        time.sleep(30)
        return 0
    if handler_mode == "hang-with-child":
        while True:
            time.sleep(3600)
    if handler_mode == "unknown-tokens":
        if output_prefix and full_json:
            document = _success_document("en", full=True)
            for segment in document["transcription"]:
                segment["tokens"] = [
                    {"text": " Garbage", "offsets": {"from": 0, "to": 100}, "p": 0.9}
                ]
            Path(f"{output_prefix}.json").write_text(
                json.dumps(document), encoding="utf-8"
            )
        return 0
    if handler_mode == "split-words":
        if output_prefix and full_json:
            document = _success_document("en", full=True)
            document["transcription"][0]["tokens"] = [
                {"text": " Exam", "offsets": {"from": 120, "to": 300}, "p": 0.99},
                {"text": "ple", "offsets": {"from": 300, "to": 480}, "p": 0.90},
                {"text": " text", "offsets": {"from": 500, "to": 840}, "p": 0.98},
            ]
            document["transcription"][1]["tokens"] = [
                {"text": " Sec", "offsets": {"from": 900, "to": 1100}, "p": 0.97},
                {"text": "ond", "offsets": {"from": 1100, "to": 1500}, "p": 0.88},
                {"text": " line.", "offsets": {"from": 1550, "to": 2100}, "p": 0.95},
            ]
            Path(f"{output_prefix}.json").write_text(
                json.dumps(document), encoding="utf-8"
            )
        return 0
    if handler_mode == "oversize-file":
        if output_prefix and full_json:
            Path(f"{output_prefix}.json").write_bytes(
                b"x" * (16 * 1024 * 1024 + 1)
            )
        return 0
    detected_language = os.environ.get("LISTEN_GEN_FAKE_WHISPER_LANGUAGE", "en")
    if output_prefix:
        Path(f"{output_prefix}.json").write_text(
            json.dumps(_success_document(detected_language, full=full_json)),
            encoding="utf-8",
        )
    return 0


raise SystemExit(main())
