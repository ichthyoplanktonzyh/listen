#!/usr/bin/env python3
"""Evaluate a syntactic sidecar against the Phase 3.9.1 preregistration.

Validation v1 is digest-locked. The scorer only asks provider-neutral token,
UPOS, feature and dependency queries; it never consumes provider-native labels.
Performance traffic uses the development set even during a validation run, so
the holdout text is analyzed exactly once per candidate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

try:
    import psutil
except ModuleNotFoundError:  # contract/unit tests do not require measurement extras
    psutil = None  # type: ignore[assignment]


ROOT = Path(__file__).resolve().parents[2]
SIDECAR = Path(__file__).with_name("syntax-sidecar.py")
DEV_FIXTURE = ROOT / "testdata/syntactic-analysis/ambiguity-dev-v1.jsonl"
VALIDATION_FIXTURE = ROOT / "testdata/syntactic-analysis/ambiguity-validation-v1.jsonl"
VALIDATION_SHA256 = "8f4b4d7ed03180d1866ae2dfc986f4acd5e85886d49fe09920e16fa8b27b7984"
PROTOCOL_VERSION = 1


def percentile(values: list[float], percentile_value: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(0, min(len(ordered) - 1, int((len(ordered) - 1) * percentile_value + 0.999999)))
    return ordered[rank]


def fixture_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_cases(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def token_kind(character: str, chars: list[str], index: int) -> str:
    inner = (
        character in {"'", "’", "-"}
        and index > 0
        and index + 1 < len(chars)
        and chars[index - 1].isalnum()
        and chars[index + 1].isalnum()
    )
    if character.isalnum() or inner:
        return "word"
    if character.isspace():
        return "whitespace"
    if character.isascii() and not character.isalnum() and not character.isspace():
        return "punctuation"
    if character in {"…", "“", "”", "‘", "’", "—", "–"}:
        return "punctuation"
    return "other"


def tokenize_english(text: str) -> list[dict[str, Any]]:
    """Mirror subtitle-core's scalar-offset tokenizer for evaluation requests."""
    chars = list(text)
    result: list[dict[str, Any]] = []
    start = 0
    while start < len(chars):
        kind = token_kind(chars[start], chars, start)
        end = start + 1
        while end < len(chars) and token_kind(chars[end], chars, end) == kind:
            if kind == "word" and not (
                chars[end].isalnum()
                or (
                    chars[end] in {"'", "’", "-"}
                    and end > 0
                    and end + 1 < len(chars)
                    and chars[end - 1].isalnum()
                    and chars[end + 1].isalnum()
                )
            ):
                break
            end += 1
        surface = "".join(chars[start:end])
        result.append(
            {
                "index": len(result),
                "kind": kind,
                "text": surface,
                "normalized": surface.casefold() if kind == "word" else None,
                "start_char": start,
                "end_char": end,
            }
        )
        start = end
    return result


class Sidecar:
    def __init__(self, python: Path, provider: str, model_dir: Path | None) -> None:
        command = [str(python), str(SIDECAR), "--provider", provider]
        if provider == "stanza":
            command += ["--model", "ewt"]
            if model_dir:
                command += ["--model-dir", str(model_dir)]
        else:
            command += ["--model", "en_core_web_sm"]
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.sequence = 0
        self.peak_rss = 0

    def exchange(self, operation: str, provider: str, sentences: list[dict[str, Any]] | None = None) -> tuple[dict[str, Any], float]:
        self.sequence += 1
        request_id = f"eval-{os.getpid()}-{self.sequence}"
        request: dict[str, Any] = {
            "protocol_version": PROTOCOL_VERSION,
            "request_id": request_id,
            "operation": operation,
            "provider": provider,
            "language": "en",
        }
        if sentences is not None:
            request["sentences"] = sentences
        assert self.process.stdin and self.process.stdout
        started = time.perf_counter()
        self.process.stdin.write(json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        elapsed = time.perf_counter() - started
        try:
            if psutil is None:
                raise RuntimeError("psutil unavailable")
            process = psutil.Process(self.process.pid)
            rss = process.memory_info().rss + sum(
                child.memory_info().rss for child in process.children(recursive=True) if child.is_running()
            )
            self.peak_rss = max(self.peak_rss, rss)
        except (psutil.Error if psutil is not None else RuntimeError):
            pass
        if not line:
            stderr = self.process.stderr.read() if self.process.stderr else ""
            raise RuntimeError(f"sidecar exited without response: {stderr[-1000:]}")
        response = json.loads(line)
        if response.get("request_id") != request_id:
            raise RuntimeError("sidecar request_id mismatch")
        if not response.get("ok"):
            raise RuntimeError(f"sidecar error: {response.get('error')}")
        return response, elapsed

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def wire_sentences(cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "sentence_id": case["case_id"],
            "text": case["text"],
            "subtitle_tokens": tokenize_english(case["text"]),
        }
        for case in cases
    ]


def content_indices(tokens: list[dict[str, Any]]) -> list[int]:
    return [index for index, token in enumerate(tokens) if token["upos"] != "PUNCT"]


def next_content(tokens: list[dict[str, Any]], start: int) -> int | None:
    return next((index for index in range(start + 1, len(tokens)) if tokens[index]["upos"] != "PUNCT"), None)


def previous_content(tokens: list[dict[str, Any]], start: int) -> int | None:
    return next((index for index in range(start - 1, -1, -1) if tokens[index]["upos"] != "PUNCT"), None)


def normalized(token: dict[str, Any]) -> str:
    return str(token.get("lemma") or token.get("surface") or "").casefold()


def query_future_going_to(tokens: list[dict[str, Any]]) -> str:
    if any(str(token["surface"]).casefold() == "gonna" for token in tokens):
        return "already_surface_form"
    for going_index, going in enumerate(tokens):
        if str(going["surface"]).casefold() != "going":
            continue
        to_index = next_content(tokens, going_index)
        complement_index = next_content(tokens, to_index) if to_index is not None else None
        if to_index is None or normalized(tokens[to_index]) != "to" or complement_index is None:
            continue
        complement = tokens[complement_index]
        if complement["upos"] in {"VERB", "AUX"} and normalized(complement) not in {"new", "place"}:
            return "allow"
    return "block"


def query_have_to(tokens: list[dict[str, Any]]) -> str:
    for have_index, have in enumerate(tokens):
        if normalized(have) != "have":
            continue
        to_index = next_content(tokens, have_index)
        verb_index = next_content(tokens, to_index) if to_index is not None else None
        if to_index is None or normalized(tokens[to_index]) != "to" or verb_index is None:
            continue
        verb = tokens[verb_index]
        following = next_content(tokens, verb_index)
        if normalized(verb) == "do" and following is not None and normalized(tokens[following]) == "with":
            return "block"
        if verb["upos"] in {"VERB", "AUX"}:
            return "allow"
    return "block"


def query_habitual_used_to(tokens: list[dict[str, Any]]) -> str:
    for used_index, used in enumerate(tokens):
        if str(used["surface"]).casefold() != "used":
            continue
        before = previous_content(tokens, used_index)
        to_index = next_content(tokens, used_index)
        complement_index = next_content(tokens, to_index) if to_index is not None else None
        if to_index is None or normalized(tokens[to_index]) != "to" or complement_index is None:
            continue
        if before is not None and normalized(tokens[before]) in {"be", "get"}:
            return "block"
        complement = tokens[complement_index]
        verb_form = complement.get("features", {}).get("VerbForm")
        if complement["upos"] in {"VERB", "AUX"} and verb_form != "Ger":
            return "allow"
    return "block"


def query_want_to(tokens: list[dict[str, Any]]) -> str:
    if any(str(token["surface"]).casefold() == "wanna" for token in tokens):
        return "already_surface_form"
    for want_index, want in enumerate(tokens):
        if normalized(want) != "want":
            continue
        to_index = next_content(tokens, want_index)
        complement_index = next_content(tokens, to_index) if to_index is not None else None
        if to_index is None or normalized(tokens[to_index]) != "to" or complement_index is None:
            continue
        complement = tokens[complement_index]
        if complement["upos"] not in {"VERB", "AUX"}:
            continue
        for token in tokens:
            surface = str(token["surface"]).casefold()
            # Current small English models collapse the critical subject/object
            # extraction pair to the same dependency. That is insufficient
            # evidence for a safe wanna activation, so all such wh extraction
            # remains conservatively blocked and falls back to the existing B.
            if surface in {"who", "which", "what"} and token.get("head_parser_token_index") == complement_index:
                if str(token["dependency_relation"]).startswith(("nsubj", "obj")):
                    return "block"
        return "allow"
    return "block"


QUERY_BY_TARGET = {
    "reference_b.future_going_to": query_future_going_to,
    "dependency_query.be_going_to_verb": query_future_going_to,
    "reference_b.have_to_obligation": query_have_to,
    "reference_b.habitual_used_to": query_habitual_used_to,
    "reference_b.want_to_reduction": query_want_to,
}


def score_target(target: dict[str, str], tokens: list[dict[str, Any]]) -> tuple[str, bool | None]:
    actual = QUERY_BY_TARGET[target["target"]](tokens)
    expected = target["expected"]
    if target["target"] == "dependency_query.be_going_to_verb":
        actual = "match" if actual == "allow" else "no_match"
    if expected == "already_surface_form":
        return actual, None
    return actual, actual == expected


def validate_tree(sentence: dict[str, Any]) -> list[str]:
    tokens = sentence["tokens"]
    issues: list[str] = []
    roots = [index for index, token in enumerate(tokens) if token["head_parser_token_index"] is None]
    if len(roots) != 1:
        issues.append(f"root_count:{len(roots)}")
    for index, token in enumerate(tokens):
        start, end = token["start_char"], token["end_char"]
        if not 0 <= start < end <= sentence["source_char_count"]:
            issues.append(f"span:{index}")
        head = token["head_parser_token_index"]
        if head is not None and (not isinstance(head, int) or head < 0 or head >= len(tokens) or head == index):
            issues.append(f"head:{index}")
        seen: set[int] = set()
        cursor: int | None = index
        while cursor is not None and 0 <= cursor < len(tokens):
            if cursor in seen:
                issues.append(f"cycle:{index}")
                break
            seen.add(cursor)
            cursor = tokens[cursor]["head_parser_token_index"]
    return sorted(set(issues))


def alignment_metrics(case: dict[str, Any], sentence: dict[str, Any]) -> dict[str, Any]:
    source_tokens = tokenize_english(case["text"])
    word_tokens = [token for token in source_tokens if token["kind"] == "word"]
    mapped: set[int] = set()
    exact = 0
    silent = 0
    for source in word_tokens:
        linked = [
            token
            for token in sentence["tokens"]
            if source["index"] in token["subtitle_token_indices"]
        ]
        if linked:
            mapped.add(source["index"])
            union_start = min(token["start_char"] for token in linked)
            union_end = max(token["end_char"] for token in linked)
            if union_start == source["start_char"] and union_end == source["end_char"]:
                exact += 1
            for token in linked:
                if not (token["start_char"] < source["end_char"] and source["start_char"] < token["end_char"]):
                    silent += 1
    denominator = len(word_tokens)
    return {
        "word_count": denominator,
        "mapped_word_count": len(mapped),
        "lexical_alignment_coverage": len(mapped) / denominator if denominator else 1.0,
        "exact_span_rate": exact / denominator if denominator else 1.0,
        "silent_misalignment_count": silent,
    }


def run_quality(python: Path, provider: str, model_dir: Path | None, cases: list[dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any], int]:
    sidecar = Sidecar(python, provider, model_dir)
    try:
        probe, _ = sidecar.exchange("probe", provider)
        response, latency = sidecar.exchange("analyze", provider, wire_sentences(cases))
        sentences = response["analysis"]["sentences"]
        by_id = {sentence["sentence_id"]: sentence for sentence in sentences}
        case_reports = []
        total_words = total_mapped = total_exact = total_silent = 0
        correct_values: list[bool] = []
        target_values: dict[str, list[bool]] = {}
        high_risk_false_positives: list[str] = []
        for case in cases:
            sentence = by_id[case["case_id"]]
            alignment = alignment_metrics(case, sentence)
            total_words += alignment["word_count"]
            total_mapped += alignment["mapped_word_count"]
            total_exact += round(alignment["exact_span_rate"] * alignment["word_count"])
            total_silent += alignment["silent_misalignment_count"]
            decisions = []
            for target in case["decision_targets"]:
                actual, correct = score_target(target, sentence["tokens"])
                decisions.append({**target, "actual": actual, "correct": correct})
                if correct is not None:
                    correct_values.append(correct)
                    target_values.setdefault(target["target"], []).append(correct)
                    if target["expected"] == "block" and actual == "allow":
                        high_risk_false_positives.append(f"{case['case_id']}:{target['target']}")
            case_reports.append(
                {
                    "case_id": case["case_id"],
                    "alignment": alignment,
                    "tree_issues": validate_tree(sentence),
                    "decisions": decisions,
                    "tokens": sentence["tokens"],
                }
            )
        aggregate = {
            "case_count": len(cases),
            "analysis_latency_seconds": latency,
            "lexical_alignment_coverage": total_mapped / total_words if total_words else 1.0,
            "exact_span_rate": total_exact / total_words if total_words else 1.0,
            "silent_misalignment_count": total_silent,
            "macro_accuracy": statistics.mean(correct_values) if correct_values else 1.0,
            "target_accuracy": {
                target: statistics.mean(values) for target, values in sorted(target_values.items())
            },
            "high_risk_false_positives": high_risk_false_positives,
            "tree_issue_count": sum(len(report["tree_issues"]) for report in case_reports),
        }
        return {"aggregate": aggregate, "cases": case_reports}, probe["capability"]["descriptor"], sidecar.peak_rss
    finally:
        sidecar.close()


def run_performance(python: Path, provider: str, model_dir: Path | None) -> dict[str, Any]:
    if psutil is None:
        raise RuntimeError("psutil is required for resource evaluation")
    cold: list[float] = []
    peak_rss = 0
    for _ in range(3):
        sidecar = Sidecar(python, provider, model_dir)
        try:
            _, elapsed = sidecar.exchange("probe", provider)
            cold.append(elapsed)
            peak_rss = max(peak_rss, sidecar.peak_rss)
        finally:
            sidecar.close()
    dev = load_cases(DEV_FIXTURE)
    warm_sidecar = Sidecar(python, provider, model_dir)
    try:
        warm_sidecar.exchange("probe", provider)
        requests = wire_sentences(dev)
        latencies: list[float] = []
        for index in range(100):
            _, elapsed = warm_sidecar.exchange("analyze", provider, [requests[index % len(requests)]])
            latencies.append(elapsed)
        batch = [requests[index % len(requests)] | {"sentence_id": f"perf-{index}"} for index in range(100)]
        _, batch_elapsed = warm_sidecar.exchange("analyze", provider, batch)
        peak_rss = max(peak_rss, warm_sidecar.peak_rss)
    finally:
        warm_sidecar.close()
    return {
        "cold_seconds": cold,
        "cold_p95_seconds": percentile(cold, 0.95),
        "warm_sentence_p95_ms": percentile(latencies, 0.95) * 1000,
        "batch_100_seconds": batch_elapsed,
        "batch_sentences_per_second": 100 / batch_elapsed,
        "peak_rss_bytes": peak_rss,
    }


def directory_bytes(path: Path) -> int:
    return sum(candidate.stat().st_size for candidate in path.rglob("*") if candidate.is_file())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, choices=("stanza", "spacy"))
    parser.add_argument("--dataset", required=True, choices=("development", "validation"))
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--venv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--with-performance", action="store_true")
    args = parser.parse_args()
    fixture = DEV_FIXTURE if args.dataset == "development" else VALIDATION_FIXTURE
    digest = fixture_sha256(fixture)
    if args.dataset == "validation" and digest != VALIDATION_SHA256:
        raise SystemExit(f"locked validation digest mismatch: {digest}")
    cases = load_cases(fixture)
    model_dir = args.venv / "models/stanza" if args.provider == "stanza" else None
    quality, descriptor, quality_rss = run_quality(args.python, args.provider, model_dir, cases)
    performance = run_performance(args.python, args.provider, model_dir) if args.with_performance else None
    report = {
        "report_version": 1,
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
            "memory_bytes": psutil.virtual_memory().total if psutil is not None else None,
        },
        "quality": quality,
        "performance": performance,
        "quality_peak_rss_bytes": quality_rss,
        "venv_installed_bytes": directory_bytes(args.venv),
        "consumer_bundle_increment_bytes": 0,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"output": str(args.output), "aggregate": quality["aggregate"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
