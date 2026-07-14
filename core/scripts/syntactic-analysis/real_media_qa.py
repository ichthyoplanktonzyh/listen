#!/usr/bin/env python3
"""Run non-distributable local SRT syntax QA without copying caption text."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any


EVALUATOR_PATH = Path(__file__).with_name("evaluate_provider.py")
SPEC = importlib.util.spec_from_file_location("syntactic_evaluator", EVALUATOR_PATH)
assert SPEC and SPEC.loader
EVALUATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVALUATOR)


def parse_srt(path: Path) -> list[dict[str, Any]]:
    normalized = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    cues: list[dict[str, Any]] = []
    for block in re.split(r"\n{2,}", normalized.strip()):
        lines = block.splitlines()
        if len(lines) < 3 or "-->" not in lines[1]:
            continue
        try:
            cue_index = int(lines[0].strip())
        except ValueError:
            continue
        text = " ".join(line.strip() for line in lines[2:] if line.strip())
        if text:
            cues.append(
                {
                    "case_id": f"real-cue-{cue_index}",
                    "cue_index": cue_index,
                    "text": text,
                    "decision_targets": [],
                }
            )
    return cues


def phrase_observations(case: dict[str, Any], tokens: list[dict[str, Any]]) -> list[dict[str, Any]]:
    surfaces = [str(token["surface"]).casefold() for token in tokens]
    observations = []
    checks = [
        ("future_going_to", "going", "to", EVALUATOR.query_future_going_to),
        ("habitual_used_to", "used", "to", EVALUATOR.query_habitual_used_to),
        ("have_to", None, "to", EVALUATOR.query_have_to),
        ("want_to", "want", "to", EVALUATOR.query_want_to),
    ]
    for target, first, second, query in checks:
        present = False
        for index in range(len(surfaces) - 1):
            first_matches = (
                surfaces[index] in {"have", "has", "had"}
                if first is None
                else surfaces[index] == first
            )
            if first_matches and surfaces[index + 1] == second:
                present = True
                break
        if present:
            observations.append(
                {
                    "cue_index": case["cue_index"],
                    "target": target,
                    "neutral_query": query(tokens),
                }
            )
    return observations


def run(provider: str, python: Path, venv: Path, cues: list[dict[str, Any]]) -> dict[str, Any]:
    model_dir = venv / "models/stanza" if provider == "stanza" else None
    sidecar = EVALUATOR.Sidecar(python, provider, model_dir)
    total_words = total_mapped = total_exact = total_silent = 0
    tree_issues: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []
    batch_latencies = []
    descriptor: dict[str, Any] | None = None
    first_batch_result: list[dict[str, Any]] | None = None
    deterministic_refresh = False
    try:
        probe, _ = sidecar.exchange("probe", provider)
        descriptor = probe["capability"]["descriptor"]
        for batch_index, offset in enumerate(range(0, len(cues), 100)):
            batch_cases = cues[offset : offset + 100]
            response, latency = sidecar.exchange(
                "analyze", provider, EVALUATOR.wire_sentences(batch_cases)
            )
            batch_latencies.append(latency)
            sentences = response["analysis"]["sentences"]
            if batch_index == 0:
                first_batch_result = sentences
            for case, sentence in zip(batch_cases, sentences, strict=True):
                metrics = EVALUATOR.alignment_metrics(case, sentence)
                total_words += metrics["word_count"]
                total_mapped += metrics["mapped_word_count"]
                total_exact += round(metrics["exact_span_rate"] * metrics["word_count"])
                total_silent += metrics["silent_misalignment_count"]
                issues = EVALUATOR.validate_tree(sentence)
                if issues:
                    tree_issues.append({"cue_index": case["cue_index"], "issues": issues})
                observations.extend(phrase_observations(case, sentence["tokens"]))
        refresh_cases = cues[: min(100, len(cues))]
        refresh, _ = sidecar.exchange(
            "analyze", provider, EVALUATOR.wire_sentences(refresh_cases)
        )
        deterministic_refresh = refresh["analysis"]["sentences"] == first_batch_result
    finally:
        sidecar.close()
    return {
        "provider": provider,
        "descriptor": descriptor,
        "cue_count": len(cues),
        "word_count": total_words,
        "lexical_alignment_coverage": total_mapped / total_words if total_words else 1.0,
        "exact_span_rate": total_exact / total_words if total_words else 1.0,
        "silent_misalignment_count": total_silent,
        "tree_issue_count": len(tree_issues),
        "tree_issues": tree_issues,
        "batch_latency_seconds": batch_latencies,
        "peak_rss_bytes": sidecar.peak_rss,
        "deterministic_refresh": deterministic_refresh,
        "phrase_observations": observations,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--srt", type=Path, required=True)
    parser.add_argument("--provider", choices=("stanza", "spacy"), required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--venv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cues = parse_srt(args.srt)
    report = {
        "report_version": 1,
        "input_sha256": hashlib.sha256(args.srt.read_bytes()).hexdigest(),
        "input_text_redistributed": False,
        "result": run(args.provider, args.python, args.venv, cues),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"output": str(args.output), "result": report["result"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
