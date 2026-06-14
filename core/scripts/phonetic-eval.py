#!/usr/bin/env python3
"""Validate and score Milestone 2.0 Phase 0 phonetic-analysis fixtures."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path


REQUIRED_GENRES = {"news", "interview", "conversation"}
REQUIRED_PHENOMENA = {
    "weak_form",
    "flap",
    "td_deletion",
    "contraction",
    "assimilation",
    "word_linking",
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_jsonl(path: Path) -> list[dict]:
    values = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                values.append(json.loads(line))
            except json.JSONDecodeError as error:
                fail(f"{path}:{line_number}: invalid JSON: {error}")
    return values


def index_cases(path: Path) -> dict[str, dict]:
    values = read_jsonl(path)
    cases = {}
    for value in values:
        case_id = value.get("case_id")
        if not isinstance(case_id, str) or not case_id:
            fail(f"{path}: every row requires a non-empty case_id")
        if case_id in cases:
            fail(f"{path}: duplicate case_id {case_id}")
        cases[case_id] = value
    if not cases:
        fail(f"{path}: no cases found")
    return cases


def validate_catalog(path: Path) -> dict:
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not 50 <= len(rows) <= 100:
        fail(f"catalog must contain 50-100 cases, found {len(rows)}")
    ids = [row["case_id"] for row in rows]
    if len(ids) != len(set(ids)):
        fail("catalog case_id values must be unique")
    genres = {row["genre"] for row in rows}
    missing_genres = REQUIRED_GENRES - genres
    if missing_genres:
        fail(f"catalog missing genres: {sorted(missing_genres)}")
    phenomena = {
        item
        for row in rows
        for item in row["phenomena"].split(",")
        if item
    }
    missing_phenomena = REQUIRED_PHENOMENA - phenomena
    if missing_phenomena:
        fail(f"catalog missing phenomena: {sorted(missing_phenomena)}")
    for row in rows:
        if row["redistribution"] not in {"allowed", "prohibited", "unknown"}:
            fail(f"{row['case_id']}: invalid redistribution value")
        if row["reference_status"] not in {"planned", "draft", "verified"}:
            fail(f"{row['case_id']}: invalid reference_status")
        if not row["source_license"].strip():
            fail(f"{row['case_id']}: source_license is required")
    return {
        "case_count": len(rows),
        "genres": dict(Counter(row["genre"] for row in rows)),
        "reference_status": dict(Counter(row["reference_status"] for row in rows)),
        "redistribution": dict(Counter(row["redistribution"] for row in rows)),
        "phenomena": dict(
            Counter(
                item
                for row in rows
                for item in row["phenomena"].split(",")
                if item
            )
        ),
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
                (cost[i - 1][j - 1] + 1, tuple(a + b for a, b in zip(ops[i - 1][j - 1], (1, 0, 0)))),
                (cost[i - 1][j] + 1, tuple(a + b for a, b in zip(ops[i - 1][j], (0, 1, 0)))),
                (cost[i][j - 1] + 1, tuple(a + b for a, b in zip(ops[i][j - 1], (0, 0, 1)))),
            ]
            cost[i][j], ops[i][j] = min(candidates, key=lambda value: value[0])
    return ops[-1][-1]


def validate_phone_timeline(case: dict) -> tuple[bool, int]:
    phones = case.get("phones", [])
    start = case.get("audio_start_ms", 0)
    end = case.get("audio_end_ms", 0)
    previous_end = start
    valid = True
    for phone in phones:
        phone_start = phone.get("start_ms")
        phone_end = phone.get("end_ms")
        if (
            not isinstance(phone_start, int)
            or not isinstance(phone_end, int)
            or phone_start < start
            or phone_end > end
            or phone_start >= phone_end
            or phone_start < previous_end
        ):
            valid = False
        previous_end = phone_end if isinstance(phone_end, int) else previous_end
    return valid, len(phones)


def score(reference_path: Path, prediction_path: Path) -> dict:
    references = index_cases(reference_path)
    predictions = index_cases(prediction_path)
    if set(references) != set(predictions):
        fail("reference and prediction case_id sets differ")
    substitutions = deletions = insertions = reference_phones = 0
    valid_timelines = associated = predicted_phones = 0
    for case_id, reference in references.items():
        prediction = predictions[case_id]
        ref_symbols = [phone["symbol"] for phone in reference["phones"]]
        pred_symbols = [phone["symbol"] for phone in prediction["phones"]]
        s, d, i = edit_distance(ref_symbols, pred_symbols)
        substitutions += s
        deletions += d
        insertions += i
        reference_phones += len(ref_symbols)
        timeline_valid, phone_count = validate_phone_timeline(prediction)
        valid_timelines += int(timeline_valid)
        predicted_phones += phone_count
        associated += sum(phone.get("token_index") is not None for phone in prediction["phones"])
    phone_error_rate = (
        (substitutions + deletions + insertions) / reference_phones
        if reference_phones
        else 0.0
    )
    timeline_ratio = valid_timelines / len(predictions) if predictions else 0.0
    association_coverage = associated / predicted_phones if predicted_phones else 0.0
    return {
        "case_count": len(references),
        "reference_phone_count": reference_phones,
        "predicted_phone_count": predicted_phones,
        "substitutions": substitutions,
        "deletions": deletions,
        "insertions": insertions,
        "phone_error_rate": round(phone_error_rate, 6),
        "timeline_valid_ratio": round(timeline_ratio, 6),
        "token_association_coverage": round(association_coverage, 6),
        "release_gates": {
            "timeline_valid_ratio_at_least_0_95": timeline_ratio >= 0.95,
            "token_association_coverage_at_least_0_85": association_coverage >= 0.85,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    catalog_parser = subparsers.add_parser("validate-catalog")
    catalog_parser.add_argument("catalog", type=Path)
    score_parser = subparsers.add_parser("score")
    score_parser.add_argument("reference", type=Path)
    score_parser.add_argument("prediction", type=Path)
    args = parser.parse_args()
    try:
        result = (
            validate_catalog(args.catalog)
            if args.command == "validate-catalog"
            else score(args.reference, args.prediction)
        )
    except (KeyError, OSError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
