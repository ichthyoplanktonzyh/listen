#!/usr/bin/env python3
"""Evaluate RhythmFrame stress/boundary output against Helsinki Prosody labels.

The Helsinki Prosody Corpus provides automatic word-level prominence and word
boundary labels for LibriTTS source files. This scorer treats those labels as a
public weak-label regression benchmark for Phase 2.20:

* prominence labels -> RhythmFrame stress anchors
* word boundary labels -> RhythmFrame phrase boundaries

It does not score weak groups, compression spans, or learner-facing hotspot
usefulness; those remain manual/product QA concerns.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def benchmark_context() -> dict[str, Any]:
    return {
        "benchmark": "Helsinki Prosody / LibriTTS",
        "role": "weak_prosody_regression",
        "evidence_class": "silver_label",
        "label_task": "automatic word-level prosodic prominence and boundary labels",
        "rhythm_frame_fields": {
            "stress_anchors": {
                "reference": "word prominence labels",
                "label_values": {
                    "0": "not prominent",
                    "1": "prominent",
                    "2": "highly prominent",
                    "NA": "not scored",
                },
                "metric": "word-index precision/recall/F1",
            },
            "phrase_boundaries": {
                "reference": "word boundary labels",
                "label_values": {
                    "0": "no boundary",
                    "1": "minor boundary",
                    "2": "major boundary",
                    "NA": "not scored",
                },
                "metric": "word-boundary precision/recall/F1",
            },
        },
        "reported_baselines": [
            {
                "name": "Talman et al. 2019 BERT-base text model",
                "split": "test",
                "task": "2-way prominence prediction",
                "metric": "accuracy",
                "value": 0.832,
                "source": "https://aclanthology.org/W19-6129.pdf",
            },
            {
                "name": "Talman et al. 2019 BERT-base text model",
                "split": "test",
                "task": "3-way prominence prediction",
                "metric": "accuracy",
                "value": 0.686,
                "source": "https://aclanthology.org/W19-6129.pdf",
            },
        ],
        "caveats": [
            "Helsinki labels are automatic labels, not human prosody gold.",
            "The reported baselines are text-prediction accuracies and are not directly comparable to end-to-end audio RhythmFrame precision/recall/F1.",
            "The phrase-boundary reference is a word-boundary silver label, not ToBI break-index gold.",
            "Small local smoke runs should be treated as pipeline diagnostics, not release gates.",
        ],
    }


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.is_file():
        return rows
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError(f"{path}:{lineno}: expected JSON object")
        rows.append(value)
    return rows


def expand_path(raw: str, repo_root: Path) -> Path:
    path = Path(raw).expanduser()
    return path if path.is_absolute() else repo_root / path


def normalize_word(value: Any) -> str:
    return "".join(re.findall(r"[a-z0-9']+", str(value).lower())).strip("'")


def tokenize_text(value: Any) -> list[str]:
    return [normalize_word(token) for token in re.findall(r"[A-Za-z0-9']+", str(value)) if normalize_word(token)]


def parse_int_label(value: str) -> int | None:
    return None if value == "NA" else int(value)


def parse_float_label(value: str) -> float | None:
    return None if value == "NA" else float(value)


def parse_helsinki_labels(path: Path, limit: int | None = None) -> list[dict[str, Any]]:
    sentences: list[dict[str, Any]] = []
    current_file: str | None = None
    current_words: list[dict[str, Any]] = []

    def flush() -> None:
        nonlocal current_words
        if current_file and current_words:
            sentences.append(
                {
                    "source_file": current_file,
                    "source_stem": Path(current_file).stem,
                    "words": current_words,
                }
            )
        current_words = []

    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped:
            flush()
            current_file = None
            if limit is not None and len(sentences) >= limit:
                break
            continue
        parts = stripped.split("\t")
        if parts[0] == "<file>":
            flush()
            if limit is not None and len(sentences) >= limit:
                break
            if len(parts) < 2:
                raise ValueError(f"{path}:{lineno}: <file> row requires a filename")
            current_file = parts[1]
            continue
        if current_file is None:
            raise ValueError(f"{path}:{lineno}: word row before <file> header")
        if len(parts) != 5:
            raise ValueError(f"{path}:{lineno}: expected 5 tab-separated fields")
        word, prominence, boundary, prominence_value, boundary_value = parts
        current_words.append(
            {
                "word": word,
                "normalized": normalize_word(word),
                "prominence": parse_int_label(prominence),
                "boundary": parse_int_label(boundary),
                "prominence_value": parse_float_label(prominence_value),
                "boundary_value": parse_float_label(boundary_value),
            }
        )
    else:
        flush()

    return sentences[:limit] if limit is not None else sentences


def label_summary(sentences: list[dict[str, Any]]) -> dict[str, Any]:
    prominence_counts = {"0": 0, "1": 0, "2": 0, "NA": 0}
    boundary_counts = {"0": 0, "1": 0, "2": 0, "NA": 0}
    word_count = 0
    for sentence in sentences:
        for word in sentence["words"]:
            if word["prominence"] is None:
                prominence_counts["NA"] += 1
            else:
                prominence_counts[str(word["prominence"])] += 1
                word_count += 1
            if word["boundary"] is None:
                boundary_counts["NA"] += 1
            else:
                boundary_counts[str(word["boundary"])] += 1
    return {
        "sentence_count": len(sentences),
        "word_count": word_count,
        "prominence_counts": prominence_counts,
        "boundary_counts": boundary_counts,
    }


def segments_by_id(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for segment in document.get("segments") or []:
        if isinstance(segment, dict) and isinstance(segment.get("id"), str):
            values[segment["id"]] = segment
    return values


def phone_timelines(document: dict[str, Any]) -> list[dict[str, Any]]:
    return [item for item in document.get("phone_timelines") or [] if isinstance(item, dict)]


def sentence_text(segment: dict[str, Any] | None) -> str:
    if not isinstance(segment, dict):
        return ""
    return str(segment.get("display_text") or segment.get("text") or "")


def timeline_sentences(document: dict[str, Any]) -> list[dict[str, Any]]:
    segments = segments_by_id(document)
    values: list[dict[str, Any]] = []
    seen_sentence_ids: set[str] = set()
    for timeline in phone_timelines(document):
        sentence_id = timeline.get("sentence_id")
        if not isinstance(sentence_id, str):
            continue
        seen_sentence_ids.add(sentence_id)
        segment = segments.get(sentence_id)
        sound_analysis = timeline.get("sound_analysis") if isinstance(timeline.get("sound_analysis"), dict) else {}
        rhythm_frame = sound_analysis.get("rhythm_frame") if isinstance(sound_analysis, dict) else None
        text = sentence_text(segment)
        values.append(
            {
                "sentence_id": sentence_id,
                "text": text,
                "words": tokenize_text(text),
                "rhythm_frame": rhythm_frame if isinstance(rhythm_frame, dict) else None,
            }
        )
    for sentence_id, segment in segments.items():
        if sentence_id in seen_sentence_ids:
            continue
        text = sentence_text(segment)
        values.append(
            {
                "sentence_id": sentence_id,
                "text": text,
                "words": tokenize_text(text),
                "rhythm_frame": None,
            }
        )
    return values


def normalized_label_words(label_sentence: dict[str, Any]) -> list[str]:
    return [word["normalized"] for word in label_sentence["words"] if word["prominence"] is not None and word["normalized"]]


def pick_timeline_sentence(
    label_sentence: dict[str, Any],
    document: dict[str, Any],
    sentence_id: str | None = None,
) -> dict[str, Any] | None:
    candidates = timeline_sentences(document)
    if sentence_id:
        for candidate in candidates:
            if candidate["sentence_id"] == sentence_id:
                return candidate
    label_words = normalized_label_words(label_sentence)
    for candidate in candidates:
        if candidate["words"] == label_words:
            return candidate
    return candidates[0] if len(candidates) == 1 else None


def timeline_manifest_entries(path: Path, repo_root: Path) -> dict[str, dict[str, Any]]:
    entries: dict[str, dict[str, Any]] = {}
    for row in load_jsonl(path):
        source_file = row.get("source_file")
        if not isinstance(source_file, str) or not source_file:
            raise ValueError(f"{path}: manifest row missing source_file")
        raw_path = None
        lltimeline = row.get("lltimeline")
        if isinstance(lltimeline, dict):
            raw_path = lltimeline.get("local_path") or lltimeline.get("path")
        raw_path = raw_path or row.get("local_path") or row.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            raise ValueError(f"{path}: manifest row for {source_file} missing timeline path")
        source_stem = Path(source_file).stem
        entries[source_file] = {
            "source_file": source_file,
            "source_stem": source_stem,
            "timeline_path": expand_path(raw_path, repo_root),
            "sentence_id": row.get("sentence_id") if isinstance(row.get("sentence_id"), str) else None,
        }
        entries[source_stem] = entries[source_file]
    return entries


def timeline_path_from_dir(source_file: str, directory: Path) -> Path | None:
    source_stem = Path(source_file).stem
    candidates = [
        directory / f"{source_file}.lltimeline.json",
        directory / f"{source_stem}.lltimeline.json",
        directory / source_stem / f"{source_stem}.lltimeline.json",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    return None


def map_raw_index(raw: Any, words: list[str]) -> int | None:
    value = as_int(raw)
    if value is None:
        return None
    if value >= 0 and value % 2 == 0 and value // 2 < len(words):
        return value // 2
    if 0 <= value < len(words):
        return value
    return None


def unique_word_index(label: Any, words: list[str]) -> int | None:
    normalized = normalize_word(label)
    if not normalized:
        return None
    matches = [index for index, word in enumerate(words) if word == normalized]
    return matches[0] if len(matches) == 1 else None


def anchor_index(item: dict[str, Any], words: list[str]) -> int | None:
    by_label = unique_word_index(item.get("label") or item.get("text") or item.get("word"), words)
    if by_label is not None:
        return by_label
    return map_raw_index(item.get("word_index"), words) or map_raw_index(item.get("token_index"), words)


def boundary_index(item: dict[str, Any], words: list[str]) -> int | None:
    after = map_raw_index(item.get("after_token_index"), words)
    if after is not None:
        return after
    token = map_raw_index(item.get("token_index"), words)
    if token is not None:
        return token
    before = map_raw_index(item.get("before_token_index"), words)
    if before is not None and before > 0:
        return before - 1
    return None


def precision_recall_f1(predicted: set[int], gold: set[int]) -> dict[str, Any]:
    true_positive = len(predicted.intersection(gold))
    false_positive = len(predicted.difference(gold))
    false_negative = len(gold.difference(predicted))
    precision = true_positive / len(predicted) if predicted else None
    recall = true_positive / len(gold) if gold else None
    f1 = None
    if precision is not None and recall is not None and precision + recall:
        f1 = 2 * precision * recall / (precision + recall)
    return {
        "true_positive": true_positive,
        "false_positive": false_positive,
        "false_negative": false_negative,
        "precision": round(precision, 6) if precision is not None else None,
        "recall": round(recall, 6) if recall is not None else None,
        "f1": round(f1, 6) if f1 is not None else None,
    }


def score_label_sentence(
    label_sentence: dict[str, Any],
    timeline_sentence: dict[str, Any],
    prominence_threshold: int,
    boundary_threshold: int,
) -> dict[str, Any]:
    words = normalized_label_words(label_sentence)
    rhythm_frame = timeline_sentence.get("rhythm_frame")
    if not isinstance(rhythm_frame, dict):
        return {
            "source_file": label_sentence["source_file"],
            "sentence_id": timeline_sentence.get("sentence_id"),
            "status": "missing_rhythm_frame",
        }

    gold_anchors = {
        index
        for index, word in enumerate(label_sentence["words"])
        if word["prominence"] is not None and word["normalized"] and word["prominence"] >= prominence_threshold
    }
    gold_boundaries = {
        index
        for index, word in enumerate(label_sentence["words"])
        if word["boundary"] is not None and word["normalized"] and word["boundary"] >= boundary_threshold
    }
    predicted_anchors = {
        index
        for item in rhythm_frame.get("stress_anchors") or []
        if isinstance(item, dict)
        for index in [anchor_index(item, words)]
        if index is not None
    }
    predicted_boundary_rows = [
        (item, index)
        for item in rhythm_frame.get("phrase_boundaries") or []
        if isinstance(item, dict)
        for index in [boundary_index(item, words)]
        if index is not None
    ]
    predicted_boundaries = {index for _, index in predicted_boundary_rows}
    predicted_boundary_evidence_counts: dict[str, int] = {}
    for item, _ in predicted_boundary_rows:
        evidence = str(item.get("evidence") or "unknown")
        predicted_boundary_evidence_counts[evidence] = (
            predicted_boundary_evidence_counts.get(evidence, 0) + 1
        )
    text_words = timeline_sentence.get("words") or []
    text_matches = text_words == words
    return {
        "source_file": label_sentence["source_file"],
        "sentence_id": timeline_sentence.get("sentence_id"),
        "status": "scored",
        "text_matches_labels": text_matches,
        "word_count": len(words),
        "gold_anchor_count": len(gold_anchors),
        "predicted_anchor_count": len(predicted_anchors),
        "gold_boundary_count": len(gold_boundaries),
        "predicted_boundary_count": len(predicted_boundaries),
        "predicted_boundary_evidence_counts": predicted_boundary_evidence_counts,
        "stress_anchors": precision_recall_f1(predicted_anchors, gold_anchors),
        "phrase_boundaries": precision_recall_f1(predicted_boundaries, gold_boundaries),
    }


def aggregate_sentence_scores(rows: list[dict[str, Any]]) -> dict[str, Any]:
    totals = {
        "stress_anchors": {"true_positive": 0, "false_positive": 0, "false_negative": 0},
        "phrase_boundaries": {"true_positive": 0, "false_positive": 0, "false_negative": 0},
    }
    status_counts: dict[str, int] = {}
    boundary_evidence_counts: dict[str, int] = {}
    text_mismatch_count = 0
    for row in rows:
        status = str(row.get("status") or "unknown")
        status_counts[status] = status_counts.get(status, 0) + 1
        if row.get("text_matches_labels") is False:
            text_mismatch_count += 1
        if status != "scored":
            continue
        for evidence, count in (row.get("predicted_boundary_evidence_counts") or {}).items():
            boundary_evidence_counts[str(evidence)] = boundary_evidence_counts.get(str(evidence), 0) + int(count)
        for field in totals:
            score = row.get(field)
            if not isinstance(score, dict):
                continue
            for key in totals[field]:
                totals[field][key] += int(score.get(key) or 0)

    def finalize(raw: dict[str, int]) -> dict[str, Any]:
        tp = raw["true_positive"]
        fp = raw["false_positive"]
        fn = raw["false_negative"]
        precision = tp / (tp + fp) if tp + fp else None
        recall = tp / (tp + fn) if tp + fn else None
        f1 = None
        if precision is not None and recall is not None and precision + recall:
            f1 = 2 * precision * recall / (precision + recall)
        return {
            **raw,
            "precision": round(precision, 6) if precision is not None else None,
            "recall": round(recall, 6) if recall is not None else None,
            "f1": round(f1, 6) if f1 is not None else None,
        }

    return {
        "sentence_count": len(rows),
        "status_counts": status_counts,
        "scored_sentence_count": status_counts.get("scored", 0),
        "text_mismatch_count": text_mismatch_count,
        "predicted_boundary_evidence_counts": boundary_evidence_counts,
        "stress_anchors": finalize(totals["stress_anchors"]),
        "phrase_boundaries": finalize(totals["phrase_boundaries"]),
    }


def evaluate(
    labels: list[dict[str, Any]],
    repo_root: Path,
    lltimeline_manifest: Path | None = None,
    lltimeline_dir: Path | None = None,
    prominence_threshold: int = 1,
    boundary_threshold: int = 2,
) -> dict[str, Any]:
    manifest_entries = timeline_manifest_entries(lltimeline_manifest, repo_root) if lltimeline_manifest else {}
    sentence_scores: list[dict[str, Any]] = []

    for label_sentence in labels:
        entry = manifest_entries.get(label_sentence["source_file"]) or manifest_entries.get(label_sentence["source_stem"])
        timeline_path: Path | None = entry["timeline_path"] if entry else None
        sentence_id = entry.get("sentence_id") if entry else None
        if timeline_path is None and lltimeline_dir is not None:
            timeline_path = timeline_path_from_dir(label_sentence["source_file"], lltimeline_dir)
        if timeline_path is None:
            sentence_scores.append({"source_file": label_sentence["source_file"], "status": "missing_timeline"})
            continue
        if not timeline_path.is_file():
            sentence_scores.append(
                {
                    "source_file": label_sentence["source_file"],
                    "status": "missing_timeline_file",
                    "timeline_path": str(timeline_path),
                }
            )
            continue
        document = read_json(timeline_path)
        timeline_sentence = pick_timeline_sentence(label_sentence, document, sentence_id=sentence_id)
        if timeline_sentence is None:
            sentence_scores.append({"source_file": label_sentence["source_file"], "status": "missing_sentence"})
            continue
        sentence_scores.append(
            score_label_sentence(
                label_sentence,
                timeline_sentence,
                prominence_threshold=prominence_threshold,
                boundary_threshold=boundary_threshold,
            )
        )

    return {
        "benchmark_context": benchmark_context(),
        "label_summary": label_summary(labels),
        "score_summary": aggregate_sentence_scores(sentence_scores),
        "sentences": sentence_scores,
    }


def quality_gates(
    score_summary: dict[str, Any],
    min_scored_sentences: int | None,
    min_anchor_f1: float | None,
    min_boundary_f1: float | None,
) -> dict[str, Any]:
    gates: list[dict[str, Any]] = []

    def add_gate(name: str, actual: Any, expected: Any, passed: bool) -> None:
        gates.append({"name": name, "actual": actual, "expected": expected, "passed": passed})

    if min_scored_sentences is not None:
        actual = int(score_summary.get("scored_sentence_count") or 0)
        add_gate("min_scored_sentences", actual, min_scored_sentences, actual >= min_scored_sentences)
    if min_anchor_f1 is not None:
        actual = (score_summary.get("stress_anchors") or {}).get("f1")
        add_gate("min_anchor_f1", actual, min_anchor_f1, actual is not None and actual >= min_anchor_f1)
    if min_boundary_f1 is not None:
        actual = (score_summary.get("phrase_boundaries") or {}).get("f1")
        add_gate("min_boundary_f1", actual, min_boundary_f1, actual is not None and actual >= min_boundary_f1)

    return {
        "gate_count": len(gates),
        "passed": all(gate["passed"] for gate in gates),
        "gates": gates,
    }


def labels_path(args: argparse.Namespace, repo_root: Path) -> Path:
    if args.labels:
        return expand_path(args.labels, repo_root)
    if not args.prosody_dir:
        raise ValueError("either --labels or --prosody-dir is required")
    return expand_path(args.prosody_dir, repo_root) / "data" / f"{args.split}.txt"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--labels", help="Path to a Helsinki Prosody split txt file")
    parser.add_argument("--prosody-dir", help="Path to cloned Helsinki prosody repo")
    parser.add_argument("--split", default="dev", choices=["dev", "test", "train_100", "train_360"])
    parser.add_argument("--limit", type=int, help="Limit label sentences for smoke runs")
    parser.add_argument("--lltimeline-manifest", help="JSONL mapping source_file to LLTimeline artifact")
    parser.add_argument("--lltimeline-dir", help="Directory containing <source_stem>.lltimeline.json artifacts")
    parser.add_argument("--prominence-threshold", type=int, default=1)
    parser.add_argument("--boundary-threshold", type=int, default=2)
    parser.add_argument("--include-sentences", action="store_true", help="Include per-sentence score rows")
    parser.add_argument("--min-scored-sentences", type=int)
    parser.add_argument("--min-anchor-f1", type=float)
    parser.add_argument("--min-boundary-f1", type=float)
    parser.add_argument("--fail-on-quality-gate", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    repo_root = Path.cwd()
    try:
        path = labels_path(args, repo_root)
        labels = parse_helsinki_labels(path, limit=args.limit)
        lltimeline_manifest = expand_path(args.lltimeline_manifest, repo_root) if args.lltimeline_manifest else None
        lltimeline_dir = expand_path(args.lltimeline_dir, repo_root) if args.lltimeline_dir else None
        result = evaluate(
            labels,
            repo_root,
            lltimeline_manifest=lltimeline_manifest,
            lltimeline_dir=lltimeline_dir,
            prominence_threshold=args.prominence_threshold,
            boundary_threshold=args.boundary_threshold,
        )
        result["metadata"] = {
            "labels_path": str(path),
            "split": args.split,
            "limit": args.limit,
            "prominence_threshold": args.prominence_threshold,
            "boundary_threshold": args.boundary_threshold,
            "lltimeline_manifest": str(lltimeline_manifest) if lltimeline_manifest else None,
            "lltimeline_dir": str(lltimeline_dir) if lltimeline_dir else None,
        }
        result["quality_gates"] = quality_gates(
            result["score_summary"],
            min_scored_sentences=args.min_scored_sentences,
            min_anchor_f1=args.min_anchor_f1,
            min_boundary_f1=args.min_boundary_f1,
        )
        if not args.include_sentences:
            result.pop("sentences", None)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if args.fail_on_quality_gate and not result["quality_gates"]["passed"]:
            return 4
        return 0
    except Exception as exc:  # pragma: no cover - CLI guardrail
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
