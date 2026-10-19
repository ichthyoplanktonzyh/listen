#!/usr/bin/env python3
"""Fake external tool for the normalized rich-stage command protocols.

It serves all three stages. The stage is selected with the
``LISTEN_GEN_FAKE_RICH_STAGE`` environment variable
(``sense-groups``, ``acoustics``, or ``prosody``). The argv layout matches the
command protocol of that stage:

* sense-groups: ``<script> {input}``
* acoustics:    ``<script> {media} {timeline}``
* prosody:      ``<script> {input}``

The success modes read the exact input document and write one normalized
``listen_gen.<stage>-result.v1`` document to stdout. Failure modes exercise
the degradable rich-stage path.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def _read_input(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_observation(observed: str | None, document: object) -> None:
    if not observed:
        return
    Path(observed).write_text(
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )


def _sense_groups_result(input_path: Path) -> dict[str, object]:
    transcript = _read_input(input_path)
    groups = []
    for sentence in transcript["sentences"]:
        groups.append(
            {
                "sentence_index": sentence["index"],
                "group_index": 0,
                "start_token_index": 0,
                "end_token_index_exclusive": len(sentence["tokens"]),
                "confidence": 0.9,
                "head_token_index": 0,
                "sources": ["rule"],
            }
        )
    return {
        "schema": "listen_gen.sense-group-result.v1",
        "provider": {"id": "command-sense-groups", "version": "1"},
        "config_sha256": "sha256:" + "1" * 64,
        "groups": groups,
    }


def _acoustics_result(media_path: Path, timeline_path: Path) -> dict[str, object]:
    timeline = _read_input(timeline_path)
    measurements = []
    for word in timeline["words"]:
        span = word["end_ms"] - word["start_ms"]
        measurements.append(
            {
                "sentence_index": word["sentence_index"],
                "token_index": word["token_index"],
                "energy": {"rms_dbfs": -24.0, "local_baseline_dbfs": -26.0,
                           "delta_db": 2.0, "prominence": 0.5},
                "pitch": {"median_f0_hz": 170.0, "local_baseline_f0_hz": 165.0,
                          "delta_semitones": 0.5, "range_semitones": 1.0,
                          "prominence": 0.45, "reset_after": 0.2},
                "duration": {"duration_ms": span, "local_ratio": 1.1},
                "voiced_frame_ratio": 0.8,
            }
        )
    return {
        "schema": "listen_gen.acoustics-result.v1",
        "provider": {"id": "command-acoustics", "version": "1"},
        "config_sha256": "sha256:" + "2" * 64,
        "sample_rate_hz": 16000,
        "measurements": measurements,
    }


def _prosody_result(input_path: Path) -> dict[str, object]:
    evidence = _read_input(input_path)
    anchors = []
    for measurement in evidence["measurements"]:
        anchors.append(
            {
                "sentence_index": measurement["sentence_index"],
                "token_index": measurement["token_index"],
                "lexical_stress": "unknown",
                "realized_prominence": 0.5,
                "utterance_role": "unmarked",
                "evidence": ["energy"],
                "confidence": 0.5,
            }
        )
    chunks = []
    for group in evidence["groups"]:
        chunks.append(
            {
                "sentence_index": group["sentence_index"],
                "chunk_index": group["group_index"],
                "start_token_index": group["start_token_index"],
                "end_token_index_exclusive": group["end_token_index_exclusive"],
                "confidence": 0.8,
            }
        )
    if not chunks:
        for sentence in evidence["sentences"]:
            chunks.append(
                {
                    "sentence_index": sentence["index"],
                    "chunk_index": 0,
                    "start_token_index": 0,
                    "end_token_index_exclusive": len(sentence["tokens"]),
                    "confidence": 0.8,
                }
            )
    return {
        "schema": "listen_gen.prosody-result.v1",
        "provider": {"id": "command-prosody", "version": "1"},
        "config_sha256": "sha256:" + "3" * 64,
        "uses_sense_groups": bool(evidence["groups"]),
        "anchors": anchors,
        "chunks": chunks,
    }


def main() -> int:
    stage = os.environ.get("LISTEN_GEN_FAKE_RICH_STAGE", "sense-groups")
    mode = os.environ.get("LISTEN_GEN_FAKE_RICH_MODE", "success")
    observed = os.environ.get("LISTEN_GEN_FAKE_RICH_OBSERVED")

    if len(sys.argv) >= 3:
        # The acoustics protocol always receives {media} {timeline}; the
        # other two protocols receive a single {input} path.
        stage = "acoustics"
        media_path = Path(sys.argv[1])
        timeline_path = Path(sys.argv[2])
        input_path = None
    else:
        input_path = Path(sys.argv[1])
        media_path = None
        timeline_path = None

    if mode == "hang":
        _write_observation(
            observed,
            {
                "stage": stage,
                "media_path": str(media_path) if media_path else None,
                "pid": os.getpid(),
            },
        )
        while True:
            time.sleep(3600)
    _write_observation(
        observed,
        {
            "stage": stage,
            "media_path": str(media_path) if media_path else None,
            "pid": os.getpid(),
        },
    )
    if mode == "fail":
        print("rich-secret-must-not-leak", file=sys.stderr)
        return 27
    if mode == "sleep":
        time.sleep(30)
        return 0
    if mode == "invalid-json":
        print('{"provider_raw":"must-not-leak-invalid-json"', file=sys.stdout)
        return 0
    if mode == "flood":
        sys.stdout.buffer.write(b"x" * (17 * 1024 * 1024))
        return 0
    if mode == "mutate-self":
        path = Path(__file__)
        path.write_text(path.read_text(encoding="utf-8") + "\n# mutated\n", encoding="utf-8")

    if stage == "sense-groups":
        document = _sense_groups_result(input_path)
    elif stage == "acoustics":
        document = _acoustics_result(media_path, timeline_path)
    else:
        document = _prosody_result(input_path)
    print(
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        file=sys.stdout,
    )
    return 0


raise SystemExit(main())
