#!/usr/bin/env python3
"""Evaluate Phase 2.20 RhythmFrame artifacts and optional manual QA labels.

The scorer reads the Phase 2.17 real-media manifest and local-only LLTimeline
artifacts. It is intentionally useful before and after artifacts are refreshed:
older timelines report missing rhythm_frame coverage, while refreshed timelines
can be scored against manual annotation JSONL.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


HOTSPOT_SCORES = {
    "correct",
    "useful_but_incomplete",
    "unclear",
    "misleading",
    "unsupported",
}
ANNOTATION_REQUIRED_FIELDS = {
    "case_id",
    "sentence_id",
    "transcript",
    "stress_anchors",
    "weak_groups",
    "compression_spans",
    "phrase_boundaries",
    "listening_hotspots",
}
ANNOTATION_LIST_FIELDS = {
    "stress_anchors",
    "weak_groups",
    "compression_spans",
    "phrase_boundaries",
    "listening_hotspots",
}
MANUAL_SCORE_FIELDS = (
    "stress_anchors",
    "weak_groups",
    "compression_spans",
    "phrase_boundaries",
    "listening_hotspots",
)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError(f"{path}:{lineno}: expected JSON object")
        rows.append(value)
    return rows


def load_manifest(path: Path) -> list[dict[str, Any]]:
    return load_jsonl(path)


def expand_path(raw: str, repo_root: Path) -> Path:
    path = Path(raw).expanduser()
    if path.is_absolute():
        return path
    return repo_root / path


def timeline_path(case: dict[str, Any], repo_root: Path) -> Path | None:
    llt = case.get("lltimeline") or {}
    raw = llt.get("local_path") or llt.get("path")
    if not isinstance(raw, str) or not raw:
        return None
    path = expand_path(raw, repo_root)
    return path if path.is_file() else None


def safe_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    return None


def as_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def normalize_text(value: Any) -> str:
    return " ".join(re.findall(r"[a-z0-9']+", str(value).lower()))


def percent(value: float | None) -> float | None:
    return round(value, 6) if value is not None else None


def ratio(numerator: int, denominator: int) -> float | None:
    return round(numerator / denominator, 6) if denominator else None


def f1(precision: float | None, recall: float | None) -> float | None:
    if precision is None or recall is None or precision + recall == 0:
        return None
    return round(2 * precision * recall / (precision + recall), 6)


def mean(values: list[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 6)


def score_total(counts: dict[str, int]) -> int:
    return sum(value for value in counts.values() if isinstance(value, int))


def score_rate(counts: dict[str, int], score: str) -> float | None:
    total = score_total(counts)
    return ratio(int(counts.get(score) or 0), total)


def segments_by_id(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for segment in safe_list(document.get("segments")):
        if isinstance(segment, dict) and isinstance(segment.get("id"), str):
            values[segment["id"]] = segment
    return values


def phone_timelines_by_sentence(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for timeline in safe_list(document.get("phone_timelines")):
        if isinstance(timeline, dict) and isinstance(timeline.get("sentence_id"), str):
            values[timeline["sentence_id"]] = timeline
    return values


def annotations_by_key(rows: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    values: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        case_id = row.get("case_id")
        sentence_id = row.get("sentence_id")
        if isinstance(case_id, str) and isinstance(sentence_id, str):
            values[(case_id, sentence_id)] = row
    return values


def validate_annotation_rows(
    rows: list[dict[str, Any]],
    known_sentence_keys: set[tuple[str, str]] | None = None,
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    seen: set[tuple[str, str]] = set()
    for index, row in enumerate(rows, 1):
        prefix = f"annotation[{index}]"
        missing = sorted(ANNOTATION_REQUIRED_FIELDS.difference(row))
        if missing:
            errors.append(f"{prefix}: missing required fields: {', '.join(missing)}")

        case_id = row.get("case_id")
        sentence_id = row.get("sentence_id")
        if not isinstance(case_id, str) or not case_id:
            errors.append(f"{prefix}: case_id must be a non-empty string")
        if not isinstance(sentence_id, str) or not sentence_id:
            errors.append(f"{prefix}: sentence_id must be a non-empty string")
        if isinstance(case_id, str) and isinstance(sentence_id, str):
            key = (case_id, sentence_id)
            if key in seen:
                errors.append(f"{prefix}: duplicate annotation for {case_id}/{sentence_id}")
            seen.add(key)
            if known_sentence_keys is not None and key not in known_sentence_keys:
                warnings.append(f"{prefix}: annotation target not found in selected timelines: {case_id}/{sentence_id}")

        for field in sorted(ANNOTATION_LIST_FIELDS):
            if field in row and not isinstance(row[field], list):
                errors.append(f"{prefix}: {field} must be a list")

        overall = row.get("overall")
        if overall is not None and not isinstance(overall, dict):
            errors.append(f"{prefix}: overall must be an object when present")
        elif isinstance(overall, dict):
            score = overall.get("manual_score")
            if score is not None and score not in HOTSPOT_SCORES:
                errors.append(f"{prefix}: invalid overall.manual_score: {score}")

        for field in MANUAL_SCORE_FIELDS:
            values = row.get(field)
            if not isinstance(values, list):
                continue
            for item_index, value in enumerate(values, 1):
                item_prefix = f"{prefix}.{field}[{item_index}]"
                if not isinstance(value, dict):
                    errors.append(f"{item_prefix}: item must be an object")
                    continue
                score = value.get("manual_score")
                if score is not None and score not in HOTSPOT_SCORES:
                    errors.append(f"{item_prefix}: invalid manual_score: {score}")
                if field == "listening_hotspots" and score is None:
                    warnings.append(f"{item_prefix}: listening hotspot has no manual_score")
    return {
        "annotation_count": len(rows),
        "error_count": len(errors),
        "warning_count": len(warnings),
        "errors": errors,
        "warnings": warnings,
    }


def token_range(item: dict[str, Any], kind: str) -> tuple[int, int] | None:
    if kind == "anchor":
        token = as_int(first_present(item.get("token_index"), item.get("word_index")))
        return (token, token) if token is not None else None
    if kind == "boundary":
        after = as_int(item.get("after_token_index"))
        before = as_int(item.get("before_token_index"))
        if after is not None and before is not None:
            return (after, before)
        token = as_int(item.get("token_index"))
        return (token, token) if token is not None else None
    start = as_int(item.get("token_start"))
    end = as_int(item.get("token_end"))
    word_range = item.get("word_range")
    if isinstance(word_range, list) and len(word_range) == 2:
        start = as_int(word_range[0])
        end = as_int(word_range[1])
    if start is None:
        start = as_int(item.get("word_start"))
    if end is None:
        end = as_int(item.get("word_end"))
    if start is None:
        return None
    return (start, end if end is not None else start)


def time_range(item: dict[str, Any], kind: str) -> tuple[int, int] | None:
    if kind == "boundary":
        at = as_int(item.get("at_ms"))
        return (at, at) if at is not None else None
    start = as_int(item.get("start_ms"))
    end = as_int(item.get("end_ms"))
    if start is None or end is None:
        return None
    return (start, end)


def ranges_overlap(left: tuple[int, int], right: tuple[int, int]) -> bool:
    return max(left[0], right[0]) <= min(left[1], right[1])


def time_iou(left: tuple[int, int], right: tuple[int, int]) -> float:
    left_duration = max(1, left[1] - left[0])
    right_duration = max(1, right[1] - right[0])
    intersection = max(0, min(left[1], right[1]) - max(left[0], right[0]))
    union = left_duration + right_duration - intersection
    return intersection / union if union else 0.0


def item_label(item: dict[str, Any]) -> str:
    return normalize_text(item.get("label") or item.get("text") or item.get("words") or "")


def item_match_score(system: dict[str, Any], manual: dict[str, Any], kind: str) -> float:
    if kind == "boundary":
        left = time_range(system, kind)
        right = time_range(manual, kind)
        if left is not None and right is not None and abs(left[0] - right[0]) <= 150:
            return 1.0
        left_tokens = token_range(system, kind)
        right_tokens = token_range(manual, kind)
        if left_tokens is not None and right_tokens is not None and left_tokens == right_tokens:
            return 0.9
        return 0.0

    left_tokens = token_range(system, kind)
    right_tokens = token_range(manual, kind)
    if left_tokens is not None and right_tokens is not None and ranges_overlap(left_tokens, right_tokens):
        return 1.0

    left_label = item_label(system)
    right_label = item_label(manual)
    if left_label and right_label:
        if left_label == right_label:
            return 0.85
        if left_label in right_label or right_label in left_label:
            return 0.65

    left_time = time_range(system, kind)
    right_time = time_range(manual, kind)
    if left_time is not None and right_time is not None:
        overlap = time_iou(left_time, right_time)
        if overlap >= 0.25:
            return 0.6 + min(0.35, overlap * 0.35)
    return 0.0


def greedy_match(
    system_items: list[dict[str, Any]],
    manual_items: list[dict[str, Any]],
    kind: str,
) -> list[tuple[int, int, float]]:
    candidates: list[tuple[int, int, float]] = []
    for i, system in enumerate(system_items):
        for j, manual in enumerate(manual_items):
            score = item_match_score(system, manual, kind)
            if score > 0:
                candidates.append((i, j, score))
    candidates.sort(key=lambda value: value[2], reverse=True)
    used_system: set[int] = set()
    used_manual: set[int] = set()
    matches: list[tuple[int, int, float]] = []
    for i, j, score in candidates:
        if i in used_system or j in used_manual:
            continue
        used_system.add(i)
        used_manual.add(j)
        matches.append((i, j, score))
    return matches


def score_items(
    system_items: list[dict[str, Any]],
    manual_items: list[dict[str, Any]],
    kind: str,
) -> dict[str, Any]:
    matches = greedy_match(system_items, manual_items, kind)
    precision = ratio(len(matches), len(system_items))
    recall = ratio(len(matches), len(manual_items))
    return {
        "system_count": len(system_items),
        "manual_count": len(manual_items),
        "matched_count": len(matches),
        "precision": precision,
        "recall": recall,
        "f1": f1(precision, recall),
    }


def manual_items(annotation: dict[str, Any] | None, *names: str) -> list[dict[str, Any]]:
    if annotation is None:
        return []
    for name in names:
        values = annotation.get(name)
        if isinstance(values, list):
            return [value for value in values if isinstance(value, dict)]
    return []


def compact_item(item: dict[str, Any], kind: str) -> dict[str, Any]:
    value: dict[str, Any] = {
        "label": item.get("label") or item.get("text") or "",
        "confidence": percent(as_float(item.get("confidence"))),
    }
    tokens = token_range(item, kind)
    times = time_range(item, kind)
    if tokens is not None:
        value["token_range"] = list(tokens)
    if times is not None:
        if kind == "boundary":
            value["at_ms"] = times[0]
        else:
            value["start_ms"] = times[0]
            value["end_ms"] = times[1]
    if item.get("kind"):
        value["kind"] = item.get("kind")
    if item.get("id"):
        value["id"] = item.get("id")
    return value


def score_hotspot_labels(
    annotation: dict[str, Any] | None,
    system_hotspots: list[dict[str, Any]],
) -> dict[str, Any] | None:
    if annotation is None:
        return None
    manual_hotspots = manual_items(annotation, "listening_hotspots", "hotspots")
    score_counts = {score: 0 for score in sorted(HOTSPOT_SCORES)}
    invalid_scores: list[str] = []
    for hotspot in manual_hotspots:
        score = hotspot.get("manual_score")
        if isinstance(score, str) and score in HOTSPOT_SCORES:
            score_counts[score] += 1
        elif score is not None:
            invalid_scores.append(str(score))
    return {
        "span_match": score_items(system_hotspots, manual_hotspots, "hotspot"),
        "manual_score_counts": score_counts,
        "invalid_manual_scores": sorted(set(invalid_scores)),
    }


def sentence_score(
    case_id: str,
    segment: dict[str, Any] | None,
    phone_timeline: dict[str, Any],
    annotation: dict[str, Any] | None,
) -> dict[str, Any]:
    sentence_id = str(phone_timeline.get("sentence_id") or "")
    sound_analysis = phone_timeline.get("sound_analysis")
    if not isinstance(sound_analysis, dict):
        return {
            "sentence_id": sentence_id,
            "status": "missing_sound_analysis",
            "text": (segment or {}).get("text", ""),
        }
    frame = sound_analysis.get("rhythm_frame")
    if not isinstance(frame, dict):
        return {
            "sentence_id": sentence_id,
            "status": "missing_rhythm_frame",
            "text": (segment or {}).get("text", ""),
            "learning_phone_count": len(safe_list(sound_analysis.get("learning_phones"))),
            "connected_speech_count": len(safe_list(sound_analysis.get("connected_speech"))),
        }

    anchors = [value for value in safe_list(frame.get("stress_anchors")) if isinstance(value, dict)]
    weak_groups = [value for value in safe_list(frame.get("weak_groups")) if isinstance(value, dict)]
    compression_spans = [
        value for value in safe_list(frame.get("compression_spans")) if isinstance(value, dict)
    ]
    boundaries = [value for value in safe_list(frame.get("phrase_boundaries")) if isinstance(value, dict)]
    hotspots = [value for value in safe_list(frame.get("listening_hotspots")) if isinstance(value, dict)]
    quality = frame.get("quality") if isinstance(frame.get("quality"), dict) else {}
    manual_scores = None
    if annotation is not None:
        manual_scores = {
            "stress_anchors": score_items(
                anchors,
                manual_items(annotation, "stress_anchors", "anchors"),
                "anchor",
            ),
            "weak_groups": score_items(
                weak_groups,
                manual_items(annotation, "weak_groups"),
                "span",
            ),
            "compression_spans": score_items(
                compression_spans,
                manual_items(annotation, "compression_spans"),
                "span",
            ),
            "phrase_boundaries": score_items(
                boundaries,
                manual_items(annotation, "phrase_boundaries"),
                "boundary",
            ),
            "listening_hotspots": score_hotspot_labels(annotation, hotspots),
            "overall_manual_score": (annotation.get("overall") or {}).get("manual_score")
            if isinstance(annotation.get("overall"), dict)
            else annotation.get("manual_score"),
        }
    return {
        "sentence_id": sentence_id,
        "status": "scored",
        "text": (segment or {}).get("text", ""),
        "start_ms": (segment or {}).get("start_ms"),
        "end_ms": (segment or {}).get("end_ms"),
        "generated_from": frame.get("generated_from"),
        "quality": {
            "timing_source": quality.get("timing_source"),
            "phone_evidence_coverage": percent(as_float(quality.get("phone_evidence_coverage"))),
            "rhythm_confidence": percent(as_float(quality.get("rhythm_confidence"))),
        },
        "counts": {
            "stress_anchors": len(anchors),
            "weak_groups": len(weak_groups),
            "compression_spans": len(compression_spans),
            "phrase_boundaries": len(boundaries),
            "listening_hotspots": len(hotspots),
        },
        "samples": {
            "stress_anchors": [compact_item(value, "anchor") for value in anchors[:5]],
            "weak_groups": [compact_item(value, "span") for value in weak_groups[:5]],
            "compression_spans": [compact_item(value, "span") for value in compression_spans[:5]],
            "listening_hotspots": [compact_item(value, "hotspot") for value in hotspots[:5]],
        },
        "manual": manual_scores,
    }


def summarize_case(sentence_rows: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(sentence_rows)
    scored = sum(1 for row in sentence_rows if row.get("status") == "scored")
    missing_sound = sum(1 for row in sentence_rows if row.get("status") == "missing_sound_analysis")
    missing_frame = sum(1 for row in sentence_rows if row.get("status") == "missing_rhythm_frame")
    return {
        "phone_timeline_sentence_count": total,
        "rhythm_frame_sentence_count": scored,
        "missing_sound_analysis_count": missing_sound,
        "missing_rhythm_frame_count": missing_frame,
        "rhythm_frame_coverage": ratio(scored, total) or 0.0,
        "status": "scored" if scored else "missing_rhythm_frame",
    }


def evaluate_case(
    case: dict[str, Any],
    repo_root: Path,
    annotations: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any]:
    path = timeline_path(case, repo_root)
    case_id = str(case.get("case_id") or "")
    if path is None:
        return {
            "case_id": case_id,
            "title": case.get("title"),
            "dataset": case.get("dataset"),
            "status": "missing_timeline",
        }
    document = read_json(path)
    segments = segments_by_id(document)
    rows = []
    for sentence_id, timeline in phone_timelines_by_sentence(document).items():
        rows.append(
            sentence_score(
                case_id,
                segments.get(sentence_id),
                timeline,
                annotations.get((case_id, sentence_id)),
            )
        )
    rows.sort(key=lambda row: (row.get("start_ms") is None, row.get("start_ms") or 0))
    return {
        "case_id": case_id,
        "title": case.get("title"),
        "dataset": case.get("dataset"),
        "layer": case.get("layer"),
        "timeline_path": str(path),
        **summarize_case(rows),
        "missing_rhythm_frame_sentence_ids": [
            row["sentence_id"] for row in rows if row.get("status") == "missing_rhythm_frame"
        ][:20],
        "sentences": rows,
    }


def aggregate_results(results: list[dict[str, Any]]) -> dict[str, Any]:
    total_sentences = sum(int(result.get("phone_timeline_sentence_count") or 0) for result in results)
    rhythm_sentences = sum(int(result.get("rhythm_frame_sentence_count") or 0) for result in results)
    missing_timelines = sum(1 for result in results if result.get("status") == "missing_timeline")
    by_dataset: dict[str, dict[str, int]] = {}
    for result in results:
        dataset = str(result.get("dataset") or "unknown")
        bucket = by_dataset.setdefault(dataset, {"cases": 0, "sentences": 0, "rhythm_frames": 0})
        bucket["cases"] += 1
        bucket["sentences"] += int(result.get("phone_timeline_sentence_count") or 0)
        bucket["rhythm_frames"] += int(result.get("rhythm_frame_sentence_count") or 0)
    return {
        "case_count": len(results),
        "missing_timeline_case_count": missing_timelines,
        "phone_timeline_sentence_count": total_sentences,
        "rhythm_frame_sentence_count": rhythm_sentences,
        "rhythm_frame_coverage": ratio(rhythm_sentences, total_sentences) or 0.0,
        "by_dataset": {
            key: {
                **value,
                "rhythm_frame_coverage": ratio(value["rhythm_frames"], value["sentences"]) or 0.0,
            }
            for key, value in sorted(by_dataset.items())
        },
        "manual_qa": aggregate_manual_qa(results),
    }


def aggregate_manual_qa(results: list[dict[str, Any]]) -> dict[str, Any]:
    hotspot_score_counts = {score: 0 for score in sorted(HOTSPOT_SCORES)}
    overall_score_counts = {score: 0 for score in sorted(HOTSPOT_SCORES)}
    invalid_hotspot_scores: set[str] = set()
    f1_values: dict[str, list[float]] = {
        "stress_anchors": [],
        "weak_groups": [],
        "compression_spans": [],
        "phrase_boundaries": [],
        "listening_hotspots": [],
    }
    annotated_sentence_count = 0
    for result in results:
        for sentence in result.get("sentences") or []:
            if not isinstance(sentence, dict):
                continue
            manual = sentence.get("manual")
            if not isinstance(manual, dict):
                continue
            annotated_sentence_count += 1
            overall_score = manual.get("overall_manual_score")
            if overall_score in overall_score_counts:
                overall_score_counts[overall_score] += 1
            for field in ("stress_anchors", "weak_groups", "compression_spans", "phrase_boundaries"):
                metric = manual.get(field)
                if isinstance(metric, dict) and isinstance(metric.get("f1"), (int, float)):
                    f1_values[field].append(float(metric["f1"]))
            hotspot = manual.get("listening_hotspots")
            if isinstance(hotspot, dict):
                span_match = hotspot.get("span_match")
                if isinstance(span_match, dict) and isinstance(span_match.get("f1"), (int, float)):
                    f1_values["listening_hotspots"].append(float(span_match["f1"]))
                for score, count in (hotspot.get("manual_score_counts") or {}).items():
                    if score in hotspot_score_counts and isinstance(count, int):
                        hotspot_score_counts[score] += count
                for score in hotspot.get("invalid_manual_scores") or []:
                    invalid_hotspot_scores.add(str(score))
    overall_total = score_total(overall_score_counts)
    hotspot_total = score_total(hotspot_score_counts)
    return {
        "annotated_sentence_count": annotated_sentence_count,
        "overall_manual_score_counts": overall_score_counts,
        "overall_manual_score_total": overall_total,
        "overall_correct_rate": score_rate(overall_score_counts, "correct"),
        "overall_useful_or_correct_rate": ratio(
            overall_score_counts["correct"] + overall_score_counts["useful_but_incomplete"],
            overall_total,
        ),
        "overall_misleading_rate": score_rate(overall_score_counts, "misleading"),
        "hotspot_manual_score_counts": hotspot_score_counts,
        "hotspot_manual_score_total": hotspot_total,
        "hotspot_useful_or_correct_rate": ratio(
            hotspot_score_counts["correct"] + hotspot_score_counts["useful_but_incomplete"],
            hotspot_total,
        ),
        "hotspot_misleading_rate": score_rate(hotspot_score_counts, "misleading"),
        "hotspot_unsupported_rate": score_rate(hotspot_score_counts, "unsupported"),
        "invalid_hotspot_manual_scores": sorted(invalid_hotspot_scores),
        "mean_f1": {field: mean(values) for field, values in sorted(f1_values.items())},
    }


def quality_gates(
    summary: dict[str, Any],
    annotation_validation: dict[str, Any],
    *,
    min_rhythm_coverage: float | None = None,
    min_annotated_sentences: int | None = None,
    min_overall_useful_rate: float | None = None,
    max_hotspot_misleading_rate: float | None = None,
    max_hotspot_unsupported_rate: float | None = None,
) -> dict[str, Any]:
    gates: list[dict[str, Any]] = []

    def add_min(name: str, actual: float | int | None, expected: float | int | None) -> None:
        if expected is None:
            return
        passed = actual is not None and actual >= expected
        gates.append(
            {
                "name": name,
                "comparison": ">=",
                "expected": expected,
                "actual": actual,
                "passed": passed,
            }
        )

    def add_max(name: str, actual: float | int | None, expected: float | int | None) -> None:
        if expected is None:
            return
        passed = actual is not None and actual <= expected
        gates.append(
            {
                "name": name,
                "comparison": "<=",
                "expected": expected,
                "actual": actual,
                "passed": passed,
            }
        )

    manual_qa = summary.get("manual_qa") if isinstance(summary.get("manual_qa"), dict) else {}
    add_min("rhythm_frame_coverage", as_float(summary.get("rhythm_frame_coverage")), min_rhythm_coverage)
    add_min(
        "annotated_sentence_count",
        as_int(manual_qa.get("annotated_sentence_count")),
        min_annotated_sentences,
    )
    add_min(
        "overall_useful_or_correct_rate",
        as_float(manual_qa.get("overall_useful_or_correct_rate")),
        min_overall_useful_rate,
    )
    add_max(
        "hotspot_misleading_rate",
        as_float(manual_qa.get("hotspot_misleading_rate")),
        max_hotspot_misleading_rate,
    )
    add_max(
        "hotspot_unsupported_rate",
        as_float(manual_qa.get("hotspot_unsupported_rate")),
        max_hotspot_unsupported_rate,
    )
    if annotation_validation.get("error_count"):
        gates.append(
            {
                "name": "annotation_validation_errors",
                "comparison": "==",
                "expected": 0,
                "actual": annotation_validation.get("error_count"),
                "passed": False,
            }
        )
    return {
        "passed": all(gate["passed"] for gate in gates),
        "gate_count": len(gates),
        "gates": gates,
    }


def sentence_keys_from_results(results: list[dict[str, Any]]) -> set[tuple[str, str]]:
    keys: set[tuple[str, str]] = set()
    for result in results:
        case_id = result.get("case_id")
        if not isinstance(case_id, str):
            continue
        for sentence in result.get("sentences") or []:
            if isinstance(sentence, dict) and isinstance(sentence.get("sentence_id"), str):
                keys.add((case_id, sentence["sentence_id"]))
    return keys


def annotation_template_rows(case: dict[str, Any], repo_root: Path) -> list[dict[str, Any]]:
    path = timeline_path(case, repo_root)
    if path is None:
        return []
    document = read_json(path)
    segments = segments_by_id(document)
    rows: list[dict[str, Any]] = []
    case_id = str(case.get("case_id") or "")
    for sentence_id, timeline in phone_timelines_by_sentence(document).items():
        segment = segments.get(sentence_id) or {}
        scored = sentence_score(case_id, segment, timeline, None)
        rows.append(
            {
                "case_id": case_id,
                "sentence_id": sentence_id,
                "transcript": segment.get("text", ""),
                "media_start_ms": segment.get("start_ms"),
                "media_end_ms": segment.get("end_ms"),
                "system": scored if scored.get("status") == "scored" else {"status": scored.get("status")},
                "stress_anchors": [],
                "weak_groups": [],
                "compression_spans": [],
                "phrase_boundaries": [],
                "listening_hotspots": [],
                "overall": {
                    "manual_score": None,
                    "misleading_reason": "",
                    "phone_detail_needed": None,
                    "notes": "",
                },
                "reviewer": "",
                "reviewed_at": "",
            }
        )
    rows.sort(key=lambda row: (row.get("media_start_ms") is None, row.get("media_start_ms") or 0))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="testdata/sound-line-real-media/manifest.jsonl")
    parser.add_argument(
        "--annotations",
        default="testdata/rhythm-frame-qa/annotations.jsonl",
        help="Optional manual QA JSONL. Missing default path is ignored.",
    )
    parser.add_argument("--case-id", action="append")
    parser.add_argument(
        "--emit-template",
        action="store_true",
        help="Emit annotation-template JSONL rows instead of score JSON.",
    )
    parser.add_argument(
        "--fail-on-missing-rhythm",
        action="store_true",
        help="Return non-zero when any selected phone timeline lacks rhythm_frame.",
    )
    parser.add_argument(
        "--strict-annotations",
        action="store_true",
        help="Return non-zero when annotation validation reports errors.",
    )
    parser.add_argument("--min-rhythm-coverage", type=float)
    parser.add_argument("--min-annotated-sentences", type=int)
    parser.add_argument("--min-overall-useful-rate", type=float)
    parser.add_argument("--max-hotspot-misleading-rate", type=float)
    parser.add_argument("--max-hotspot-unsupported-rate", type=float)
    parser.add_argument(
        "--fail-on-quality-gate",
        action="store_true",
        help="Return non-zero when any configured quality gate fails.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    manifest = load_manifest(repo_root / args.manifest)
    selected = set(args.case_id or [])
    cases = [case for case in manifest if not selected or case.get("case_id") in selected]

    if args.emit_template:
        for case in cases:
            for row in annotation_template_rows(case, repo_root):
                print(json.dumps(row, ensure_ascii=False, sort_keys=True))
        return 0

    annotation_path = expand_path(args.annotations, repo_root)
    annotation_rows = load_jsonl(annotation_path)
    basic_annotation_validation = validate_annotation_rows(annotation_rows)
    annotations = annotations_by_key(annotation_rows)
    results = [evaluate_case(case, repo_root, annotations) for case in cases]
    annotation_validation = validate_annotation_rows(
        annotation_rows,
        known_sentence_keys=sentence_keys_from_results(results),
    )
    summary = aggregate_results(results)
    gate_result = quality_gates(
        summary,
        annotation_validation,
        min_rhythm_coverage=args.min_rhythm_coverage,
        min_annotated_sentences=args.min_annotated_sentences,
        min_overall_useful_rate=args.min_overall_useful_rate,
        max_hotspot_misleading_rate=args.max_hotspot_misleading_rate,
        max_hotspot_unsupported_rate=args.max_hotspot_unsupported_rate,
    )
    output = {
        "manifest": args.manifest,
        "annotations": str(annotation_path) if annotation_path.is_file() else None,
        "annotation_count": len(annotation_rows),
        "annotation_validation": annotation_validation,
        "quality_gates": gate_result,
        "summary": summary,
        "results": results,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
    if args.strict_annotations and (
        basic_annotation_validation["error_count"] > 0
        or annotation_validation["error_count"] > 0
    ):
        return 3
    if args.fail_on_missing_rhythm and output["summary"]["rhythm_frame_coverage"] < 1.0:
        return 2
    if args.fail_on_quality_gate and not gate_result["passed"]:
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
