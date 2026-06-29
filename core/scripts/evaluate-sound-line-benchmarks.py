#!/usr/bin/env python3
"""Evaluate Phase 2.17 sound-line artifacts against local benchmark references.

This scorer is intentionally local-only. It reads the Phase 2.17 manifest,
uses ignored `.tmp/sound-line-real-media/` LLTimeline artifacts, and compares
only against benchmark files already present on the developer machine.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path
from typing import Any


SILENCE_OR_NOISE = {
    "h#",
    "pau",
    "epi",
    "bcl",
    "dcl",
    "gcl",
    "kcl",
    "pcl",
    "tcl",
    "q",
    "sil",
    "sp",
    "noise",
    "vocnoise",
    "iver",
}

ARPABET_TO_REFERENCE = {
    "aa": "aa",
    "ae": "ae",
    "ah": "ah",
    "ao": "ao",
    "aw": "aw",
    "ax": "ax",
    "axr": "axr",
    "ay": "ay",
    "b": "b",
    "ch": "ch",
    "d": "d",
    "dh": "dh",
    "dx": "dx",
    "eh": "eh",
    "el": "el",
    "em": "em",
    "en": "en",
    "er": "er",
    "ey": "ey",
    "f": "f",
    "g": "g",
    "hh": "hh",
    "ih": "ih",
    "iy": "iy",
    "jh": "jh",
    "k": "k",
    "l": "l",
    "m": "m",
    "n": "n",
    "ng": "ng",
    "ow": "ow",
    "oy": "oy",
    "p": "p",
    "r": "r",
    "s": "s",
    "sh": "sh",
    "t": "t",
    "th": "th",
    "uh": "uh",
    "uw": "uw",
    "v": "v",
    "w": "w",
    "y": "y",
    "z": "z",
    "zh": "zh",
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_manifest(path: Path) -> list[dict[str, Any]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


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


def normalize_text(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9']+", value.lower()))


def normalize_phone(value: str) -> str | None:
    value = value.strip().lower()
    if not value or value in SILENCE_OR_NOISE:
        return None
    if value.startswith("{") or value.startswith("<"):
        return None
    return ARPABET_TO_REFERENCE.get(value, value)


def sample_to_ms(sample: int, sample_rate: int = 16000) -> int:
    return int(round(sample * 1000 / sample_rate))


def parse_timit_boundary(path: Path) -> list[tuple[int, int, str]]:
    rows: list[tuple[int, int, str]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.strip().split(maxsplit=2)
        if len(parts) != 3:
            continue
        rows.append((int(parts[0]), int(parts[1]), parts[2]))
    return rows


def parse_concat_file(path: Path) -> list[Path]:
    files: list[Path] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"file '(.+)'", line.strip())
        if match:
            files.append(Path(match.group(1)))
    return files


def phone_timelines_by_sentence(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for timeline in document.get("phone_timelines") or []:
        sentence_id = timeline.get("sentence_id")
        if isinstance(sentence_id, str):
            values[sentence_id] = timeline
    return values


def phones_from_timeline(timeline: dict[str, Any]) -> list[str]:
    phones: list[str] = []
    for phone in timeline.get("phones") or []:
        symbol = normalize_phone(str(phone.get("symbol", "")))
        if symbol:
            phones.append(symbol)
    return phones


def compact_phone_sample(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "sentence_id": row.get("sentence_id"),
        "case_index": row.get("case_index"),
        "start_ms": row.get("start_ms"),
        "end_ms": row.get("end_ms"),
        "text": row.get("text"),
        "reference_count": len(row.get("reference") or []),
        "prediction_count": len(row.get("prediction") or []),
        "substitutions": row.get("substitutions"),
        "deletions": row.get("deletions"),
        "insertions": row.get("insertions"),
        "phone_error_rate": row.get("phone_error_rate"),
        "reference_head": (row.get("reference") or [])[:24],
        "prediction_head": (row.get("prediction") or [])[:24],
    }


def edit_distance(reference: list[str], prediction: list[str]) -> tuple[int, int, int]:
    rows = len(reference) + 1
    cols = len(prediction) + 1
    cost = [[0] * cols for _ in range(rows)]
    ops = [[(0, 0, 0)] * cols for _ in range(rows)]
    for i in range(1, rows):
        cost[i][0] = i
        ops[i][0] = (0, i, 0)
    for j in range(1, cols):
        cost[0][j] = j
        ops[0][j] = (0, 0, j)
    for i in range(1, rows):
        for j in range(1, cols):
            if reference[i - 1] == prediction[j - 1]:
                cost[i][j] = cost[i - 1][j - 1]
                ops[i][j] = ops[i - 1][j - 1]
                continue
            candidates = [
                (cost[i - 1][j - 1] + 1, add_ops(ops[i - 1][j - 1], (1, 0, 0))),
                (cost[i - 1][j] + 1, add_ops(ops[i - 1][j], (0, 1, 0))),
                (cost[i][j - 1] + 1, add_ops(ops[i][j - 1], (0, 0, 1))),
            ]
            cost[i][j], ops[i][j] = min(candidates, key=lambda value: value[0])
    return ops[-1][-1]


def add_ops(left: tuple[int, int, int], right: tuple[int, int, int]) -> tuple[int, int, int]:
    return (left[0] + right[0], left[1] + right[1], left[2] + right[2])


def score_phone_sequences(rows: list[dict[str, Any]]) -> dict[str, Any]:
    substitutions = deletions = insertions = reference_count = predicted_count = 0
    for row in rows:
        s, d, i = edit_distance(row["reference"], row["prediction"])
        row["substitutions"] = s
        row["deletions"] = d
        row["insertions"] = i
        row["phone_error_rate"] = round((s + d + i) / len(row["reference"]), 6) if row["reference"] else None
        substitutions += s
        deletions += d
        insertions += i
        reference_count += len(row["reference"])
        predicted_count += len(row["prediction"])
    per = (substitutions + deletions + insertions) / reference_count if reference_count else None
    unknown_symbols = sorted(
        {
            symbol
            for row in rows
            for symbol in row["prediction"]
            if symbol not in ARPABET_TO_REFERENCE.values() and symbol not in SILENCE_OR_NOISE
        }
    )
    return {
        "comparable_sentence_count": len(rows),
        "reference_phone_count": reference_count,
        "predicted_phone_count": predicted_count,
        "substitutions": substitutions,
        "deletions": deletions,
        "insertions": insertions,
        "phone_error_rate": round(per, 6) if per is not None else None,
        "unknown_prediction_symbols": unknown_symbols,
        "sample_rows": [compact_phone_sample(row) for row in rows[:10]],
    }


def evaluate_timit(case: dict[str, Any], document: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    concat_path = Path("/tmp/p217-timit/timit-concat.txt")
    if not concat_path.is_file():
        return {"status": "missing_reference", "reference": str(concat_path)}
    wav_files = parse_concat_file(concat_path)
    segments = document.get("segments") or []
    timelines = phone_timelines_by_sentence(document)
    rows: list[dict[str, Any]] = []
    missing_sentence_ids: list[str] = []
    for index, segment in enumerate(segments):
        sentence_id = segment.get("id")
        if not isinstance(sentence_id, str) or index >= len(wav_files):
            continue
        timeline = timelines.get(sentence_id)
        if timeline is None:
            missing_sentence_ids.append(sentence_id)
            continue
        wrd_path = wav_files[index].with_suffix(".WRD")
        phn_path = wav_files[index].with_suffix(".PHN")
        if not wrd_path.is_file() or not phn_path.is_file():
            continue
        word_rows = parse_timit_boundary(wrd_path)
        utterance_start = min(start for start, _, _ in word_rows)
        utterance_end = max(end for _, end, _ in word_rows)
        reference = []
        for start, end, symbol in parse_timit_boundary(phn_path):
            if start < utterance_start or end > utterance_end:
                continue
            normalized = normalize_phone(symbol)
            if normalized:
                reference.append(normalized)
        rows.append(
            {
                "case_index": index,
                "sentence_id": sentence_id,
                "text": segment.get("text", ""),
                "reference": reference,
                "prediction": phones_from_timeline(timeline),
            }
        )
    scored = score_phone_sequences(rows)
    return {
        "status": "scored",
        "metric": "phone_error_rate_content_only",
        "dataset": "timit",
        "timeline_sentence_count": len(segments),
        "generated_phone_timeline_count": len(timelines),
        "coverage": round(len(rows) / len(segments), 6) if segments else 0.0,
        "missing_phone_timeline_count": len(missing_sentence_ids),
        "missing_sentence_ids": missing_sentence_ids[:10],
        **scored,
    }


def parse_buckeye_phones(path: Path) -> list[tuple[int, int, str]]:
    values: list[tuple[int, int, str]] = []
    previous_ms = 0
    after_header = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped == "#":
            after_header = True
            continue
        if not after_header or not stripped:
            continue
        parts = stripped.split()
        if len(parts) < 3:
            continue
        end_ms = int(round(float(parts[0]) * 1000))
        symbol = parts[2]
        normalized = normalize_phone(symbol)
        if normalized:
            values.append((previous_ms, end_ms, normalized))
        previous_ms = end_ms
    return values


def evaluate_buckeye(case: dict[str, Any], document: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    subtitle = case.get("subtitle") or {}
    raw = subtitle.get("local_path")
    if not isinstance(raw, str):
        return {"status": "missing_reference", "reason": "subtitle.local_path is missing"}
    phones_path = expand_path(raw, repo_root).with_suffix(".phones")
    if not phones_path.is_file():
        return {"status": "missing_reference", "reference": str(phones_path)}
    reference_phones = parse_buckeye_phones(phones_path)
    timelines = phone_timelines_by_sentence(document)
    rows: list[dict[str, Any]] = []
    for segment in document.get("segments") or []:
        sentence_id = segment.get("id")
        if not isinstance(sentence_id, str) or sentence_id not in timelines:
            continue
        start_ms = int(segment.get("start_ms", 0))
        end_ms = int(segment.get("end_ms", 0))
        reference = [
            symbol
            for start, end, symbol in reference_phones
            if start >= start_ms and end <= end_ms
        ]
        rows.append(
            {
                "sentence_id": sentence_id,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": segment.get("text", "")[:120],
                "reference": reference,
                "prediction": phones_from_timeline(timelines[sentence_id]),
            }
        )
    scored = score_phone_sequences(rows)
    return {
        "status": "scored",
        "metric": "phone_error_rate_buckeye_actual_pronunciation_windowed",
        "dataset": "buckeye",
        "timeline_sentence_count": len(document.get("segments") or []),
        "generated_phone_timeline_count": len(timelines),
        "coverage": round(len(rows) / len(document.get("segments") or []), 6)
        if document.get("segments")
        else 0.0,
        **scored,
    }


def parse_stm(path: Path) -> list[dict[str, Any]]:
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.strip().split(maxsplit=6)
        if len(parts) < 7:
            continue
        text = parts[6]
        if "ignore_time_segment_in_scoring" in text:
            continue
        rows.append(
            {
                "start_ms": int(round(float(parts[3]) * 1000)),
                "end_ms": int(round(float(parts[4]) * 1000)),
                "text": text,
            }
        )
    return rows


def mean_abs(values: list[int]) -> float | None:
    if not values:
        return None
    return round(statistics.fmean(abs(value) for value in values), 6)


def evaluate_tedlium(case: dict[str, Any], document: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    subtitle = case.get("subtitle") or {}
    raw = subtitle.get("local_path")
    if not isinstance(raw, str):
        return {"status": "missing_reference", "reason": "subtitle.local_path is missing"}
    stm_path = expand_path(raw, repo_root)
    if not stm_path.is_file():
        return {"status": "missing_reference", "reference": str(stm_path)}
    reference_rows = parse_stm(stm_path)
    segments = document.get("segments") or []
    pairs = list(zip(reference_rows, segments))
    exact = 0
    start_offsets = []
    end_offsets = []
    samples = []
    for reference, segment in pairs:
        ref_text = normalize_text(reference["text"])
        seg_text = normalize_text(str(segment.get("text", "")))
        exact += int(ref_text == seg_text)
        start_offsets.append(int(segment.get("start_ms", 0)) - reference["start_ms"])
        end_offsets.append(int(segment.get("end_ms", 0)) - reference["end_ms"])
        if len(samples) < 8 and ref_text != seg_text:
            samples.append(
                {
                    "reference": reference["text"][:160],
                    "candidate": str(segment.get("text", ""))[:160],
                }
            )
    return {
        "status": "scored",
        "metric": "stm_segment_transcript_and_timing",
        "dataset": "tedlium",
        "reference_segment_count": len(reference_rows),
        "timeline_sentence_count": len(segments),
        "comparable_sentence_count": len(pairs),
        "coverage": round(len(pairs) / len(reference_rows), 6) if reference_rows else 0.0,
        "text_exact_match_ratio": round(exact / len(pairs), 6) if pairs else None,
        "start_offset_mean_abs_ms": mean_abs(start_offsets),
        "end_offset_mean_abs_ms": mean_abs(end_offsets),
        "sample_text_mismatches": samples,
    }


def evaluate_case(case: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    path = timeline_path(case, repo_root)
    if path is None:
        return {"case_id": case.get("case_id"), "status": "missing_timeline"}
    document = read_json(path)
    dataset = case.get("dataset")
    if dataset == "timit":
        result = evaluate_timit(case, document, repo_root)
    elif dataset == "buckeye":
        result = evaluate_buckeye(case, document, repo_root)
    elif dataset == "tedlium":
        result = evaluate_tedlium(case, document, repo_root)
    else:
        result = {
            "status": "not_benchmark_scored",
            "reason": "product-media case has no phone/text gold reference",
        }
    return {
        "case_id": case.get("case_id"),
        "title": case.get("title"),
        "dataset": dataset,
        "timeline_path": str(path),
        **result,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="testdata/sound-line-real-media/manifest.jsonl",
    )
    parser.add_argument("--case-id", action="append")
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    manifest = load_manifest(repo_root / args.manifest)
    selected = set(args.case_id or [])
    results = [
        evaluate_case(case, repo_root)
        for case in manifest
        if not selected or case.get("case_id") in selected
    ]
    scored = [item for item in results if item.get("status") == "scored"]
    output = {
        "case_count": len(results),
        "scored_case_count": len(scored),
        "results": results,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
