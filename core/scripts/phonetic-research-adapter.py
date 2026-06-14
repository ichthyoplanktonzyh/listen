#!/usr/bin/env python3
"""Isolated harness for reproducible Milestone 2.0 candidate research."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import platform
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ZIPA_REVISION = "9a8d85ba0d2adcbafe7087b82180d0e65c6f3426"
ZIPA_DEPENDENCIES = ("onnxruntime", "torch", "lhotse", "soundfile", "librosa")
ZIPA_ARTIFACTS = {
    "fp32": {
        "size_bytes": 260267872,
        "sha256": "b7955abbf80065fdeeb90e80fe4e76c6e61f59a305b6015c48e34d7375f91e69",
    },
    "fp16": {
        "size_bytes": 131607660,
        "sha256": "d5631c72b46ea4f39d46b4e76f999db16297e66de29c27b27699b341d78abe93",
    },
    "int8": {
        "size_bytes": 70677672,
        "sha256": "8f0505173e4606b4afe041f19477b38d6a72a98a19863562749066dc496e86ae",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def directory_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def dependency_status() -> dict[str, bool]:
    return {
        dependency: importlib.util.find_spec(dependency) is not None
        for dependency in ZIPA_DEPENDENCIES
    }


def check_zipa(args: argparse.Namespace) -> int:
    dependencies = dependency_status()
    artifact = ZIPA_ARTIFACTS[args.variant]
    model = args.model
    model_status = {
        "path": str(model) if model else None,
        "exists": bool(model and model.is_file()),
        "expected_size_bytes": artifact["size_bytes"],
        "expected_sha256": artifact["sha256"],
    }
    if model_status["exists"]:
        model_status["actual_size_bytes"] = model.stat().st_size
        model_status["actual_sha256"] = sha256(model)
        model_status["matches_expected"] = (
            model_status["actual_size_bytes"] == artifact["size_bytes"]
            and model_status["actual_sha256"] == artifact["sha256"]
        )
    result = {
        "candidate": "zipa-small-crctc-300k",
        "revision": ZIPA_REVISION,
        "variant": args.variant,
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "dependencies": dependencies,
        "model": model_status,
        "license_status": "model_license_metadata_not_verified",
        "timeline_status": (
            "upstream simplified ONNX inference emits a phone sequence but no "
            "stable per-phone timeline; a research adapter must derive and "
            "validate timestamps before scoring"
        ),
        "ready": all(dependencies.values())
        and bool(model_status.get("matches_expected"))
        and args.accept_unverified_model_license,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ready"] else 1


def read_adapter_output(path: Path) -> dict:
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError("candidate adapter emitted no JSON")
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError("candidate adapter output must be one JSON object")
    return value


def normalize_phones(value: dict, start_ms: int, end_ms: int) -> list[dict]:
    phones = value.get("phones")
    if not isinstance(phones, list) or not phones:
        raise ValueError("candidate adapter must emit a non-empty phones list")
    relative = value.get("time_base", "relative") == "relative"
    normalized = []
    previous_end = start_ms
    for index, phone in enumerate(phones):
        if not isinstance(phone, dict) or not isinstance(phone.get("symbol"), str):
            raise ValueError(f"phone {index} requires a symbol")
        phone_start = phone.get("start_ms")
        phone_end = phone.get("end_ms")
        if not isinstance(phone_start, int) or not isinstance(phone_end, int):
            raise ValueError(
                "candidate output without per-phone integer timestamps is not "
                "eligible for the M2.0 detected-phone timeline"
            )
        if relative:
            phone_start += start_ms
            phone_end += start_ms
        if (
            phone_start < start_ms
            or phone_end > end_ms
            or phone_start >= phone_end
            or phone_start < previous_end
        ):
            raise ValueError(f"phone {index} has an invalid or non-monotonic range")
        previous_end = phone_end
        normalized.append(
            {
                "symbol": phone["symbol"],
                "start_ms": phone_start,
                "end_ms": phone_end,
                "token_index": phone.get("token_index"),
                **(
                    {"confidence": phone["confidence"]}
                    if isinstance(phone.get("confidence"), (int, float))
                    else {}
                ),
            }
        )
    return normalized


def sample_rss_bytes(pid: int) -> int | None:
    try:
        value = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            check=False,
            capture_output=True,
            text=True,
        ).stdout.strip()
        return int(value) * 1024 if value else None
    except (OSError, ValueError):
        return None


def append_jsonl(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(value, sort_keys=True) + "\n")


def run_candidate(args: argparse.Namespace) -> int:
    if args.license_id.strip().lower() in {"", "unknown", "pending", "unverified"}:
        raise ValueError("licensed external audio requires a non-pending license_id")
    if not args.audio.is_file():
        raise ValueError("audio file does not exist")
    if not args.model.exists():
        raise ValueError("model path does not exist")
    if args.audio_start_ms < 0 or args.audio_start_ms >= args.audio_end_ms:
        raise ValueError("invalid requested audio range")
    if not args.command:
        raise ValueError("candidate adapter command is required after --")

    replacements = {
        "{audio}": str(args.audio),
        "{model}": str(args.model),
        "{start_ms}": str(args.audio_start_ms),
        "{end_ms}": str(args.audio_end_ms),
    }
    command = [
        replacements.get(part, part)
        for part in args.command
        if part != "--"
    ]
    started = time.monotonic()
    peak_rss = None
    with tempfile.TemporaryDirectory(prefix="llplayernext-phonetic-research-") as raw:
        stdout_path = Path(raw) / "stdout.json"
        stderr_path = Path(raw) / "stderr.log"
        with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
            while process.poll() is None:
                observed = sample_rss_bytes(process.pid)
                peak_rss = max(peak_rss or 0, observed or 0) or None
                time.sleep(0.02)
        elapsed = time.monotonic() - started
        stderr_text = stderr_path.read_text(encoding="utf-8").strip()
        try:
            if process.returncode != 0:
                raise RuntimeError(
                    f"candidate adapter failed with exit {process.returncode}: "
                    f"{stderr_text}"
                )
            raw_result = read_adapter_output(stdout_path)
            phones = normalize_phones(
                raw_result,
                args.audio_start_ms,
                args.audio_end_ms,
            )
        except (json.JSONDecodeError, OSError, RuntimeError, ValueError) as error:
            append_jsonl(
                args.metrics,
                {
                    "case_id": args.case_id,
                    "provider_id": args.provider_id,
                    "model_revision": args.model_revision,
                    "wall_time_seconds": round(elapsed, 6),
                    "observed_process_peak_rss_bytes": peak_rss,
                    "model_size_bytes": directory_size(args.model),
                    "failure": str(error),
                },
            )
            raise

    duration_seconds = (args.audio_end_ms - args.audio_start_ms) / 1000
    result = {
        "case_id": args.case_id,
        "audio_start_ms": args.audio_start_ms,
        "audio_end_ms": args.audio_end_ms,
        "phone_set": args.phone_set,
        "phones": phones,
        "provider_id": args.provider_id,
        "model_revision": args.model_revision,
        "license_id": args.license_id,
    }
    metrics = {
        "case_id": args.case_id,
        "provider_id": args.provider_id,
        "model_revision": args.model_revision,
        "wall_time_seconds": round(elapsed, 6),
        "real_time_factor": round(elapsed / duration_seconds, 6),
        "observed_process_peak_rss_bytes": peak_rss,
        "model_size_bytes": directory_size(args.model),
        "failure": None,
    }
    append_jsonl(args.output, result)
    append_jsonl(args.metrics, metrics)
    print(json.dumps({"result": result, "metrics": metrics}, indent=2, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    check = subparsers.add_parser("check-zipa")
    check.add_argument("--variant", choices=sorted(ZIPA_ARTIFACTS), default="int8")
    check.add_argument("--model", type=Path)
    check.add_argument("--accept-unverified-model-license", action="store_true")

    run = subparsers.add_parser("run")
    run.add_argument("--case-id", required=True)
    run.add_argument("--audio", type=Path, required=True)
    run.add_argument("--audio-start-ms", type=int, required=True)
    run.add_argument("--audio-end-ms", type=int, required=True)
    run.add_argument("--license-id", required=True)
    run.add_argument("--provider-id", required=True)
    run.add_argument("--model", type=Path, required=True)
    run.add_argument("--model-revision", required=True)
    run.add_argument("--phone-set", required=True)
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--metrics", type=Path, required=True)
    run.add_argument("command", nargs=argparse.REMAINDER)

    args = parser.parse_args()
    try:
        return check_zipa(args) if args.command_name == "check-zipa" else run_candidate(args)
    except (json.JSONDecodeError, OSError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
