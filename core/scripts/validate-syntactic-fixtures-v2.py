#!/usr/bin/env python3
"""Validate the corrected Phase 3.9.2 fixtures and locked digest."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEV = ROOT / "testdata/syntactic-analysis/ambiguity-dev-v2.jsonl"
VALIDATION = ROOT / "testdata/syntactic-analysis/ambiguity-validation-v2.jsonl"
LOCK_PATH = ROOT / "testdata/syntactic-analysis/locked-fixtures-v1.json"
ALLOWED_EVIDENCE = {"gold", "manual_product_qa", "coverage", "heuristic_proxy"}
ALLOWED_ROLES = {"attachment_gold", "product_policy", "surface_coverage"}
REQUIRED_TARGETS = {"b.future_going_to", "b.habitual_used_to", "b.have_to", "b.want_to"}


def load(path: Path) -> list[dict[str, Any]]:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    if not rows:
        raise ValueError(f"{path}: empty fixture")
    return rows


def validate(rows: list[dict[str, Any]], split: str) -> tuple[set[str], set[str]]:
    ids: set[str] = set()
    texts: set[str] = set()
    targets: set[str] = set()
    real_count = controlled_count = policy_count = 0
    for row in rows:
        case_id = row.get("case_id")
        if not isinstance(case_id, str) or not re.fullmatch(r"syn2-(dev|val)-(real|control)-\d{3}", case_id):
            raise ValueError(f"invalid v2 case id: {case_id!r}")
        if case_id in ids or row.get("text") in texts:
            raise ValueError(f"duplicate id/text: {case_id}")
        ids.add(case_id)
        texts.add(row["text"])
        if row.get("split") != split or row.get("language") != "en":
            raise ValueError(f"{case_id}: wrong split/language")
        if row.get("evidence_class") not in ALLOWED_EVIDENCE:
            raise ValueError(f"{case_id}: invalid evidence class")
        source = row.get("source", {})
        kind = source.get("kind")
        if kind == "real_subtitle_excerpt":
            real_count += 1
            if not re.fullmatch(r"[0-9a-f]{64}", str(source.get("source_sha256", ""))):
                raise ValueError(f"{case_id}: real source needs SHA-256")
        elif kind == "controlled_minimal_pair":
            controlled_count += 1
            if row["evidence_class"] != "gold" or not source.get("pair_id"):
                raise ValueError(f"{case_id}: controlled pair needs gold + pair_id")
        elif kind == "controlled_ambiguity":
            policy_count += 1
            if row["evidence_class"] != "heuristic_proxy":
                raise ValueError(f"{case_id}: ambiguity policy is heuristic_proxy")
        else:
            raise ValueError(f"{case_id}: invalid source kind {kind!r}")
        if not isinstance(row.get("alignment_challenges"), list):
            raise ValueError(f"{case_id}: alignment_challenges required")
        for target in row.get("decision_targets", []):
            name = target.get("target")
            role = target.get("evaluation_role")
            if name not in REQUIRED_TARGETS or role not in ALLOWED_ROLES or not target.get("expected"):
                raise ValueError(f"{case_id}: malformed target")
            if role == "product_policy":
                if target["expected"] != "abstain" or target.get("product_expected") != "block":
                    raise ValueError(f"{case_id}: policy must require abstain -> block")
            elif "product_expected" in target:
                raise ValueError(f"{case_id}: only policy targets have product_expected")
            targets.add(name)
    if real_count < 4 or controlled_count < 4 or policy_count != 1:
        raise ValueError(f"{split}: insufficient real/controlled or policy count")
    return texts, targets


def main() -> int:
    dev_texts, dev_targets = validate(load(DEV), "development")
    val_texts, val_targets = validate(load(VALIDATION), "validation")
    if dev_texts & val_texts:
        raise ValueError("v2 development and validation texts overlap")
    if dev_targets != REQUIRED_TARGETS or val_targets != REQUIRED_TARGETS:
        raise ValueError("each split must cover every product target")
    digest = hashlib.sha256(VALIDATION.read_bytes()).hexdigest()
    lock_document = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    lock = lock_document.get("fixtures", {}).get(VALIDATION.name)
    if not isinstance(lock, dict):
        raise ValueError(f"{LOCK_PATH}: missing lock for {VALIDATION.name}")
    expected = lock.get("sha256")
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError(f"{LOCK_PATH}: invalid SHA-256 lock for {VALIDATION.name}")
    if not isinstance(lock.get("provenance"), str) or not lock["provenance"].strip():
        raise ValueError(f"{LOCK_PATH}: missing provenance for {VALIDATION.name}")
    if not isinstance(lock.get("historical_source_path"), str) or not lock[
        "historical_source_path"
    ].strip():
        raise ValueError(f"{LOCK_PATH}: missing historical source path for {VALIDATION.name}")
    if digest != expected:
        raise ValueError("v2 locked fixture digest mismatch")
    print(json.dumps({"status": "ok", "development_cases": len(load(DEV)), "validation_cases": len(load(VALIDATION)), "validation_sha256": digest}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"v2 syntactic fixture validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
