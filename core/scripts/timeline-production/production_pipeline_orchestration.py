from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from aligners import available_aligners, get_aligner
from production_pipeline_acoustics import (
    RHYTHM_WORD_ACOUSTIC_PROVIDER_ID,
    RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION,
    append_rhythm_word_acoustic_cues_safe,
)
from production_pipeline_alignment import add_aligned_word_timeline, build_mfa_alignment_request, record_post_alignment_failure
from production_pipeline_audio import prepare_media
from production_pipeline_common import load_json, now_ms
from production_pipeline_conversion import convert_whisperx, default_whisperx_bin
from production_pipeline_report import write_production_report

def resolve_whisperx_command(args: argparse.Namespace) -> list[str] | str:
    if args.whisperx_command:
        return args.whisperx_command.format(
            input=args.input,
            output_dir=args.output_dir,
            model=args.model,
            language=args.language or "",
            device=args.device,
            compute_type=args.compute_type,
            batch_size=args.batch_size,
        )
    executable = args.whisperx_bin or shutil.which("whisperx") or default_whisperx_bin()
    if executable:
        command = [executable]
    elif importlib.util.find_spec("whisperx") is not None:
        command = [sys.executable, "-m", "whisperx"]
    else:
        raise SystemExit(
            "whisperx not found; install the timeline-production venv or pass --whisperx-command"
        )
    command.extend(
        [
            args.input,
            "--model",
            args.model,
            "--output_dir",
            args.output_dir,
            "--output_format",
            "json",
            "--device",
            args.device,
            "--compute_type",
            args.compute_type,
            "--batch_size",
            str(args.batch_size),
        ]
    )
    if args.language:
        command.extend(["--language", args.language])
    if args.align_model:
        command.extend(["--align_model", args.align_model])
    if args.diarize:
        command.append("--diarize")
    if args.hf_token:
        command.extend(["--hf_token", args.hf_token])
    return command


def resolve_mlx_whisper_command(args: argparse.Namespace) -> list[str]:
    mlx_python = getattr(args, "mlx_whisper_python", None) or default_mlx_whisper_python()
    script = Path(__file__).with_name("mlx-whisper-transcribe.py")
    command = [
        mlx_python,
        str(script),
        "--input", args.input,
        "--output-dir", args.output_dir,
        "--model", getattr(args, "mlx_whisper_model", None) or "mlx-community/whisper-large-v3-mlx",
        "--language", args.language or "en",
        "--verbose",
    ]
    if getattr(args, "output_json", None):
        command.extend(["--output-json", args.output_json])
    return command


def default_mlx_whisper_python() -> str:
    candidate = Path(
        os.environ.get(
            "LLPLAYERNEXT_MLX_WHISPER_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mlx-whisper"),
        )
    ) / "venv" / "bin" / "python3"
    return str(candidate) if candidate.exists() else sys.executable


def find_whisperx_json(output_dir: Path, input_path: Path, explicit: str | None) -> Path:
    if explicit:
        output = Path(explicit)
        if not output.exists():
            raise SystemExit(f"expected WhisperX JSON was not created: {output}")
        return output
    preferred = output_dir / f"{input_path.stem}.json"
    if preferred.exists():
        return preferred
    json_files = sorted(output_dir.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    if not json_files:
        raise SystemExit(f"no WhisperX JSON found in {output_dir}")
    return json_files[0]


def run_whisperx(args: argparse.Namespace) -> int:
    report = run_whisperx_report(args)
    if report.get("dry_run"):
        print(json.dumps(report, sort_keys=True))
    else:
        print(json.dumps({"whisperx_json": report["whisperx_json"], "report_path": report["report_path"]}, sort_keys=True))
    return 0


def run_whisperx_report(args: argparse.Namespace) -> dict[str, Any]:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    asr = getattr(args, "asr", "whisperx")
    if asr == "mlx-whisper":
        command = resolve_mlx_whisper_command(args)
    else:
        command = resolve_whisperx_command(args)
    printable = command if isinstance(command, str) else " ".join(shlex.quote(part) for part in command)
    if args.dry_run:
        return {"command": printable, "output_dir": str(output_dir), "asr": asr, "dry_run": True}
    started_at = now_ms()
    subprocess.run(command, shell=isinstance(command, str), check=True)
    output_json = find_whisperx_json(output_dir, Path(args.input), getattr(args, "output_json", None))
    report = {
        "input": args.input,
        "whisperx_json": str(output_json),
        "output_dir": str(output_dir),
        "asr": asr,
        "model": args.model,
        "language": args.language,
        "started_at_ms": started_at,
        "completed_at_ms": now_ms(),
    }
    if asr != "mlx-whisper":
        report["device"] = args.device
        report["compute_type"] = args.compute_type
    report_path = output_dir / "asr-run-report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    report["report_path"] = str(report_path)
    return report


def post_aligner_chain(args: argparse.Namespace) -> list[str]:
    if args.post_aligner == "none":
        return []
    language = getattr(args, "language", None) or "en"
    if args.post_aligner == "auto":
        return available_aligners(language)
    if args.post_aligner_fallback:
        chain = [args.post_aligner]
        for name in available_aligners(language):
            if name not in chain:
                chain.append(name)
        return chain
    return [args.post_aligner]


def _aligner_config_from_args(args: argparse.Namespace) -> dict[str, Any]:
    """Extract aligner configuration from argparse namespace."""
    cfg: dict[str, Any] = {}
    for key in (
        "mfa_align_cli", "mfa_bin", "mfa_root_dir", "mfa_dictionary",
        "mfa_acoustic_model", "mfa_strategy", "mfa_jobs", "mfa_quiet",
        "post_algorithm_id", "post_algorithm_version",
        "post_config_hash", "post_status",
        "mms_fa_align_cli", "mms_fa_python",
    ):
        value = getattr(args, key, None)
        if value is not None:
            cfg[key] = value
    return cfg


def run_single_post_aligner(
    aligner_name: str,
    args: argparse.Namespace,
    document_path: Path,
    audio_path: Path,
    output_dir: Path,
) -> dict[str, Any]:
    language = getattr(args, "language", None) or "en"
    plugin = get_aligner(aligner_name)
    config = _aligner_config_from_args(args)
    aligner_dir = output_dir / aligner_name

    dry_run = getattr(args, "dry_run", False)
    request_path = aligner_dir / "alignment-request.json"

    if dry_run:
        return plugin.align(
            request_path=request_path,
            audio_path=audio_path,
            output_dir=aligner_dir,
            language=language,
            dry_run=True,
            config=config,
        )

    document = load_json(document_path)
    build_mfa_alignment_request(document, audio_path, request_path)

    result = plugin.align(
        request_path=request_path,
        audio_path=audio_path,
        output_dir=aligner_dir,
        language=language,
        dry_run=False,
        config=config,
    )

    aligned = result.get("aligned")
    if not aligned:
        aligned = load_json(Path(result["aligned_path"]))

    timeline = add_aligned_word_timeline(
        document,
        aligned,
        algorithm_id=result.get("algorithm_id", plugin.provider_id),
        algorithm_version=result.get("algorithm_version", plugin.provider_version),
        config_hash=config.get("post_config_hash", "default"),
        status=config.get("post_status", "active"),
    )
    document_path.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return {
        "aligner": aligner_name,
        "request_path": str(request_path),
        "aligned_path": result.get("aligned_path", ""),
        "timeline_id": timeline["id"],
        "word_count": len(timeline["words"]),
        "replaced_word_count": timeline["metrics_json"]["replaced_word_count"],
        "fallback_word_count": timeline["metrics_json"]["fallback_word_count"],
    }


def run_post_alignment_chain(
    args: argparse.Namespace,
    document_path: Path,
    audio_path: Path,
    output_dir: Path,
) -> dict[str, Any] | None:
    chain = post_aligner_chain(args)
    if not chain:
        return None
    if args.dry_run:
        return {
            "policy": "ordered-fallback",
            "chain": chain,
            "plans": [
                run_single_post_aligner(aligner, args, document_path, audio_path, output_dir)
                for aligner in chain
            ],
        }
    failures = []
    for aligner in chain:
        try:
            report = run_single_post_aligner(aligner, args, document_path, audio_path, output_dir)
            report["policy"] = "ordered-fallback"
            report["attempted_aligners"] = chain
            report["failures"] = failures
            return report
        except Exception as error:  # noqa: BLE001 - production fallback must preserve the WhisperX resource.
            failures.append({"aligner": aligner, "error": str(error)})
            record_post_alignment_failure(document_path, aligner=aligner, error=str(error))
            if not args.post_aligner_fallback:
                raise
    return {
        "policy": "ordered-fallback",
        "attempted_aligners": chain,
        "degraded_to": "whisperx",
        "failures": failures,
    }


def apply_mfa_alignment(args: argparse.Namespace) -> int:
    args.post_aligner = "mfa"
    args.post_aligner_fallback = False
    args.language = getattr(args, "language", "en")
    report = run_single_post_aligner("mfa", args, Path(args.input), Path(args.audio), Path(args.output_dir))
    if report.get("dry_run"):
        print(json.dumps(report, sort_keys=True))
    else:
        acoustic_cues = append_rhythm_word_acoustic_cues_safe(Path(args.input), Path(args.audio))
        quality_path = Path(args.output_dir) / "production-report.json"
        quality = write_production_report(Path(args.input), quality_path)
        report["rhythm_word_acoustic_cues"] = acoustic_cues
        report["production_report"] = str(quality_path)
        report["ready_for_manual_review"] = quality["ready_for_manual_review"]
        print(json.dumps(report, sort_keys=True))
    return 0


def apply_mms_fa_alignment(args: argparse.Namespace) -> int:
    args.post_aligner = "mms-fa"
    args.post_aligner_fallback = False
    args.language = getattr(args, "language", "en")
    report = run_single_post_aligner("mms-fa", args, Path(args.input), Path(args.audio), Path(args.output_dir))
    if report.get("dry_run"):
        print(json.dumps(report, sort_keys=True))
    else:
        acoustic_cues = append_rhythm_word_acoustic_cues_safe(Path(args.input), Path(args.audio))
        quality_path = Path(args.output_dir) / "production-report.json"
        quality = write_production_report(Path(args.input), quality_path)
        report["rhythm_word_acoustic_cues"] = acoustic_cues
        report["production_report"] = str(quality_path)
        report["ready_for_manual_review"] = quality["ready_for_manual_review"]
        print(json.dumps(report, sort_keys=True))
    return 0


def produce_whisperx(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    media_dir = output_dir / "media"
    whisperx_dir = output_dir / "whisperx"
    output = Path(args.output or output_dir / "timeline.lltimeline.json")
    media_path = args.media_path or args.input
    if args.dry_run:
        selected_audio = media_dir / ("vocals-16k-mono.wav" if args.vocal_isolation_command else "audio-16k-mono.wav")
        whisperx_args = argparse.Namespace(**whisperx_namespace(args, selected_audio, whisperx_dir))
        whisperx_report = run_whisperx_report(whisperx_args)
        plan = {
            "prepare_media": {
                "input": args.input,
                "output_dir": str(media_dir),
                "vocal_isolation": bool(args.vocal_isolation_command),
            },
            "run_whisperx": whisperx_report,
            "convert": {
                "output": str(output),
                "media_fingerprint": args.media_fingerprint,
                "media_title": args.media_title,
            },
            "rhythm_word_acoustic_cues": {
                "provider_id": RHYTHM_WORD_ACOUSTIC_PROVIDER_ID,
                "provider_version": RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION,
                "audio_path": str(selected_audio),
            },
        }
        post_alignment_plan = run_post_alignment_chain(args, output, selected_audio, output_dir)
        if post_alignment_plan:
            plan["post_align"] = post_alignment_plan
        print(json.dumps(plan, sort_keys=True))
        return 0

    prepare_media(
        argparse.Namespace(
            input=args.input,
            output_dir=str(media_dir),
            vocal_isolation_command=args.vocal_isolation_command,
        )
    )
    preprocessing_artifacts = media_dir / "preprocessing-artifacts.json"
    preprocessing = load_json(preprocessing_artifacts)
    selected_audio = Path(preprocessing["selected_audio_path"])
    whisperx_args = argparse.Namespace(**whisperx_namespace(args, selected_audio, whisperx_dir))
    whisperx_report = run_whisperx_report(whisperx_args)
    convert_whisperx(
        argparse.Namespace(
            input=whisperx_report["whisperx_json"],
            output=str(output),
            media_fingerprint=args.media_fingerprint,
            media_title=args.media_title,
            media_path=media_path,
            media_id=args.media_id,
            track_id=args.track_id,
            timeline_id=args.timeline_id,
            duration_ms=args.duration_ms,
            preprocessing_artifacts=str(preprocessing_artifacts),
            language=args.language,
            algorithm_id=args.algorithm_id,
            algorithm_version=args.algorithm_version,
            config_hash=args.config_hash,
            status=args.status,
        )
    )
    post_alignment_report = run_post_alignment_chain(args, output, selected_audio, output_dir)
    acoustic_cues = append_rhythm_word_acoustic_cues_safe(output, selected_audio)
    report_path = output_dir / "production-report.json"
    report = write_production_report(output, report_path)
    payload = {
        "output": str(output),
        "preprocessing_artifacts": str(preprocessing_artifacts),
        "production_report": str(report_path),
        "ready_for_manual_review": report["ready_for_manual_review"],
        "rhythm_word_acoustic_cues": acoustic_cues,
        "whisperx_json": whisperx_report["whisperx_json"],
    }
    if post_alignment_report:
        payload["post_alignment"] = post_alignment_report
    print(json.dumps(payload, sort_keys=True))
    return 0


def whisperx_namespace(args: argparse.Namespace, selected_audio: Path, whisperx_dir: Path) -> dict[str, Any]:
    return {
        "input": str(selected_audio),
        "output_dir": str(whisperx_dir),
        "output_json": args.output_json,
        "model": args.model,
        "language": args.language,
        "device": args.device,
        "compute_type": args.compute_type,
        "batch_size": args.batch_size,
        "align_model": args.align_model,
        "diarize": args.diarize,
        "hf_token": args.hf_token,
        "whisperx_bin": args.whisperx_bin,
        "whisperx_command": args.whisperx_command,
        "asr": getattr(args, "asr", "whisperx"),
        "mlx_whisper_python": getattr(args, "mlx_whisper_python", None),
        "mlx_whisper_model": getattr(args, "mlx_whisper_model", None),
        "dry_run": args.dry_run,
    }




