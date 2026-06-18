#!/usr/bin/env python3
"""Local heavy timeline production helpers.

This script intentionally lives outside the app bundle path. It is a production
sidecar utility for local research and content production, and its stable output
is an LLTimeline JSON resource.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


SCHEMA = "llplayer.timeline.v1"
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)?")


def now_ms() -> int:
    return int(time.time() * 1000)


def stable_id(namespace: str, value: str) -> str:
    return hashlib.sha256(f"{namespace}:{value}".encode("utf-8")).hexdigest()


def ms(value: float | int | None) -> int | None:
    if value is None:
        return None
    return int(round(float(value) * 1000))


def normalize_word(value: str) -> str:
    return value.strip().strip(".,!?;:\"“”‘’()[]{}").replace("’", "'").lower()


def tokenize(text: str) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    index = 0
    cursor = 0
    for match in WORD_RE.finditer(text):
        if match.start() > cursor:
            index = append_non_word_tokens(tokens, text[cursor:match.start()], cursor, index)
        value = match.group(0)
        tokens.append(
            {
                "index": index,
                "kind": "word",
                "text": value,
                "normalized": normalize_word(value),
                "start_char": match.start(),
                "end_char": match.end(),
            }
        )
        index += 1
        cursor = match.end()
    if cursor < len(text):
        append_non_word_tokens(tokens, text[cursor:], cursor, index)
    return tokens


def append_non_word_tokens(
    tokens: list[dict[str, Any]],
    text: str,
    absolute_start: int,
    index: int,
) -> int:
    cursor = 0
    while cursor < len(text):
        start = cursor
        is_space = text[cursor].isspace()
        while cursor < len(text) and text[cursor].isspace() == is_space:
            cursor += 1
        value = text[start:cursor]
        kind = "whitespace" if is_space else "punctuation"
        tokens.append(
            {
                "index": index,
                "kind": kind,
                "text": value,
                "normalized": None,
                "start_char": absolute_start + start,
                "end_char": absolute_start + cursor,
            }
        )
        index += 1
    return index


def word_token_indexes(tokens: list[dict[str, Any]]) -> list[int]:
    return [token["index"] for token in tokens if token["kind"] == "word"]


def convert_whisperx(args: argparse.Namespace) -> int:
    source = json.loads(Path(args.input).read_text(encoding="utf-8"))
    raw_segments = source.get("segments")
    if not isinstance(raw_segments, list) or not raw_segments:
        raise SystemExit("WhisperX JSON must contain a non-empty segments array")

    created_at = now_ms()
    media_id = args.media_id or stable_id("media", args.media_fingerprint)
    track_id = args.track_id or stable_id("subtitle-track", f"{media_id}:{args.media_fingerprint}:whisperx")
    timeline_id = args.timeline_id or stable_id(
        "word-timeline",
        f"{track_id}:{args.algorithm_id}:{args.algorithm_version}:{args.config_hash}",
    )
    segments: list[dict[str, Any]] = []
    timings: list[dict[str, Any]] = []
    skipped_words: list[dict[str, Any]] = []

    for segment_index, segment in enumerate(raw_segments):
        start_ms = ms(segment.get("start"))
        end_ms = ms(segment.get("end"))
        text = str(segment.get("text") or "").strip()
        if start_ms is None or end_ms is None or end_ms <= start_ms or not text:
            skipped_words.append({"segment_index": segment_index, "reason": "invalid_segment"})
            continue
        sentence_id = stable_id("subtitle-sentence", f"{track_id}:{segment_index}:{start_ms}:{end_ms}:{text}")
        tokens = tokenize(text)
        segments.append(
            {
                "id": sentence_id,
                "index": segment_index,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": text,
                "display_text": text,
                "tokens": tokens,
            }
        )

        token_indexes = word_token_indexes(tokens)
        words = segment.get("words") or []
        if not isinstance(words, list):
            skipped_words.append({"segment_index": segment_index, "reason": "invalid_words"})
            continue
        for word_index, word in enumerate(words):
            if word_index >= len(token_indexes) or not isinstance(word, dict):
                skipped_words.append(
                    {
                        "segment_index": segment_index,
                        "word_index": word_index,
                        "reason": "token_missing",
                    }
                )
                continue
            word_start_ms = ms(word.get("start"))
            word_end_ms = ms(word.get("end"))
            if word_start_ms is None or word_end_ms is None or word_end_ms <= word_start_ms:
                skipped_words.append(
                    {
                        "segment_index": segment_index,
                        "word_index": word_index,
                        "word": word.get("word"),
                        "reason": "timing_missing",
                    }
                )
                continue
            timings.append(
                {
                    "sentence_id": sentence_id,
                    "token_index": token_indexes[word_index],
                    "text": str(word.get("word") or "").strip(),
                    "start_ms": word_start_ms,
                    "end_ms": word_end_ms,
                    "confidence": word.get("score"),
                    "timing_source": "forced_aligned",
                    "provider_id": args.algorithm_id,
                    "provider_version": args.algorithm_version,
                }
            )

    if not segments:
        raise SystemExit("no valid WhisperX segments were converted")
    if not timings:
        raise SystemExit("no valid WhisperX word timings were converted")

    document = {
        "schema": SCHEMA,
        "metadata": {
            "created_at_ms": created_at,
            "generator": {
                "id": "llplayernext-production-pipeline",
                "version": "phase3-v1",
                "mode": "production_engine",
            },
            "media": {
                "id": media_id,
                "fingerprint": args.media_fingerprint,
                "path": args.media_path,
                "title": args.media_title,
                "duration_ms": args.duration_ms,
            },
            "language": args.language,
            "human_reviewed": False,
            "extra": {
                "track_id": track_id,
                "track_fingerprint": stable_id("track-fingerprint", json.dumps(segments, sort_keys=True)),
                "track_source": "whisperx-json",
                "pipeline": "whisperx-json-import",
            },
        },
        "segments": segments,
        "word_timelines": [
            {
                "id": timeline_id,
                "track_id": track_id,
                "media_id": media_id,
                "algorithm_id": args.algorithm_id,
                "algorithm_version": args.algorithm_version,
                "config_hash": args.config_hash,
                "parent_timeline_id": None,
                "created_by": "algorithm",
                "status": args.status,
                "metrics_json": {
                    "source": "whisperx-json",
                    "converted_at_ms": created_at,
                    "segment_count": len(segments),
                    "word_count": len(timings),
                    "skipped_words": skipped_words,
                },
                "words": timings,
                "created_at_ms": created_at,
                "updated_at_ms": created_at,
            }
        ],
        "active_word_timeline_id": timeline_id if args.status == "active" else None,
        "phone_timelines": [],
        "active_phone_timeline_id": None,
        "chunk_timelines": [],
        "active_chunk_timeline_id": None,
        "artifacts": [
            {
                "kind": "alignment_diagnostics",
                "provider_id": args.algorithm_id,
                "provider_version": args.algorithm_version,
                "payload": {
                    "input": str(args.input),
                    "skipped_words": skipped_words,
                },
            }
        ],
    }
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    Path(args.output).write_text(output, encoding="utf-8")
    print(json.dumps({"output": args.output, "segments": len(segments), "words": len(timings)}, sort_keys=True))
    return 0


def prepare_audio(args: argparse.Namespace) -> int:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg not found")
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "audio-16k-mono.wav"
    command = [
        ffmpeg,
        "-y",
        "-i",
        args.input,
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
    print(json.dumps({"audio_path": str(output)}, sort_keys=True))
    return 0


def doctor(_: argparse.Namespace) -> int:
    checks = {
        "ffmpeg": shutil.which("ffmpeg") is not None,
        "python": True,
        "whisperx": importlib.util.find_spec("whisperx") is not None,
        "torch": importlib.util.find_spec("torch") is not None,
    }
    print(json.dumps(checks, sort_keys=True))
    return 0 if checks["ffmpeg"] else 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    check = subcommands.add_parser("doctor", help="check local production dependencies")
    check.set_defaults(func=doctor)

    audio = subcommands.add_parser("prepare-audio", help="extract normalized wav for alignment")
    audio.add_argument("--input", required=True)
    audio.add_argument("--output-dir", required=True)
    audio.set_defaults(func=prepare_audio)

    convert = subcommands.add_parser("from-whisperx-json", help="convert WhisperX JSON to LLTimeline v1")
    convert.add_argument("--input", required=True)
    convert.add_argument("--output", required=True)
    convert.add_argument("--media-fingerprint", required=True)
    convert.add_argument("--media-title", required=True)
    convert.add_argument("--media-path")
    convert.add_argument("--media-id")
    convert.add_argument("--track-id")
    convert.add_argument("--timeline-id")
    convert.add_argument("--duration-ms", type=int)
    convert.add_argument("--language", default="en")
    convert.add_argument("--algorithm-id", default="whisperx")
    convert.add_argument("--algorithm-version", default="large-v3-align")
    convert.add_argument("--config-hash", default="default")
    convert.add_argument("--status", choices=["candidate", "active", "archived"], default="active")
    convert.set_defaults(func=convert_whisperx)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
