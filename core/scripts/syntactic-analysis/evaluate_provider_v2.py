#!/usr/bin/env python3
"""Corrected Phase 3.9.2 query-by-query syntax qualification.

This intentionally leaves the frozen v1 evaluator untouched. Attachment gold,
product ambiguity policy, and artifact validity are reported separately.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import platform
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = Path(__file__).with_name("evaluate_provider.py")
SPEC = importlib.util.spec_from_file_location("syntactic_evaluator_v1", BASE_PATH)
assert SPEC and SPEC.loader
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

DEV_FIXTURE = ROOT / "testdata/syntactic-analysis/ambiguity-dev-v2.jsonl"
VALIDATION_FIXTURE = ROOT / "testdata/syntactic-analysis/ambiguity-validation-v2.jsonl"
VALIDATION_SHA256 = "7d2a81147e5fad2da6a0c79392ec62ff8812ffb45a4d7332a58100ac22523e47"


def normalized(token: dict[str, Any]) -> str:
    return str(token.get("lemma") or token.get("surface") or "").casefold()


def next_content(tokens: list[dict[str, Any]], start: int) -> int | None:
    return next(
        (index for index in range(start + 1, len(tokens)) if tokens[index]["upos"] != "PUNCT"),
        None,
    )


def want_to_query(tokens: list[dict[str, Any]]) -> str:
    """Return allow/block/abstain without lexicalizing the validation text."""
    if any(str(token["surface"]).casefold() == "wanna" for token in tokens):
        return "already_surface_form"
    for want_index, want in enumerate(tokens):
        if normalized(want) != "want":
            continue
        to_index = next_content(tokens, want_index)
        complement_index = next_content(tokens, to_index) if to_index is not None else None
        if (
            to_index is None
            or normalized(tokens[to_index]) != "to"
            or complement_index is None
            or tokens[complement_index]["upos"] not in {"VERB", "AUX"}
        ):
            continue
        wh_heads: list[int] = []
        for index, token in enumerate(tokens[:want_index]):
            surface = str(token["surface"]).casefold()
            if surface in {"who", "what"}:
                wh_heads.append(index)
            elif index > 0 and str(tokens[index - 1]["surface"]).casefold() == "which":
                wh_heads.append(index)
        if not wh_heads:
            return "allow"
        for index in wh_heads:
            token = tokens[index]
            relation = str(token["dependency_relation"])
            if token.get("head_parser_token_index") == complement_index:
                if relation.startswith("nsubj"):
                    return "block"
                if relation.startswith("obj"):
                    return "allow"
        # A visible object already attached to the infinitive makes a wh phrase
        # attached to WANT the embedded subject/control argument, not another
        # object of the infinitive.
        complement_has_object = any(
            token.get("head_parser_token_index") == complement_index
            and str(token["dependency_relation"]).startswith("obj")
            for index, token in enumerate(tokens)
            if index not in wh_heads
        )
        if complement_has_object:
            return "block"
        # Basic dependencies from small English pipelines often attach both
        # subject- and object-extraction NPs to WANT. That evidence is genuinely
        # insufficient; do not turn it into a guessed language fact.
        return "abstain"
    return "block"


QUERY_BY_TARGET: dict[str, Callable[[list[dict[str, Any]]], str]] = {
    "b.future_going_to": BASE.query_future_going_to,
    "b.habitual_used_to": BASE.query_habitual_used_to,
    "b.have_to": BASE.query_have_to,
    "b.want_to": want_to_query,
}


def score_target(target: dict[str, str], tokens: list[dict[str, Any]]) -> dict[str, Any]:
    raw = QUERY_BY_TARGET[target["target"]](tokens)
    role = target["evaluation_role"]
    if role == "surface_coverage":
        return {**target, "raw_actual": raw, "raw_correct": None, "product_actual": raw, "policy_correct": None}
    if role == "product_policy":
        product = "block" if raw == "abstain" else raw
        return {
            **target,
            "raw_actual": raw,
            "raw_correct": None,
            "product_actual": product,
            "policy_correct": raw == target["expected"] and product == target["product_expected"],
        }
    return {
        **target,
        "raw_actual": raw,
        "raw_correct": raw == target["expected"],
        "product_actual": "fallback" if raw == "abstain" else raw,
        "policy_correct": None,
    }


def run_quality(
    python: Path, provider: str, model_dir: Path | None, cases: list[dict[str, Any]]
) -> tuple[dict[str, Any], dict[str, Any], int]:
    sidecar = BASE.Sidecar(python, provider, model_dir)
    try:
        probe, _ = sidecar.exchange("probe", provider)
        response, latency = sidecar.exchange("analyze", provider, BASE.wire_sentences(cases))
        by_id = {sentence["sentence_id"]: sentence for sentence in response["analysis"]["sentences"]}
        reports: list[dict[str, Any]] = []
        total_words = total_mapped = total_exact = total_silent = 0
        per_query: dict[str, dict[str, Any]] = {}
        policy_values: list[bool] = []
        for case in cases:
            sentence = by_id[case["case_id"]]
            alignment = BASE.alignment_metrics(case, sentence)
            total_words += alignment["word_count"]
            total_mapped += alignment["mapped_word_count"]
            total_exact += round(alignment["exact_span_rate"] * alignment["word_count"])
            total_silent += alignment["silent_misalignment_count"]
            decisions = [score_target(target, sentence["tokens"]) for target in case["decision_targets"]]
            for decision in decisions:
                if decision["evaluation_role"] == "attachment_gold":
                    values = per_query.setdefault(
                        decision["target"],
                        {"case_count": 0, "correct_count": 0, "abstain_count": 0, "unsafe_allow_count": 0},
                    )
                    values["case_count"] += 1
                    values["correct_count"] += int(decision["raw_correct"])
                    values["abstain_count"] += int(decision["raw_actual"] == "abstain")
                    values["unsafe_allow_count"] += int(
                        decision["expected"] == "block" and decision["raw_actual"] == "allow"
                    )
                elif decision["evaluation_role"] == "product_policy":
                    policy_values.append(bool(decision["policy_correct"]))
            reports.append(
                {
                    "case_id": case["case_id"],
                    "evidence_class": case["evidence_class"],
                    "alignment": alignment,
                    "tree_issues": BASE.validate_tree(sentence),
                    "decisions": decisions,
                    "tokens": sentence["tokens"],
                }
            )
        tree_issue_count = sum(len(report["tree_issues"]) for report in reports)
        lexical_coverage = total_mapped / total_words if total_words else 1.0
        artifact_qualified = lexical_coverage >= 0.995 and total_silent == 0 and tree_issue_count == 0
        query_matrix = {}
        for target, values in sorted(per_query.items()):
            values["accuracy"] = values["correct_count"] / values["case_count"]
            values["decision"] = (
                "qualified"
                if values["accuracy"] == 1.0
                and values["abstain_count"] == 0
                and values["unsafe_allow_count"] == 0
                else "fallback_only"
            )
            query_matrix[target] = values
        aggregate = {
            "case_count": len(cases),
            "analysis_latency_seconds": latency,
            "lexical_alignment_coverage": lexical_coverage,
            "exact_span_rate": total_exact / total_words if total_words else 1.0,
            "silent_misalignment_count": total_silent,
            "tree_issue_count": tree_issue_count,
            "artifact_structurally_qualified": artifact_qualified,
            "ambiguity_policy_passed": bool(policy_values) and all(policy_values),
            "query_qualification": query_matrix,
        }
        return {"aggregate": aggregate, "cases": reports}, probe["capability"]["descriptor"], sidecar.peak_rss
    finally:
        sidecar.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, choices=("stanza", "spacy"))
    parser.add_argument("--dataset", required=True, choices=("development", "validation"))
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--venv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fixture = DEV_FIXTURE if args.dataset == "development" else VALIDATION_FIXTURE
    digest = hashlib.sha256(fixture.read_bytes()).hexdigest()
    if args.dataset == "validation":
        if digest != VALIDATION_SHA256:
            raise SystemExit(f"locked validation digest mismatch: {digest}")
    cases = BASE.load_cases(fixture)
    model_dir = args.venv / "models/stanza" if args.provider == "stanza" else None
    quality, descriptor, peak_rss = run_quality(args.python, args.provider, model_dir, cases)
    report = {
        "report_version": 2,
        "provider": args.provider,
        "dataset": args.dataset,
        "fixture": str(fixture.relative_to(ROOT)),
        "fixture_sha256": digest,
        "descriptor": descriptor,
        "machine": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "python": platform.python_version(),
            "logical_cpu_count": os.cpu_count(),
        },
        "quality": quality,
        "quality_peak_rss_bytes": peak_rss,
        "consumer_bundle_increment_bytes": 0,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"output": str(args.output), "aggregate": quality["aggregate"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
