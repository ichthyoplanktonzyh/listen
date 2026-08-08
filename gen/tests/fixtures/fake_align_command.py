#!/usr/bin/env python3
"""Fake external word aligner for the normalized command alignment protocol.

It reads the exact emitted subtitle payload at ``{transcript}``, records it to
an observation file when configured, and writes one
``listen_gen.align-result.v1`` document to stdout with one timing per word
token. Failure modes exercise the degradable alignment path.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def main() -> int:
    media_path = sys.argv[1]
    transcript_path = Path(sys.argv[2])
    observed = os.environ.get("LISTEN_GEN_FAKE_ALIGN_OBSERVED")
    mode = os.environ.get("LISTEN_GEN_FAKE_ALIGN_MODE", "success")

    transcript = json.loads(transcript_path.read_text(encoding="utf-8"))
    if observed:
        Path(observed).write_text(
            json.dumps(
                {
                    "schema": transcript.get("schema"),
                    "language": transcript.get("language"),
                    "media_path": media_path,
                    "sentences": transcript["sentences"],
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
    if mode == "fail":
        print("must-not-leak-align", file=sys.stderr)
        return 23
    if mode == "sleep":
        time.sleep(30)
        return 0
    if mode == "invalid-json":
        print('{"schema": "listen_gen.align-result.v1", "words": [', file=sys.stdout)
        return 0
    if mode == "flood":
        print("x" * (20 * 1024 * 1024), file=sys.stdout)
        return 0

    words = []
    for sentence in transcript["sentences"]:
        word_tokens = [token for token in sentence["tokens"] if token["kind"] == "word"]
        for offset, token in enumerate(word_tokens):
            spread = len(word_tokens) - 1
            start = sentence["start_ms"] + offset * 10
            end = sentence["end_ms"] - (spread - offset) * 10
            words.append(
                {
                    "sentence_index": sentence["index"],
                    "text": token["text"],
                    "start_ms": start,
                    "end_ms": end,
                    "confidence": 0.9,
                }
            )
    document = {
        "schema": "listen_gen.align-result.v1",
        "provider": {"id": "command-aligner", "version": "1"},
        "config_sha256": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "words": words,
    }
    print(
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        file=sys.stdout,
    )
    return 0


raise SystemExit(main())
