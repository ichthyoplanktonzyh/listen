#!/usr/bin/env python3
"""Validate Phase 3.9.1 Slice 0 fixtures without parser dependencies."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "testdata" / "syntactic-analysis"
DEV_PATH = FIXTURE_DIR / "ambiguity-dev-v1.jsonl"
VALIDATION_PATH = FIXTURE_DIR / "ambiguity-validation-v1.jsonl"
MAPPING_PATH = FIXTURE_DIR / "mapping-contract-v1.json"
PREREG_PATH = (
    ROOT
    / ".planning/phases/3.9.1-shared-syntactic-analysis-provider"
    / "3.9.1-EVALUATION-PREREGISTRATION.md"
)

REQUIRED_PHENOMENA = {
    "future_going_to",
    "motion_going_to",
    "want_to",
    "habitual_used_to",
    "state_used_to",
    "have_to",
    "function_word",
    "multiword_proper_name",
    "contraction",
    "asr_no_terminal_punctuation",
    "subtitle_fragment",
    "false_start",
}
ALLOWED_EVIDENCE = {"gold", "manual_product_qa"}
ALLOWED_ALIGNMENT_STATUS = {"exact", "split", "merged", "normalized_overlap"}


def fail(message: str) -> None:
    raise ValueError(message)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as error:
            fail(f"{path}:{line_number}: invalid JSON: {error}")
        if not isinstance(value, dict):
            fail(f"{path}:{line_number}: row must be an object")
        rows.append(value)
    if not rows:
        fail(f"{path}: fixture must not be empty")
    return rows


def validate_ambiguity_rows(rows: list[dict[str, Any]], split: str) -> set[str]:
    ids: set[str] = set()
    texts: set[str] = set()
    phenomena: set[str] = set()
    source_kinds: dict[str, int] = {}
    for row in rows:
        case_id = row.get("case_id")
        if not isinstance(case_id, str) or not re.fullmatch(r"syn-(dev|val)-(real|control)-\d{3}", case_id):
            fail(f"invalid case_id: {case_id!r}")
        if case_id in ids:
            fail(f"duplicate case_id: {case_id}")
        ids.add(case_id)
        if row.get("split") != split:
            fail(f"{case_id}: expected split {split!r}")
        if row.get("language") != "en":
            fail(f"{case_id}: Slice 0 ambiguity fixture must be English")
        if row.get("evidence_class") not in ALLOWED_EVIDENCE:
            fail(f"{case_id}: invalid evidence_class")
        text = row.get("text")
        if not isinstance(text, str) or not text.strip() or text != text.strip():
            fail(f"{case_id}: text must be non-empty and trimmed")
        if text in texts:
            fail(f"{case_id}: duplicate text within split")
        texts.add(text)
        row_phenomena = row.get("phenomena")
        if not isinstance(row_phenomena, list) or not all(isinstance(item, str) for item in row_phenomena):
            fail(f"{case_id}: phenomena must be a string array")
        phenomena.update(row_phenomena)
        source = row.get("source")
        if not isinstance(source, dict) or not isinstance(source.get("kind"), str):
            fail(f"{case_id}: source.kind is required")
        source_kind = source["kind"]
        source_kinds[source_kind] = source_kinds.get(source_kind, 0) + 1
        if source_kind == "real_subtitle_excerpt":
            if row["evidence_class"] != "manual_product_qa":
                fail(f"{case_id}: real excerpts must be manual_product_qa")
            if not re.fullmatch(r"[0-9a-f]{64}", str(source.get("source_sha256", ""))):
                fail(f"{case_id}: real excerpt requires source SHA-256")
            if not isinstance(source.get("cue_index"), int):
                fail(f"{case_id}: real excerpt requires cue_index")
        elif source_kind == "controlled_minimal_pair":
            if row["evidence_class"] != "gold" or not source.get("pair_id"):
                fail(f"{case_id}: controlled pairs require gold + pair_id")
        else:
            fail(f"{case_id}: unsupported source kind {source_kind!r}")
        targets = row.get("decision_targets")
        if not isinstance(targets, list):
            fail(f"{case_id}: decision_targets must be an array")
        for target in targets:
            if not isinstance(target, dict) or not target.get("target") or not target.get("expected"):
                fail(f"{case_id}: malformed decision target")
        expectations = row.get("dependency_expectations")
        if not isinstance(expectations, list) or not expectations:
            fail(f"{case_id}: dependency_expectations must be non-empty")
        if any("provider_id" in key or "canonical" in key for key in row):
            fail(f"{case_id}: fixture must not lock a provider or canonical identity")
    if source_kinds.get("real_subtitle_excerpt", 0) < 4:
        fail(f"{split}: requires at least four real subtitle excerpts")
    if source_kinds.get("controlled_minimal_pair", 0) < 4:
        fail(f"{split}: requires at least four controlled contrasts")
    return texts | {f"phenomenon:{item}" for item in phenomena}


def validate_mapping_contract() -> None:
    document = json.loads(MAPPING_PATH.read_text(encoding="utf-8"))
    if document.get("contract_version") != 1:
        fail("mapping contract_version must be 1")
    if document.get("offset_unit") != "unicode_scalar" or document.get("span_semantics") != "half_open":
        fail("mapping contract must use half-open Unicode scalar spans")
    seen_ids: set[str] = set()
    saw_split = saw_merge = saw_unaligned = saw_non_ascii = False
    for case in document.get("cases", []):
        case_id = case.get("case_id")
        if not isinstance(case_id, str) or case_id in seen_ids:
            fail(f"invalid/duplicate mapping case id: {case_id!r}")
        seen_ids.add(case_id)
        text = case.get("text")
        if not isinstance(text, str):
            fail(f"{case_id}: text is required")
        chars = list(text)
        saw_non_ascii |= any(ord(char) > 127 for char in chars)
        subtitle_tokens = case.get("subtitle_tokens")
        syntactic_tokens = case.get("syntactic_tokens")
        if not isinstance(subtitle_tokens, list) or not isinstance(syntactic_tokens, list):
            fail(f"{case_id}: token arrays are required")
        subtitle_by_index: dict[int, dict[str, Any]] = {}
        cursor = 0
        for position, token in enumerate(subtitle_tokens):
            if token.get("index") != position:
                fail(f"{case_id}: SubtitleToken indices must be contiguous")
            start, end = token.get("start_char"), token.get("end_char")
            if not isinstance(start, int) or not isinstance(end, int) or start != cursor or not start < end <= len(chars):
                fail(f"{case_id}: invalid SubtitleToken span at {position}")
            if "".join(chars[start:end]) != token.get("text"):
                fail(f"{case_id}: SubtitleToken text/span mismatch at {position}")
            subtitle_by_index[position] = token
            cursor = end
        if cursor != len(chars):
            fail(f"{case_id}: SubtitleToken spans must reconstruct the full text")
        mapped_word_indices: set[int] = set()
        parser_indices: set[int] = set()
        for parser_token in syntactic_tokens:
            parser_index = parser_token.get("parser_token_index")
            if not isinstance(parser_index, int) or parser_index in parser_indices:
                fail(f"{case_id}: invalid/duplicate parser token index")
            parser_indices.add(parser_index)
            start, end = parser_token.get("start_char"), parser_token.get("end_char")
            if not isinstance(start, int) or not isinstance(end, int) or not 0 <= start < end <= len(chars):
                fail(f"{case_id}: invalid parser span {parser_index}")
            status = parser_token.get("alignment_status")
            if status not in ALLOWED_ALIGNMENT_STATUS:
                fail(f"{case_id}: invalid alignment status {status!r}")
            indices = parser_token.get("subtitle_token_indices")
            if not isinstance(indices, list) or not indices or len(indices) != len(set(indices)):
                fail(f"{case_id}: parser mapping must be a non-empty set")
            for subtitle_index in indices:
                subtitle_token = subtitle_by_index.get(subtitle_index)
                if subtitle_token is None or subtitle_token["kind"] == "whitespace":
                    fail(f"{case_id}: mappings cannot target missing/whitespace tokens")
                token_start, token_end = subtitle_token["start_char"], subtitle_token["end_char"]
                if max(start, token_start) >= min(end, token_end):
                    fail(f"{case_id}: parser/subtitle spans do not intersect")
                if subtitle_token["kind"] == "word":
                    mapped_word_indices.add(subtitle_index)
            saw_split |= status == "split"
            saw_merge |= len(indices) > 1
        declared_unaligned = set(case.get("unaligned_subtitle_token_indices", []))
        word_indices = {index for index, token in subtitle_by_index.items() if token["kind"] == "word"}
        actual_unaligned = word_indices - mapped_word_indices
        if declared_unaligned != actual_unaligned:
            fail(f"{case_id}: unaligned word indices must be explicit")
        saw_unaligned |= bool(actual_unaligned)
        expected_coverage = case.get("expected_lexical_alignment_coverage")
        coverage = len(mapped_word_indices) / len(word_indices) if word_indices else 1.0
        if expected_coverage is not None and abs(float(expected_coverage) - coverage) > 1e-12:
            fail(f"{case_id}: expected coverage does not match mapping")
    if len(seen_ids) < 4 or not all((saw_split, saw_merge, saw_unaligned, saw_non_ascii)):
        fail("mapping contract must retain split, merge, unaligned, and non-ASCII cases")


def validate_locked_digest() -> str:
    digest = hashlib.sha256(VALIDATION_PATH.read_bytes()).hexdigest()
    prereg = PREREG_PATH.read_text(encoding="utf-8")
    match = re.search(r"`ambiguity-validation-v1\.jsonl` SHA-256:\s*\n`([0-9a-f]{64})`", prereg)
    if not match:
        fail("preregistration is missing a locked validation SHA-256")
    if match.group(1) != digest:
        fail(f"validation fixture digest mismatch: expected {match.group(1)}, got {digest}")
    return digest


def main() -> int:
    dev_rows = load_jsonl(DEV_PATH)
    validation_rows = load_jsonl(VALIDATION_PATH)
    dev_facts = validate_ambiguity_rows(dev_rows, "development")
    validation_facts = validate_ambiguity_rows(validation_rows, "validation")
    dev_texts = {row["text"] for row in dev_rows}
    validation_texts = {row["text"] for row in validation_rows}
    if dev_texts & validation_texts:
        fail("development and validation text must be disjoint")
    combined_phenomena = {
        fact.removeprefix("phenomenon:")
        for fact in dev_facts | validation_facts
        if fact.startswith("phenomenon:")
    }
    missing = REQUIRED_PHENOMENA - combined_phenomena
    if missing:
        fail(f"missing required phenomena: {sorted(missing)}")
    validate_mapping_contract()
    digest = validate_locked_digest()
    print(
        json.dumps(
            {
                "status": "ok",
                "development_cases": len(dev_rows),
                "validation_cases": len(validation_rows),
                "required_phenomena": len(REQUIRED_PHENOMENA),
                "validation_sha256": digest,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"syntactic fixture validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
