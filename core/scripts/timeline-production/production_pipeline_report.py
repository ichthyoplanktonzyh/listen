from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from production_pipeline_common import active_word_timeline, load_json, now_ms

SCHEMA = "llplayer.timeline.v1"

def word_timing_quality(words: list[dict[str, Any]]) -> dict[str, Any]:
    by_sentence: dict[str, list[dict[str, Any]]] = {}
    for word in words:
        by_sentence.setdefault(str(word.get("sentence_id")), []).append(word)
    overlap_count = 0
    large_gap_count = 0
    max_gap_ms = 0
    for sentence_words in by_sentence.values():
        sentence_words.sort(key=lambda word: (int(word.get("start_ms", 0)), int(word.get("end_ms", 0))))
        for left, right in zip(sentence_words, sentence_words[1:]):
            gap = int(right.get("start_ms", 0)) - int(left.get("end_ms", 0))
            if gap < 0:
                overlap_count += 1
            elif gap > 750:
                large_gap_count += 1
            max_gap_ms = max(max_gap_ms, gap)
    confidences = [
        float(word["confidence"])
        for word in words
        if isinstance(word.get("confidence"), (int, float))
    ]
    provider_ids = sorted({str(word.get("provider_id", "unknown")) for word in words})
    return {
        "word_count": len(words),
        "sentence_count": len(by_sentence),
        "overlap_count": overlap_count,
        "large_gap_count": large_gap_count,
        "max_gap_ms": max_gap_ms,
        "confidence_count": len(confidences),
        "average_confidence": round(sum(confidences) / len(confidences), 6) if confidences else None,
        "provider_ids": provider_ids,
        "valid": overlap_count == 0,
    }


def build_production_report(document: dict[str, Any], input_path: str | None = None) -> dict[str, Any]:
    if document.get("schema") != SCHEMA:
        raise SystemExit(f"unsupported LLTimeline schema: {document.get('schema')!r}")
    segments = document.get("segments") or []
    token_word_count = sum(
        1
        for segment in segments
        for token in segment.get("tokens", [])
        if isinstance(token, dict) and token.get("kind") == "word"
    )
    timeline = active_word_timeline(document)
    words = timeline.get("words", []) if timeline else []
    quality = word_timing_quality(words)
    artifacts = document.get("artifacts") or []
    return {
        "report_version": 1,
        "generated_at_ms": now_ms(),
        "input": input_path,
        "schema": document["schema"],
        "media": document.get("metadata", {}).get("media", {}),
        "active_word_timeline_id": document.get("active_word_timeline_id"),
        "segment_count": len(segments),
        "token_word_count": token_word_count,
        "word_timeline_count": len(document.get("word_timelines") or []),
        "active_word_count": quality["word_count"],
        "word_coverage": round(quality["word_count"] / token_word_count, 6) if token_word_count else None,
        "quality": quality,
        "artifact_kinds": [
            artifact.get("kind", "unknown")
            for artifact in artifacts
            if isinstance(artifact, dict)
        ],
        "human_reviewed": document.get("metadata", {}).get("human_reviewed", False),
        "ready_for_manual_review": quality["valid"] and quality["word_count"] > 0,
    }


def write_production_report(input_path: Path, output_path: Path) -> dict[str, Any]:
    document = load_json(input_path)
    report = build_production_report(document, str(input_path))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


