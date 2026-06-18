#!/usr/bin/env python3
"""Convert external benchmark corpora into LLTimeline JSON v1.

The script never downloads or vendors restricted corpora. It only converts data
that already exists on the developer machine.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from typing import Any


SCHEMA = "llplayer.timeline.v1"
WORD_RE = re.compile(r"['’]?[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*(?:['’])?")


def now_ms() -> int:
    return int(time.time() * 1000)


def stable_id(namespace: str, value: str) -> str:
    return hashlib.sha256(f"{namespace}:{value}".encode("utf-8")).hexdigest()


def sample_to_ms(sample: int, sample_rate: int) -> int:
    return int(round(sample * 1000 / sample_rate))


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
        tokens.append(
            {
                "index": index,
                "kind": "whitespace" if is_space else "punctuation",
                "text": value,
                "normalized": None,
                "start_char": absolute_start + start,
                "end_char": absolute_start + cursor,
            }
        )
        index += 1
    return index


def parse_boundary_file(path: Path, label: str) -> list[tuple[int, int, str]]:
    rows: list[tuple[int, int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(maxsplit=2)
        if len(parts) != 3:
            raise ValueError(f"{path}:{line_number}: expected '<start_sample> <end_sample> <{label}>'")
        try:
            start = int(parts[0])
            end = int(parts[1])
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: boundary samples must be integers") from error
        if end <= start:
            raise ValueError(f"{path}:{line_number}: end sample must be greater than start sample")
        rows.append((start, end, parts[2].strip()))
    if not rows:
        raise ValueError(f"{path}: no {label} rows found")
    return rows


def parse_word_boundary_file(path: Path) -> tuple[list[tuple[int, int, str]], list[dict[str, Any]]]:
    rows: list[tuple[int, int, str]] = []
    skipped: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(maxsplit=2)
        if len(parts) != 3:
            raise ValueError(f"{path}:{line_number}: expected '<start_sample> <end_sample> <word>'")
        try:
            start = int(parts[0])
            end = int(parts[1])
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: boundary samples must be integers") from error
        word = parts[2].strip()
        if end <= start:
            skipped.append(
                {
                    "path": str(path),
                    "line": line_number,
                    "word": word,
                    "start_sample": start,
                    "end_sample": end,
                    "reason": "non_positive_duration",
                }
            )
            continue
        rows.append((start, end, word))
    if not rows:
        raise ValueError(f"{path}: no valid word rows found")
    return rows, skipped


def map_words_to_token_indexes(
    words: list[tuple[int, int, str]],
    tokens: list[dict[str, Any]],
    utterance_id: str,
) -> tuple[list[int | None], list[dict[str, Any]]]:
    word_tokens = [token for token in tokens if token["kind"] == "word"]
    indexes: list[int | None] = []
    skipped: list[dict[str, Any]] = []
    cursor = 0
    for row_index, (_, _, word) in enumerate(words):
        normalized = normalize_word(word)
        match = None
        for candidate_cursor in range(cursor, len(word_tokens)):
            if word_tokens[candidate_cursor]["normalized"] == normalized:
                match = candidate_cursor
                break
        if match is None:
            skipped.append(
                {
                    "utterance": utterance_id,
                    "word_row_index": row_index,
                    "word": word,
                    "reason": "not_found_in_transcript",
                }
            )
            indexes.append(None)
            continue
        indexes.append(word_tokens[match]["index"])
        cursor = match + 1
    return indexes, skipped


def read_timit_text(txt_path: Path | None, words: list[tuple[int, int, str]]) -> str:
    if txt_path and txt_path.exists():
        line = txt_path.read_text(encoding="utf-8").strip()
        parts = line.split(maxsplit=2)
        if len(parts) == 3:
            return parts[2].strip()
    return " ".join(word for _, _, word in words)


def make_non_overlapping_words(
    rows: list[dict[str, Any]],
    utterance_id: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    adjusted = [dict(row) for row in rows]
    adjustments: list[dict[str, Any]] = []
    for index in range(1, len(adjusted)):
        previous = adjusted[index - 1]
        current = adjusted[index]
        if current["start_ms"] >= previous["end_ms"]:
            continue
        boundary = int(round((previous["end_ms"] + current["start_ms"]) / 2))
        boundary = max(previous["start_ms"] + 1, min(boundary, current["end_ms"] - 1))
        if boundary <= previous["start_ms"] or boundary >= current["end_ms"]:
            raise ValueError(
                f"{utterance_id}: cannot repair overlapping words "
                f"{previous['text']!r}/{current['text']!r}"
            )
        adjustments.append(
            {
                "utterance": utterance_id,
                "left_word": previous["text"],
                "right_word": current["text"],
                "left_original_end_ms": previous["end_ms"],
                "right_original_start_ms": current["start_ms"],
                "adjusted_boundary_ms": boundary,
            }
        )
        previous["end_ms"] = boundary
        current["start_ms"] = boundary
    return adjusted, adjustments


def sibling(path: Path, suffix: str) -> Path | None:
    for candidate in (path.with_suffix(suffix.upper()), path.with_suffix(suffix.lower())):
        if candidate.exists():
            return candidate
    return None


def timit_to_lltimeline(args: argparse.Namespace) -> int:
    input_dir = Path(args.input_dir)
    wrd_files = sorted(input_dir.rglob("*.WRD")) + sorted(input_dir.rglob("*.wrd"))
    if args.limit:
        wrd_files = wrd_files[: args.limit]
    if not wrd_files:
        raise ValueError(f"{input_dir}: no TIMIT .WRD files found")

    created_at = now_ms()
    media_fingerprint = args.media_fingerprint or stable_id(
        "timit-benchmark",
        "|".join(str(path.relative_to(input_dir)) for path in wrd_files),
    )
    media_id = args.media_id or stable_id("media", media_fingerprint)
    track_id = args.track_id or stable_id("subtitle-track", f"{media_id}:timit-gold")
    word_timeline_id = args.word_timeline_id or stable_id("word-timeline", f"{track_id}:timit-gold")
    phone_timeline_id = args.phone_timeline_id or stable_id("phone-timeline", f"{track_id}:timit-gold")
    segments: list[dict[str, Any]] = []
    words_out: list[dict[str, Any]] = []
    phones_out: list[dict[str, Any]] = []
    utterances: list[dict[str, Any]] = []
    boundary_adjustments: list[dict[str, Any]] = []
    skipped_word_rows: list[dict[str, Any]] = []
    cursor_ms = 0

    for utterance_index, wrd_path in enumerate(wrd_files):
        utterance_id = str(wrd_path.relative_to(input_dir))
        words, skipped_words = parse_word_boundary_file(wrd_path)
        skipped_word_rows.extend(skipped_words)
        txt_path = sibling(wrd_path, ".TXT")
        phn_path = sibling(wrd_path, ".PHN")
        wav_path = sibling(wrd_path, ".WAV")
        text = read_timit_text(txt_path, words)
        tokens = tokenize(text)
        token_indexes, unmapped_words = map_words_to_token_indexes(words, tokens, utterance_id)
        skipped_word_rows.extend(unmapped_words)
        utterance_start = min(start for start, _, _ in words)
        utterance_end = max(end for _, end, _ in words)
        segment_start_ms = cursor_ms + sample_to_ms(utterance_start, args.sample_rate)
        segment_end_ms = cursor_ms + sample_to_ms(utterance_end, args.sample_rate)
        sentence_id = stable_id("subtitle-sentence", f"{track_id}:{wrd_path.relative_to(input_dir)}")
        segments.append(
            {
                "id": sentence_id,
                "index": utterance_index,
                "start_ms": segment_start_ms,
                "end_ms": segment_end_ms,
                "text": text,
                "display_text": text,
                "tokens": tokens,
            }
        )
        utterance_words = []
        for word_index, (start, end, word) in enumerate(words):
            token_index = token_indexes[word_index]
            if token_index is None:
                continue
            utterance_words.append(
                {
                    "sentence_id": sentence_id,
                    "token_index": token_index,
                    "text": word,
                    "start_ms": cursor_ms + sample_to_ms(start, args.sample_rate),
                    "end_ms": cursor_ms + sample_to_ms(end, args.sample_rate),
                    "confidence": 1.0,
                    "timing_source": "human_gold",
                    "provider_id": "timit",
                    "provider_version": "ldc93s1-word",
                }
            )
        adjusted_words, adjustments = make_non_overlapping_words(utterance_words, utterance_id)
        words_out.extend(adjusted_words)
        boundary_adjustments.extend(adjustments)
        if phn_path and phn_path.exists():
            for phone_index, (start, end, phone) in enumerate(parse_boundary_file(phn_path, "phone")):
                phones_out.append(
                    {
                        "sentence_id": sentence_id,
                        "phone_index": phone_index,
                        "label": phone,
                        "start_ms": cursor_ms + sample_to_ms(start, args.sample_rate),
                        "end_ms": cursor_ms + sample_to_ms(end, args.sample_rate),
                        "provider_id": "timit",
                        "provider_version": "ldc93s1-phone",
                    }
                )
        utterances.append(
            {
                "relative_wrd_path": str(wrd_path.relative_to(input_dir)),
                "relative_txt_path": str(txt_path.relative_to(input_dir)) if txt_path else None,
                "relative_phn_path": str(phn_path.relative_to(input_dir)) if phn_path else None,
                "relative_wav_path": str(wav_path.relative_to(input_dir)) if wav_path else None,
                "offset_ms": cursor_ms,
            }
        )
        cursor_ms += sample_to_ms(utterance_end, args.sample_rate) + args.utterance_gap_ms

    document: dict[str, Any] = {
        "schema": SCHEMA,
        "metadata": {
            "created_at_ms": created_at,
            "generator": {
                "id": "llplayernext-benchmark-datasets",
                "version": "phase4-v1",
                "mode": "benchmark_gold_import",
            },
            "media": {
                "id": media_id,
                "fingerprint": media_fingerprint,
                "path": str(input_dir),
                "title": args.media_title,
                "duration_ms": cursor_ms - args.utterance_gap_ms,
            },
            "language": args.language,
            "human_reviewed": True,
            "extra": {
                "track_id": track_id,
                "track_fingerprint": stable_id("track-fingerprint", json.dumps(segments, sort_keys=True)),
                "track_source": "timit-wrd-phn",
                "benchmark_dataset": "TIMIT",
            },
        },
        "segments": segments,
        "word_timelines": [
            {
                "id": word_timeline_id,
                "track_id": track_id,
                "media_id": media_id,
                "algorithm_id": "timit-human-gold",
                "algorithm_version": "ldc93s1",
                "config_hash": f"sample-rate-{args.sample_rate}",
                "parent_timeline_id": None,
                "created_by": "user",
                "status": "published",
                "metrics_json": {
                    "dataset": "TIMIT",
                    "utterance_count": len(segments),
                    "word_count": len(words_out),
                    "sample_rate_hz": args.sample_rate,
                },
                "words": words_out,
                "created_at_ms": created_at,
                "updated_at_ms": created_at,
            }
        ],
        "active_word_timeline_id": word_timeline_id,
        "phone_timelines": [],
        "active_phone_timeline_id": None,
        "chunk_timelines": [],
        "active_chunk_timeline_id": None,
        "artifacts": [
            {
                "kind": "benchmark_dataset_manifest",
                "provider_id": "llplayernext-benchmark-datasets",
                "provider_version": "phase4-v1",
                "payload": {
                    "dataset": "TIMIT",
                    "input_dir": str(input_dir),
                    "utterances": utterances,
                    "boundary_adjustment_count": len(boundary_adjustments),
                    "boundary_adjustment_samples": boundary_adjustments[:20],
                    "skipped_word_row_count": len(skipped_word_rows),
                    "skipped_word_row_samples": skipped_word_rows[:20],
                    "license_note": "TIMIT is restricted; keep source corpus outside Git and distribution artifacts.",
                },
            }
        ],
    }
    if phones_out:
        document["phone_timelines"] = [
            {
                "id": phone_timeline_id,
                "track_id": track_id,
                "media_id": media_id,
                "algorithm_id": "timit-human-gold",
                "algorithm_version": "ldc93s1-phone",
                "config_hash": f"sample-rate-{args.sample_rate}",
                "parent_timeline_id": None,
                "created_by": "user",
                "status": "published",
                "phones": phones_out,
                "created_at_ms": created_at,
                "updated_at_ms": created_at,
            }
        ]
        document["active_phone_timeline_id"] = phone_timeline_id

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "segments": len(segments), "words": len(words_out), "phones": len(phones_out)}, sort_keys=True))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    timit = subcommands.add_parser("timit-to-lltimeline", help="convert local TIMIT .WRD/.PHN files to LLTimeline JSON v1")
    timit.add_argument("--input-dir", required=True)
    timit.add_argument("--output", required=True)
    timit.add_argument("--media-title", default="TIMIT benchmark gold")
    timit.add_argument("--media-fingerprint")
    timit.add_argument("--media-id")
    timit.add_argument("--track-id")
    timit.add_argument("--word-timeline-id")
    timit.add_argument("--phone-timeline-id")
    timit.add_argument("--language", default="en")
    timit.add_argument("--sample-rate", type=int, default=16000)
    timit.add_argument("--utterance-gap-ms", type=int, default=1000)
    timit.add_argument("--limit", type=int)
    timit.set_defaults(func=timit_to_lltimeline)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.func(args)
    except (OSError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
