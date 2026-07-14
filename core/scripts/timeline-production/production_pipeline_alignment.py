from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from lltimeline_common import align_asr_words_to_tokens, word_key, word_token_indexes
from production_pipeline_common import active_word_timeline, load_json, now_ms, stable_id

SCHEMA = "llplayer.timeline.v1"

def build_mfa_alignment_request(
    document: dict[str, Any],
    audio_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    segments = []
    for segment in document.get("segments") or []:
        if not isinstance(segment, dict):
            continue
        words = [
            str(token.get("text") or "").strip()
            for token in segment.get("tokens", [])
            if isinstance(token, dict) and token.get("kind") == "word" and str(token.get("text") or "").strip()
        ]
        if not words:
            continue
        segments.append(
            {
                "index": int(segment["index"]),
                "text": str(segment.get("text") or "").strip(),
                "words": words,
                "start_ms": int(segment["start_ms"]),
                "end_ms": int(segment["end_ms"]),
            }
        )
    if not segments:
        raise SystemExit("no word-bearing LLTimeline segments available for MFA")
    request = {
        "audio_path": str(audio_path),
        "segments": segments,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return request


def segment_word_keys(document: dict[str, Any]) -> dict[tuple[int, int], tuple[str, int, str]]:
    keys: dict[tuple[int, int], tuple[str, int, str]] = {}
    for segment in document.get("segments") or []:
        if not isinstance(segment, dict):
            continue
        token_indexes = word_token_indexes(segment.get("tokens", []))
        for word_index, token_index in enumerate(token_indexes):
            token = next(
                (
                    item
                    for item in segment.get("tokens", [])
                    if isinstance(item, dict) and int(item.get("index", -1)) == int(token_index)
                ),
                None,
            )
            text = str(token.get("text") if isinstance(token, dict) else "").strip()
            keys[(int(segment["index"]), word_index)] = (str(segment["id"]), int(token_index), text)
    return keys


def timeline_word_map(timeline: dict[str, Any]) -> dict[tuple[str, int], dict[str, Any]]:
    return {
        word_key(word): dict(word)
        for word in timeline.get("words", [])
        if isinstance(word, dict) and "sentence_id" in word and "token_index" in word
    }


def sorted_timeline_words(document: dict[str, Any], words: dict[tuple[str, int], dict[str, Any]]) -> list[dict[str, Any]]:
    ordered: list[dict[str, Any]] = []
    for segment in sorted(document.get("segments") or [], key=lambda item: int(item.get("index", 0))):
        for token_index in word_token_indexes(segment.get("tokens", [])):
            word = words.get((str(segment["id"]), int(token_index)))
            if word:
                ordered.append(word)
    return ordered


def add_aligned_word_timeline(
    document: dict[str, Any],
    aligned: dict[str, Any],
    *,
    algorithm_id: str,
    algorithm_version: str,
    config_hash: str,
    status: str,
) -> dict[str, Any]:
    parent = active_word_timeline(document)
    if not parent:
        raise SystemExit("cannot add aligned timeline without an active source word timeline")

    created_at = now_ms()
    media = document.get("metadata", {}).get("media", {})
    media_id = str(parent.get("media_id") or media.get("id") or stable_id("media", "unknown"))
    track_id = str(parent.get("track_id") or document.get("metadata", {}).get("extra", {}).get("track_id") or media_id)
    timeline_id = stable_id(
        "word-timeline",
        f"{track_id}:{algorithm_id}:{algorithm_version}:{config_hash}:{parent.get('id')}",
    )

    segment_keys = segment_word_keys(document)
    merged_words = timeline_word_map(parent)
    replaced = 0
    skipped = []

    for row in aligned.get("timings", []):
        if not isinstance(row, dict):
            continue
        segment_index = int(row.get("segment_index", -1))
        word_index = int(row.get("word_index", -1))
        key = segment_keys.get((segment_index, word_index))
        if not key:
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "word_key_missing"})
            continue
        sentence_id, token_index, token_text = key
        if row.get("skipped"):
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "aligner_skipped"})
            continue
        start_ms = row.get("start_ms")
        end_ms = row.get("end_ms")
        if not isinstance(start_ms, int) or not isinstance(end_ms, int) or end_ms <= start_ms:
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "invalid_timing"})
            continue
        merged_words[(sentence_id, token_index)] = {
            "sentence_id": sentence_id,
            "token_index": token_index,
            "text": str(row.get("text") or token_text),
            "start_ms": start_ms,
            "end_ms": end_ms,
            "confidence": row.get("score"),
            "timing_source": "forced_aligned",
            "provider_id": aligned.get("provider_id", algorithm_id),
            "provider_version": aligned.get("provider_version", algorithm_version),
        }
        replaced += 1

    words = sorted_timeline_words(document, merged_words)
    timeline = {
        "id": timeline_id,
        "track_id": track_id,
        "media_id": media_id,
        "algorithm_id": algorithm_id,
        "algorithm_version": algorithm_version,
        "config_hash": config_hash,
        "parent_timeline_id": parent.get("id"),
        "created_by": "algorithm",
        "status": status,
        "metrics_json": {
            "source": "post_alignment",
            "provider_id": aligned.get("provider_id", algorithm_id),
            "provider_version": aligned.get("provider_version", algorithm_version),
            "source_timeline_id": parent.get("id"),
            "input_word_count": len(parent.get("words", [])),
            "aligned_timing_count": len(aligned.get("timings", [])),
            "replaced_word_count": replaced,
            "fallback_word_count": max(0, len(words) - replaced),
            "skipped": skipped,
            "diagnostics": aligned.get("diagnostics", {}),
        },
        "words": words,
        "created_at_ms": created_at,
        "updated_at_ms": created_at,
    }
    document.setdefault("word_timelines", []).append(timeline)
    if status == "active":
        if parent.get("status") == "active":
            parent["status"] = "candidate"
        document["active_word_timeline_id"] = timeline_id
    document.setdefault("artifacts", []).append(
        {
            "kind": "post_alignment",
            "provider_id": algorithm_id,
            "provider_version": algorithm_version,
            "payload": {
                "timeline_id": timeline_id,
                "source_timeline_id": parent.get("id"),
                "replaced_word_count": replaced,
                "fallback_word_count": max(0, len(words) - replaced),
            },
        }
    )
    return timeline


def record_post_alignment_failure(
    document_path: Path,
    *,
    aligner: str,
    error: str,
) -> None:
    document = load_json(document_path)
    document.setdefault("artifacts", []).append(
        {
            "kind": "post_alignment_failure",
            "provider_id": aligner,
            "provider_version": "fallback-chain-v1",
            "payload": {
                "error": error,
                "recorded_at_ms": now_ms(),
            },
        }
    )
    document_path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


