#!/usr/bin/env python3
"""Validate and score Milestone 2.0 Phase 0 phonetic-analysis fixtures."""

from __future__ import annotations

import argparse
import csv
import hashlib
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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_text(case_id: str, value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{case_id}: {field} requires non-empty text")
    return value.strip()


def validate_ranges(
    case_id: str,
    ranges: object,
    field: str,
    start_ms: int,
    end_ms: int,
    *,
    require_symbol: bool = False,
) -> int:
    if not isinstance(ranges, list) or not ranges:
        fail(f"{case_id}: {field} requires a non-empty list")
    previous_end = start_ms
    for index, value in enumerate(ranges):
        if not isinstance(value, dict):
            fail(f"{case_id}: {field}[{index}] must be an object")
        item_start = value.get("start_ms")
        item_end = value.get("end_ms")
        if (
            not isinstance(item_start, int)
            or not isinstance(item_end, int)
            or item_start < start_ms
            or item_end > end_ms
            or item_start >= item_end
            or item_start < previous_end
        ):
            fail(f"{case_id}: {field}[{index}] has an invalid range")
        if require_symbol:
            require_text(case_id, value.get("symbol"), f"{field}[{index}].symbol")
        previous_end = item_end
    return len(ranges)


def validate_inputs(path: Path, catalog_path: Path | None, minimum_cases: int) -> dict:
    cases = index_cases(path)
    if len(cases) < minimum_cases:
        fail(f"input manifest requires at least {minimum_cases} cases, found {len(cases)}")
    catalog_ids = None
    if catalog_path:
        with catalog_path.open(encoding="utf-8", newline="") as handle:
            catalog_ids = {row["case_id"] for row in csv.DictReader(handle, delimiter="\t")}
    redistribution = Counter()
    phone_sets = Counter()
    total_words = total_phones = 0
    for case_id, case in cases.items():
        if catalog_ids is not None and case_id not in catalog_ids:
            fail(f"{case_id}: case_id is not present in the fixed catalog")
        audio_path_value = require_text(case_id, case.get("audio_path"), "audio_path")
        audio_path = Path(audio_path_value).expanduser()
        if not audio_path.is_absolute():
            audio_path = path.parent / audio_path
        if not audio_path.is_file():
            fail(f"{case_id}: audio_path does not exist: {audio_path}")
        expected_sha256 = require_text(
            case_id, case.get("audio_sha256"), "audio_sha256"
        ).lower()
        if len(expected_sha256) != 64 or any(
            char not in "0123456789abcdef" for char in expected_sha256
        ):
            fail(f"{case_id}: audio_sha256 must be a lowercase SHA-256 digest")
        actual_sha256 = sha256(audio_path)
        if actual_sha256 != expected_sha256:
            fail(f"{case_id}: audio checksum mismatch")
        require_text(case_id, case.get("transcript"), "transcript")
        source_license = require_text(
            case_id, case.get("source_license"), "source_license"
        ).lower()
        if source_license in {"unknown", "pending", "license_pending", "unverified"}:
            fail(f"{case_id}: source_license must be verified before evaluation")
        redistribution_value = case.get("redistribution")
        if redistribution_value not in {"allowed", "prohibited"}:
            fail(f"{case_id}: redistribution must be allowed or prohibited")
        redistribution[redistribution_value] += 1
        start_ms = case.get("audio_start_ms")
        end_ms = case.get("audio_end_ms")
        if (
            not isinstance(start_ms, int)
            or not isinstance(end_ms, int)
            or start_ms < 0
            or start_ms >= end_ms
        ):
            fail(f"{case_id}: invalid audio range")
        total_words += validate_ranges(
            case_id, case.get("word_ranges"), "word_ranges", start_ms, end_ms
        )
        for index, word in enumerate(case["word_ranges"]):
            require_text(case_id, word.get("text"), f"word_ranges[{index}].text")
        total_phones += validate_ranges(
            case_id,
            case.get("phones"),
            "phones",
            start_ms,
            end_ms,
            require_symbol=True,
        )
        phone_set = require_text(case_id, case.get("phone_set"), "phone_set")
        phone_sets[phone_set] += 1
        annotator = require_text(case_id, case.get("annotator"), "annotator")
        reviewer = require_text(case_id, case.get("reviewer"), "reviewer")
        if annotator == reviewer:
            fail(f"{case_id}: reviewer must be independent from annotator")
        if case.get("review_status") != "verified":
            fail(f"{case_id}: review_status must be verified")
    return {
        "case_count": len(cases),
        "word_range_count": total_words,
        "phone_count": total_phones,
        "phone_sets": dict(phone_sets),
        "redistribution": dict(redistribution),
        "minimum_cases": minimum_cases,
        "ready_for_candidate_development_run": len(cases) >= 10,
    }


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


def create_input_template(path: Path, case_ids: list[str]) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as handle:
        rows = {
            row["case_id"]: row for row in csv.DictReader(handle, delimiter="\t")
        }
    if not case_ids:
        fail("at least one case ID is required")
    missing = [case_id for case_id in case_ids if case_id not in rows]
    if missing:
        fail(f"case IDs are not present in the fixed catalog: {missing}")
    return [
        {
            "case_id": case_id,
            "audio_path": "",
            "audio_sha256": "",
            "transcript": "",
            "audio_start_ms": 0,
            "audio_end_ms": 0,
            "word_ranges": [],
            "phone_set": "",
            "phones": [],
            "annotator": "",
            "reviewer": "",
            "review_status": "draft",
            "source_license": rows[case_id]["source_license"],
            "redistribution": rows[case_id]["redistribution"],
            "source_locator": "",
            "target_phenomena": [
                value for value in rows[case_id]["phenomena"].split(",") if value
            ],
            "notes": (
                f"genre={rows[case_id]['genre']}; rate={rows[case_id]['rate']}; "
                f"recording_quality={rows[case_id]['recording_quality']}"
            ),
        }
        for case_id in case_ids
    ]


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
    inputs_parser = subparsers.add_parser("validate-inputs")
    inputs_parser.add_argument("manifest", type=Path)
    inputs_parser.add_argument("--catalog", type=Path)
    inputs_parser.add_argument("--minimum-cases", type=int, default=10)
    template_parser = subparsers.add_parser("create-input-template")
    template_parser.add_argument("catalog", type=Path)
    template_parser.add_argument("--case-ids", required=True)
    score_parser = subparsers.add_parser("score")
    score_parser.add_argument("reference", type=Path)
    score_parser.add_argument("prediction", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "validate-catalog":
            result = validate_catalog(args.catalog)
        elif args.command == "validate-inputs":
            if args.minimum_cases < 1:
                fail("minimum-cases must be positive")
            result = validate_inputs(args.manifest, args.catalog, args.minimum_cases)
        elif args.command == "create-input-template":
            case_ids = [
                value.strip() for value in args.case_ids.split(",") if value.strip()
            ]
            for value in create_input_template(args.catalog, case_ids):
                print(json.dumps(value, sort_keys=True))
            return 0
        else:
            result = score(args.reference, args.prediction)
    except (KeyError, OSError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
