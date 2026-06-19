#!/usr/bin/env python3
"""Compare versioned LLPlayerNext word timeline resources."""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from lltimeline_common import normalize_word, word_key


THRESHOLDS_MS = (25, 50, 100, 200)


def fail(message: str) -> None:
    raise ValueError(message)


def read_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as error:
        fail(f"{path}: invalid JSON: {error}")


def require_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} requires non-empty text")
    return value.strip()


def require_int(value: Any, field: str) -> int:
    if not isinstance(value, int):
        fail(f"{field} requires an integer")
    return value


def timeline_words(value: Any, label: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        words = value.get("words")
    else:
        words = value
    if not isinstance(words, list) or not words:
        fail(f"{label}: requires a non-empty words array")
    normalized = []
    for index, word in enumerate(words):
        if not isinstance(word, dict):
            fail(f"{label}: words[{index}] must be an object")
        sentence_id = require_text(word.get("sentence_id"), f"{label}: words[{index}].sentence_id")
        token_index = require_int(word.get("token_index"), f"{label}: words[{index}].token_index")
        text = require_text(word.get("text"), f"{label}: words[{index}].text")
        start_ms = require_int(word.get("start_ms"), f"{label}: words[{index}].start_ms")
        end_ms = require_int(word.get("end_ms"), f"{label}: words[{index}].end_ms")
        if start_ms >= end_ms:
            fail(f"{label}: words[{index}] start_ms must be before end_ms")
        normalized.append(
            {
                **word,
                "sentence_id": sentence_id,
                "token_index": token_index,
                "text": text,
                "normalized_text": normalize_word(text),
                "start_ms": start_ms,
                "end_ms": end_ms,
            }
        )
    return normalized


def timeline_meta(value: Any, path: Path, words: list[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {
            "id": path.stem,
            "algorithm_id": "unknown",
            "algorithm_version": "unknown",
            "status": "unknown",
            "word_count": len(words),
        }
    return {
        "id": value.get("id", path.stem),
        "algorithm_id": value.get("algorithm_id", "unknown"),
        "algorithm_version": value.get("algorithm_version", "unknown"),
        "status": value.get("status", "unknown"),
        "word_count": len(words),
    }


def index_words(words: list[dict[str, Any]], label: str) -> dict[tuple[str, int], dict[str, Any]]:
    indexed = {}
    for word in words:
        key = word_key(word)
        if key in indexed:
            fail(f"{label}: duplicate word key {key}")
        indexed[key] = word
    return indexed


def round_float(value: float) -> float:
    return round(value, 6)


def stats(values: list[int]) -> dict[str, Any]:
    if not values:
        return {
            "count": 0,
            "mean": None,
            "median": None,
            "mean_abs": None,
            "median_abs": None,
            "p95_abs": None,
            "max_abs": None,
        }
    absolute = [abs(value) for value in values]
    return {
        "count": len(values),
        "mean": round_float(statistics.fmean(values)),
        "median": round_float(statistics.median(values)),
        "mean_abs": round_float(statistics.fmean(absolute)),
        "median_abs": round_float(statistics.median(absolute)),
        "p95_abs": percentile(absolute, 95),
        "max_abs": max(absolute),
    }


def percentile(values: list[int], percentile_value: int) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return round_float(float(ordered[0]))
    rank = (len(ordered) - 1) * percentile_value / 100
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    weight = rank - lower
    return round_float(ordered[lower] * (1 - weight) + ordered[upper] * weight)


def timeline_validity(words: list[dict[str, Any]]) -> dict[str, Any]:
    overlaps = []
    negative_gaps = []
    large_gaps = []
    by_sentence: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for word in words:
        by_sentence[word["sentence_id"]].append(word)
    for sentence_id, sentence_words in by_sentence.items():
        sentence_words.sort(key=lambda value: (value["start_ms"], value["end_ms"], value["token_index"]))
        for left, right in zip(sentence_words, sentence_words[1:]):
            gap = right["start_ms"] - left["end_ms"]
            row = {
                "sentence_id": sentence_id,
                "left_token_index": left["token_index"],
                "right_token_index": right["token_index"],
                "gap_ms": gap,
            }
            if gap < 0:
                overlaps.append(row)
                negative_gaps.append(row)
            elif gap > 750:
                large_gaps.append(row)
    return {
        "sentence_count": len(by_sentence),
        "overlap_count": len(overlaps),
        "negative_gap_count": len(negative_gaps),
        "large_gap_count": len(large_gaps),
        "valid": not overlaps,
        "sample_overlaps": overlaps[:10],
        "sample_large_gaps": large_gaps[:10],
    }


def provider_mix(words: list[dict[str, Any]]) -> dict[str, int]:
    return dict(Counter(str(word.get("provider_id", "unknown")) for word in words))


def confidence_summary(words: list[dict[str, Any]]) -> dict[str, Any]:
    values = [word.get("confidence") for word in words]
    numeric = [float(value) for value in values if isinstance(value, (int, float))]
    if not numeric:
        return {"count": 0, "mean": None, "min": None, "median": None}
    return {
        "count": len(numeric),
        "mean": round_float(statistics.fmean(numeric)),
        "min": round_float(min(numeric)),
        "median": round_float(statistics.median(numeric)),
    }


def matched_pairs(
    reference: list[dict[str, Any]],
    prediction: list[dict[str, Any]],
    *,
    reference_label: str,
    prediction_label: str,
) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    reference_index = index_words(reference, reference_label)
    prediction_index = index_words(prediction, prediction_label)
    pairs = []
    for key in sorted(reference_index):
        if key in prediction_index:
            pairs.append((reference_index[key], prediction_index[key]))
    return pairs


def text_mismatches(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> list[dict[str, Any]]:
    mismatches: list[dict[str, Any]] = []
    for reference, prediction in pairs:
        if reference["normalized_text"] == prediction["normalized_text"]:
            continue
        mismatches.append(
            {
                "sentence_id": reference["sentence_id"],
                "token_index": reference["token_index"],
                "reference_text": reference["text"],
                "candidate_text": prediction["text"],
                "reference_normalized": reference["normalized_text"],
                "candidate_normalized": prediction["normalized_text"],
            }
        )
    return mismatches


def offset_metrics(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> dict[str, Any]:
    start_offsets = [candidate["start_ms"] - base["start_ms"] for base, candidate in pairs]
    end_offsets = [candidate["end_ms"] - base["end_ms"] for base, candidate in pairs]
    duration_deltas = [
        (candidate["end_ms"] - candidate["start_ms"]) - (base["end_ms"] - base["start_ms"])
        for base, candidate in pairs
    ]
    return {
        "start_offset_ms": stats(start_offsets),
        "end_offset_ms": stats(end_offsets),
        "duration_delta_ms": stats(duration_deltas),
        "lead_lag_bias_start_ms": stats(start_offsets)["mean"],
        "lead_lag_bias_end_ms": stats(end_offsets)["mean"],
        "tail_lag_ms": tail_lag_metrics(pairs),
    }


def tail_lag_metrics(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> dict[str, Any]:
    last_pairs_by_sentence: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
    for base, candidate in pairs:
        sentence_id = base["sentence_id"]
        previous = last_pairs_by_sentence.get(sentence_id)
        if previous is None or base["token_index"] > previous[0]["token_index"]:
            last_pairs_by_sentence[sentence_id] = (base, candidate)
    end_offsets = [
        candidate["end_ms"] - base["end_ms"]
        for base, candidate in last_pairs_by_sentence.values()
    ]
    return {
        **stats(end_offsets),
        "positive_lag_count": sum(offset > 0 for offset in end_offsets),
        "sentence_count": len(end_offsets),
    }


def suspicious_words(
    pairs: list[tuple[dict[str, Any], dict[str, Any]]],
    threshold_ms: int,
) -> list[dict[str, Any]]:
    rows = []
    for base, candidate in pairs:
        start_offset = candidate["start_ms"] - base["start_ms"]
        end_offset = candidate["end_ms"] - base["end_ms"]
        duration_delta = (
            candidate["end_ms"] - candidate["start_ms"]
        ) - (base["end_ms"] - base["start_ms"])
        max_abs = max(abs(start_offset), abs(end_offset), abs(duration_delta))
        if max_abs < threshold_ms:
            continue
        rows.append(
            {
                "sentence_id": base["sentence_id"],
                "token_index": base["token_index"],
                "text": candidate["text"],
                "start_offset_ms": start_offset,
                "end_offset_ms": end_offset,
                "duration_delta_ms": duration_delta,
                "max_abs_offset_ms": max_abs,
            }
        )
    rows.sort(key=lambda value: (-value["max_abs_offset_ms"], value["sentence_id"], value["token_index"]))
    return rows[:50]


def gold_metrics(
    gold_words: list[dict[str, Any]],
    candidate_words: list[dict[str, Any]],
) -> dict[str, Any]:
    pairs = matched_pairs(
        gold_words,
        candidate_words,
        reference_label="gold",
        prediction_label="candidate",
    )
    start_errors = [candidate["start_ms"] - gold["start_ms"] for gold, candidate in pairs]
    end_errors = [candidate["end_ms"] - gold["end_ms"] for gold, candidate in pairs]

    def accuracy(errors: list[int], threshold: int) -> float:
        return round_float(sum(abs(value) <= threshold for value in errors) / len(errors)) if errors else 0.0

    return {
        "gold_word_count": len(gold_words),
        "matched_word_count": len(pairs),
        "coverage": round_float(len(pairs) / len(gold_words)) if gold_words else 0.0,
        "start_mae_ms": stats(start_errors)["mean_abs"],
        "start_median_abs_error_ms": stats(start_errors)["median_abs"],
        "end_mae_ms": stats(end_errors)["mean_abs"],
        "end_median_abs_error_ms": stats(end_errors)["median_abs"],
        "lead_bias_start_ms": stats(start_errors)["mean"],
        "lead_bias_end_ms": stats(end_errors)["mean"],
        "onset_accuracy": {f"within_{threshold}_ms": accuracy(start_errors, threshold) for threshold in THRESHOLDS_MS},
        "offset_accuracy": {f"within_{threshold}_ms": accuracy(end_errors, threshold) for threshold in THRESHOLDS_MS},
    }


def markdown_report(report: dict[str, Any]) -> str:
    weak = report["weak_metrics"]
    start = weak["offsets"]["start_offset_ms"]
    end = weak["offsets"]["end_offset_ms"]
    tail = weak["offsets"]["tail_lag_ms"]
    lines = [
        "# Word Timeline Evaluation",
        "",
        f"- Baseline: `{report['baseline']['id']}` ({report['baseline']['algorithm_id']} {report['baseline']['algorithm_version']})",
        f"- Candidate: `{report['candidate']['id']}` ({report['candidate']['algorithm_id']} {report['candidate']['algorithm_version']})",
        f"- Matched words: {weak['matched_word_count']}",
        f"- Start mean offset: {start['mean']} ms; median abs: {start['median_abs']} ms; P95 abs: {start['p95_abs']} ms",
        f"- End mean offset: {end['mean']} ms; median abs: {end['median_abs']} ms; P95 abs: {end['p95_abs']} ms",
        f"- Tail lag mean: {tail['mean']} ms; P95 abs: {tail['p95_abs']} ms",
        f"- Candidate overlaps: {weak['candidate_validity']['overlap_count']}",
        f"- Text mismatches: {weak['text_mismatch_count']} ({weak['text_mismatch_rate']})",
        f"- Suspicious words: {len(weak['suspicious_words'])}",
    ]
    if weak["text_mismatch_samples"]:
        lines.extend(["", "## Text Mismatches", ""])
        for word in weak["text_mismatch_samples"][:20]:
            lines.append(
                f"- {word['sentence_id']}:{word['token_index']} "
                f"`{word['reference_text']}` -> `{word['candidate_text']}`"
            )
    if "gold_metrics" in report:
        gold = report["gold_metrics"]
        lines.extend(
            [
                "",
                "## Gold Metrics",
                "",
                f"- Coverage: {gold['coverage']}",
                f"- Start MAE: {gold['start_mae_ms']} ms",
                f"- End MAE: {gold['end_mae_ms']} ms",
                f"- Onset <= 50 ms: {gold['onset_accuracy']['within_50_ms']}",
                f"- Offset <= 50 ms: {gold['offset_accuracy']['within_50_ms']}",
            ]
        )
    if weak["suspicious_words"]:
        lines.extend(["", "## Suspicious Words", ""])
        for word in weak["suspicious_words"][:20]:
            lines.append(
                f"- `{word['text']}` {word['sentence_id']}:{word['token_index']} "
                f"start={word['start_offset_ms']}ms end={word['end_offset_ms']}ms "
                f"duration={word['duration_delta_ms']}ms"
            )
    return "\n".join(lines) + "\n"


def build_compare_report(
    baseline_value: Any,
    candidate_value: Any,
    *,
    baseline_path: Path,
    candidate_path: Path,
    suspicious_threshold_ms: int,
    gold_value: Any | None = None,
    source_document: dict[str, Any] | None = None,
    production_report: dict[str, Any] | None = None,
) -> dict[str, Any]:
    baseline_words = timeline_words(baseline_value, "baseline")
    candidate_words = timeline_words(candidate_value, "candidate")
    pairs = matched_pairs(
        baseline_words,
        candidate_words,
        reference_label="baseline",
        prediction_label="candidate",
    )
    if not pairs:
        fail("baseline and candidate have no matching sentence_id/token_index word keys")
    mismatches = text_mismatches(pairs)
    weak = {
        "baseline_word_count": len(baseline_words),
        "candidate_word_count": len(candidate_words),
        "matched_word_count": len(pairs),
        "text_mismatch_count": len(mismatches),
        "text_mismatch_rate": round_float(len(mismatches) / len(pairs)),
        "text_mismatch_samples": mismatches[:20],
        "baseline_coverage": round_float(len(pairs) / len(baseline_words)),
        "candidate_coverage": round_float(len(pairs) / len(candidate_words)),
        "offsets": offset_metrics(pairs),
        "baseline_validity": timeline_validity(baseline_words),
        "candidate_validity": timeline_validity(candidate_words),
        "provider_mix": {
            "baseline": provider_mix(baseline_words),
            "candidate": provider_mix(candidate_words),
        },
        "confidence": {
            "baseline": confidence_summary(baseline_words),
            "candidate": confidence_summary(candidate_words),
        },
        "suspicious_words": suspicious_words(pairs, suspicious_threshold_ms),
    }
    report = {
        "report_version": 1,
        "baseline": timeline_meta(baseline_value, baseline_path, baseline_words),
        "candidate": timeline_meta(candidate_value, candidate_path, candidate_words),
        "weak_metrics": weak,
    }
    if source_document:
        report["source_document"] = source_document
    if production_report:
        report["production_report"] = production_report
    if gold_value:
        gold_words = timeline_words(gold_value, "gold")
        report["gold_metrics"] = gold_metrics(gold_words, candidate_words)
    return report


def compare(args: argparse.Namespace) -> dict[str, Any]:
    baseline_value = read_json(args.baseline)
    candidate_value = read_json(args.candidate)
    gold_value = read_json(args.gold) if args.gold else None
    return build_compare_report(
        baseline_value,
        candidate_value,
        baseline_path=args.baseline,
        candidate_path=args.candidate,
        suspicious_threshold_ms=args.suspicious_threshold_ms,
        gold_value=gold_value,
    )


def select_word_timeline(document: dict[str, Any], timeline_id: str, label: str) -> dict[str, Any]:
    timelines = document.get("word_timelines")
    if not isinstance(timelines, list) or not timelines:
        fail(f"{label}: LLTimeline document has no word_timelines")
    if timeline_id == "@active":
        active_id = document.get("active_word_timeline_id")
        if not active_id:
            fail(f"{label}: LLTimeline document has no active_word_timeline_id")
        timeline_id = active_id
    for timeline in timelines:
        if isinstance(timeline, dict) and timeline.get("id") == timeline_id:
            return timeline
    fail(f"{label}: word timeline {timeline_id!r} not found")


def compact_production_report(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail("production report must be an object")
    return {
        "report_version": value.get("report_version"),
        "input": value.get("input"),
        "word_coverage": value.get("word_coverage"),
        "ready_for_manual_review": value.get("ready_for_manual_review"),
        "quality": value.get("quality", {}),
    }


def compare_lltimeline(args: argparse.Namespace) -> dict[str, Any]:
    document = read_json(args.input)
    if not isinstance(document, dict) or document.get("schema") != "llplayer.timeline.v1":
        fail(f"{args.input}: expected LLTimeline JSON v1 document")
    baseline = select_word_timeline(document, args.baseline_timeline, "baseline")
    candidate = select_word_timeline(document, args.candidate_timeline, "candidate")
    gold = select_word_timeline(document, args.gold_timeline, "gold") if args.gold_timeline else None
    production_report = compact_production_report(read_json(args.production_report)) if args.production_report else None
    media = document.get("metadata", {}).get("media", {})
    return build_compare_report(
        baseline,
        candidate,
        baseline_path=Path(f"{args.input}#{baseline.get('id', 'baseline')}"),
        candidate_path=Path(f"{args.input}#{candidate.get('id', 'candidate')}"),
        suspicious_threshold_ms=args.suspicious_threshold_ms,
        gold_value=gold,
        source_document={
            "input": str(args.input),
            "schema": document.get("schema"),
            "media_id": media.get("id"),
            "media_title": media.get("title"),
            "baseline_timeline_id": baseline.get("id"),
            "candidate_timeline_id": candidate.get("id"),
            "gold_timeline_id": gold.get("id") if gold else None,
        },
        production_report=production_report,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    compare_parser = subparsers.add_parser("compare")
    compare_parser.add_argument("--baseline", type=Path, required=True)
    compare_parser.add_argument("--candidate", type=Path, required=True)
    compare_parser.add_argument("--gold", type=Path)
    compare_parser.add_argument("--json-output", type=Path)
    compare_parser.add_argument("--markdown-output", type=Path)
    compare_parser.add_argument("--suspicious-threshold-ms", type=int, default=200)
    document_parser = subparsers.add_parser("compare-lltimeline")
    document_parser.add_argument("--input", type=Path, required=True)
    document_parser.add_argument("--baseline-timeline", required=True)
    document_parser.add_argument("--candidate-timeline", required=True)
    document_parser.add_argument("--gold-timeline")
    document_parser.add_argument("--production-report", type=Path)
    document_parser.add_argument("--json-output", type=Path)
    document_parser.add_argument("--markdown-output", type=Path)
    document_parser.add_argument("--suspicious-threshold-ms", type=int, default=200)
    args = parser.parse_args()
    try:
        if args.command == "compare":
            report = compare(args)
        elif args.command == "compare-lltimeline":
            report = compare_lltimeline(args)
        else:
            fail(f"unknown command {args.command}")
        encoded = json.dumps(report, indent=2, sort_keys=True)
        if args.json_output:
            args.json_output.write_text(encoded + "\n", encoding="utf-8")
        if args.markdown_output:
            args.markdown_output.write_text(markdown_report(report), encoding="utf-8")
        if not args.json_output:
            print(encoded)
    except (OSError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
