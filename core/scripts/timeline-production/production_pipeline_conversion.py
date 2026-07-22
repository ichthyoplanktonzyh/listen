from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from lltimeline_common import align_asr_words_to_tokens, tokenize, word_token_indexes
from production_pipeline_common import load_json, now_ms, stable_id
from production_pipeline_report import write_production_report

SCHEMA = "llplayer.timeline.v1"

def ms(value: float | int | None) -> int | None:
    if value is None:
        return None
    return int(round(float(value) * 1000))


def default_whisperx_bin() -> str | None:
    production_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_TIMELINE_PRODUCTION_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/timeline-production"),
        )
    )
    candidate = production_root / "venv" / "bin" / "whisperx"
    return str(candidate) if candidate.exists() else None


def report_lltimeline(args: argparse.Namespace) -> int:
    report = write_production_report(Path(args.input), Path(args.output))
    print(
        json.dumps(
            {
                "output": args.output,
                "segments": report["segment_count"],
                "words": report["active_word_count"],
                "ready_for_manual_review": report["ready_for_manual_review"],
            },
            sort_keys=True,
        )
    )
    return 0


def convert_whisperx(args: argparse.Namespace) -> int:
    source = load_json(Path(args.input))
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
        aligned = align_asr_words_to_tokens(words, tokens)
        for tok_i, mapped in enumerate(aligned):
            if mapped is None:
                skipped_words.append(
                    {"segment_index": segment_index, "token_index": token_indexes[tok_i], "reason": "no_asr_match"}
                )
                continue
            word_start_ms = ms(mapped.get("start"))
            word_end_ms = ms(mapped.get("end"))
            if word_start_ms is None or word_end_ms is None or word_end_ms <= word_start_ms:
                skipped_words.append(
                    {
                        "segment_index": segment_index,
                        "token_index": token_indexes[tok_i],
                        "word": mapped.get("word"),
                        "reason": "timing_missing",
                    }
                )
                continue
            timings.append(
                {
                    "sentence_id": sentence_id,
                    "token_index": token_indexes[tok_i],
                    "text": str(mapped.get("word") or "").strip(),
                    "start_ms": word_start_ms,
                    "end_ms": word_end_ms,
                    "confidence": mapped.get("score"),
                    "timing_source": "forced_aligned",
                    "provider_id": args.algorithm_id,
                    "provider_version": args.algorithm_version,
                }
            )

    if not segments:
        raise SystemExit("no valid WhisperX segments were converted")
    if not timings:
        raise SystemExit("no valid WhisperX word timings were converted")
    artifacts = [
        {
            "kind": "alignment_diagnostics",
            "provider_id": args.algorithm_id,
            "provider_version": args.algorithm_version,
            "payload": {
                "input": str(args.input),
                "skipped_words": skipped_words,
            },
        }
    ]
    if args.preprocessing_artifacts:
        preprocessing = load_json(Path(args.preprocessing_artifacts))
        artifacts.append(
            {
                "kind": "preprocessing",
                "provider_id": "llplayernext-production-pipeline",
                "provider_version": "phase3-v1",
                "payload": preprocessing,
            }
        )

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
        "artifacts": artifacts,
    }
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    Path(args.output).write_text(output, encoding="utf-8")
    print(json.dumps({"output": args.output, "segments": len(segments), "words": len(timings)}, sort_keys=True))
    return 0


