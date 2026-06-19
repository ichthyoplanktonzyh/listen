#!/usr/bin/env python3
"""Local heavy timeline production helpers.

This script intentionally lives outside the app bundle path. It is a production
sidecar utility for local research and content production, and its stable output
is an LLTimeline JSON resource.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from lltimeline_common import tokenize, word_key, word_token_indexes


SCHEMA = "llplayer.timeline.v1"
REPO_ROOT = Path(__file__).resolve().parents[2]


def now_ms() -> int:
    return int(time.time() * 1000)


def stable_id(namespace: str, value: str) -> str:
    return hashlib.sha256(f"{namespace}:{value}".encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ms(value: float | int | None) -> int | None:
    if value is None:
        return None
    return int(round(float(value) * 1000))


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def active_word_timeline(document: dict[str, Any]) -> dict[str, Any] | None:
    timelines = document.get("word_timelines") or []
    active_id = document.get("active_word_timeline_id")
    if active_id:
        for timeline in timelines:
            if isinstance(timeline, dict) and timeline.get("id") == active_id:
                return timeline
    for timeline in timelines:
        if isinstance(timeline, dict) and timeline.get("status") == "active":
            return timeline
    return timelines[0] if timelines and isinstance(timelines[0], dict) else None


def default_mfa_bin() -> str:
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_MFA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mfa"),
        )
    )
    candidate = research_root / "env" / "bin" / "mfa"
    return str(candidate) if candidate.exists() else "mfa"


def default_mfa_root_dir() -> str:
    if "LLPLAYERNEXT_MFA_ROOT_DIR" in os.environ:
        return os.environ["LLPLAYERNEXT_MFA_ROOT_DIR"]
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_MFA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mfa"),
        )
    )
    return str(research_root / "root")


def default_whisperx_bin() -> str | None:
    production_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_TIMELINE_PRODUCTION_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/timeline-production"),
        )
    )
    candidate = production_root / "venv" / "bin" / "whisperx"
    return str(candidate) if candidate.exists() else None


def default_mms_fa_python() -> str:
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_FA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/forced-align"),
        )
    )
    candidate = research_root / "venv" / "bin" / "python"
    return str(candidate) if candidate.exists() else sys.executable


def word_timing_quality(words: list[dict[str, Any]]) -> dict[str, Any]:
    by_sentence: dict[str, list[dict[str, Any]]] = {}
    for word in words:
        by_sentence.setdefault(str(word.get("sentence_id")), []).append(word)
    overlap_count = 0
    large_gap_count = 0
    max_gap_ms = 0
    for sentence_words in by_sentence.values():
        sentence_words.sort(key=lambda word: (int(word.get("start_ms", 0)), int(word.get("end_ms", 0))))
        for left, right in zip(sentence_words, sentence_words[1:]):
            gap = int(right.get("start_ms", 0)) - int(left.get("end_ms", 0))
            if gap < 0:
                overlap_count += 1
            elif gap > 750:
                large_gap_count += 1
            max_gap_ms = max(max_gap_ms, gap)
    confidences = [
        float(word["confidence"])
        for word in words
        if isinstance(word.get("confidence"), (int, float))
    ]
    provider_ids = sorted({str(word.get("provider_id", "unknown")) for word in words})
    return {
        "word_count": len(words),
        "sentence_count": len(by_sentence),
        "overlap_count": overlap_count,
        "large_gap_count": large_gap_count,
        "max_gap_ms": max_gap_ms,
        "confidence_count": len(confidences),
        "average_confidence": round(sum(confidences) / len(confidences), 6) if confidences else None,
        "provider_ids": provider_ids,
        "valid": overlap_count == 0,
    }


def build_production_report(document: dict[str, Any], input_path: str | None = None) -> dict[str, Any]:
    if document.get("schema") != SCHEMA:
        raise SystemExit(f"unsupported LLTimeline schema: {document.get('schema')!r}")
    segments = document.get("segments") or []
    token_word_count = sum(
        1
        for segment in segments
        for token in segment.get("tokens", [])
        if isinstance(token, dict) and token.get("kind") == "word"
    )
    timeline = active_word_timeline(document)
    words = timeline.get("words", []) if timeline else []
    quality = word_timing_quality(words)
    artifacts = document.get("artifacts") or []
    return {
        "report_version": 1,
        "generated_at_ms": now_ms(),
        "input": input_path,
        "schema": document["schema"],
        "media": document.get("metadata", {}).get("media", {}),
        "active_word_timeline_id": document.get("active_word_timeline_id"),
        "segment_count": len(segments),
        "token_word_count": token_word_count,
        "word_timeline_count": len(document.get("word_timelines") or []),
        "active_word_count": quality["word_count"],
        "word_coverage": round(quality["word_count"] / token_word_count, 6) if token_word_count else None,
        "quality": quality,
        "artifact_kinds": [
            artifact.get("kind", "unknown")
            for artifact in artifacts
            if isinstance(artifact, dict)
        ],
        "human_reviewed": document.get("metadata", {}).get("human_reviewed", False),
        "ready_for_manual_review": quality["valid"] and quality["word_count"] > 0,
    }


def write_production_report(input_path: Path, output_path: Path) -> dict[str, Any]:
    document = load_json(input_path)
    report = build_production_report(document, str(input_path))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def build_mfa_alignment_request(
    document: dict[str, Any],
    audio_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    segments = []
    for segment in document.get("segments") or []:
        if not isinstance(segment, dict):
            continue
        words = [
            str(token.get("text") or "").strip()
            for token in segment.get("tokens", [])
            if isinstance(token, dict) and token.get("kind") == "word" and str(token.get("text") or "").strip()
        ]
        if not words:
            continue
        segments.append(
            {
                "index": int(segment["index"]),
                "text": str(segment.get("text") or "").strip(),
                "words": words,
                "start_ms": int(segment["start_ms"]),
                "end_ms": int(segment["end_ms"]),
            }
        )
    if not segments:
        raise SystemExit("no word-bearing LLTimeline segments available for MFA")
    request = {
        "audio_path": str(audio_path),
        "segments": segments,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return request


def segment_word_keys(document: dict[str, Any]) -> dict[tuple[int, int], tuple[str, int, str]]:
    keys: dict[tuple[int, int], tuple[str, int, str]] = {}
    for segment in document.get("segments") or []:
        if not isinstance(segment, dict):
            continue
        token_indexes = word_token_indexes(segment.get("tokens", []))
        for word_index, token_index in enumerate(token_indexes):
            token = next(
                (
                    item
                    for item in segment.get("tokens", [])
                    if isinstance(item, dict) and int(item.get("index", -1)) == int(token_index)
                ),
                None,
            )
            text = str(token.get("text") if isinstance(token, dict) else "").strip()
            keys[(int(segment["index"]), word_index)] = (str(segment["id"]), int(token_index), text)
    return keys


def timeline_word_map(timeline: dict[str, Any]) -> dict[tuple[str, int], dict[str, Any]]:
    return {
        word_key(word): dict(word)
        for word in timeline.get("words", [])
        if isinstance(word, dict) and "sentence_id" in word and "token_index" in word
    }


def sorted_timeline_words(document: dict[str, Any], words: dict[tuple[str, int], dict[str, Any]]) -> list[dict[str, Any]]:
    ordered: list[dict[str, Any]] = []
    for segment in sorted(document.get("segments") or [], key=lambda item: int(item.get("index", 0))):
        for token_index in word_token_indexes(segment.get("tokens", [])):
            word = words.get((str(segment["id"]), int(token_index)))
            if word:
                ordered.append(word)
    return ordered


def add_aligned_word_timeline(
    document: dict[str, Any],
    aligned: dict[str, Any],
    *,
    algorithm_id: str,
    algorithm_version: str,
    config_hash: str,
    status: str,
) -> dict[str, Any]:
    parent = active_word_timeline(document)
    if not parent:
        raise SystemExit("cannot add aligned timeline without an active source word timeline")

    created_at = now_ms()
    media = document.get("metadata", {}).get("media", {})
    media_id = str(parent.get("media_id") or media.get("id") or stable_id("media", "unknown"))
    track_id = str(parent.get("track_id") or document.get("metadata", {}).get("extra", {}).get("track_id") or media_id)
    timeline_id = stable_id(
        "word-timeline",
        f"{track_id}:{algorithm_id}:{algorithm_version}:{config_hash}:{parent.get('id')}",
    )

    segment_keys = segment_word_keys(document)
    merged_words = timeline_word_map(parent)
    replaced = 0
    skipped = []

    for row in aligned.get("timings", []):
        if not isinstance(row, dict):
            continue
        segment_index = int(row.get("segment_index", -1))
        word_index = int(row.get("word_index", -1))
        key = segment_keys.get((segment_index, word_index))
        if not key:
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "word_key_missing"})
            continue
        sentence_id, token_index, token_text = key
        if row.get("skipped"):
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "aligner_skipped"})
            continue
        start_ms = row.get("start_ms")
        end_ms = row.get("end_ms")
        if not isinstance(start_ms, int) or not isinstance(end_ms, int) or end_ms <= start_ms:
            skipped.append({"segment_index": segment_index, "word_index": word_index, "reason": "invalid_timing"})
            continue
        merged_words[(sentence_id, token_index)] = {
            "sentence_id": sentence_id,
            "token_index": token_index,
            "text": str(row.get("text") or token_text),
            "start_ms": start_ms,
            "end_ms": end_ms,
            "confidence": row.get("score"),
            "timing_source": "forced_aligned",
            "provider_id": aligned.get("provider_id", algorithm_id),
            "provider_version": aligned.get("provider_version", algorithm_version),
        }
        replaced += 1

    words = sorted_timeline_words(document, merged_words)
    timeline = {
        "id": timeline_id,
        "track_id": track_id,
        "media_id": media_id,
        "algorithm_id": algorithm_id,
        "algorithm_version": algorithm_version,
        "config_hash": config_hash,
        "parent_timeline_id": parent.get("id"),
        "created_by": "algorithm",
        "status": status,
        "metrics_json": {
            "source": "post_alignment",
            "provider_id": aligned.get("provider_id", algorithm_id),
            "provider_version": aligned.get("provider_version", algorithm_version),
            "source_timeline_id": parent.get("id"),
            "input_word_count": len(parent.get("words", [])),
            "aligned_timing_count": len(aligned.get("timings", [])),
            "replaced_word_count": replaced,
            "fallback_word_count": max(0, len(words) - replaced),
            "skipped": skipped,
            "diagnostics": aligned.get("diagnostics", {}),
        },
        "words": words,
        "created_at_ms": created_at,
        "updated_at_ms": created_at,
    }
    document.setdefault("word_timelines", []).append(timeline)
    if status == "active":
        if parent.get("status") == "active":
            parent["status"] = "candidate"
        document["active_word_timeline_id"] = timeline_id
    document.setdefault("artifacts", []).append(
        {
            "kind": "post_alignment",
            "provider_id": algorithm_id,
            "provider_version": algorithm_version,
            "payload": {
                "timeline_id": timeline_id,
                "source_timeline_id": parent.get("id"),
                "replaced_word_count": replaced,
                "fallback_word_count": max(0, len(words) - replaced),
            },
        }
    )
    return timeline


def record_post_alignment_failure(
    document_path: Path,
    *,
    aligner: str,
    error: str,
) -> None:
    document = load_json(document_path)
    document.setdefault("artifacts", []).append(
        {
            "kind": "post_alignment_failure",
            "provider_id": aligner,
            "provider_version": "fallback-chain-v1",
            "payload": {
                "error": error,
                "recorded_at_ms": now_ms(),
            },
        }
    )
    document_path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def report_lltimeline(args: argparse.Namespace) -> int:
    report = write_production_report(Path(args.input), Path(args.output))
    print(
        json.dumps(
            {
                "output": args.output,
                "segments": report["segment_count"],
                "words": report["active_word_count"],
                "ready_for_manual_review": report["ready_for_manual_review"],
            },
            sort_keys=True,
        )
    )
    return 0


def convert_whisperx(args: argparse.Namespace) -> int:
    source = load_json(Path(args.input))
    raw_segments = source.get("segments")
    if not isinstance(raw_segments, list) or not raw_segments:
        raise SystemExit("WhisperX JSON must contain a non-empty segments array")

    created_at = now_ms()
    media_id = args.media_id or stable_id("media", args.media_fingerprint)
    track_id = args.track_id or stable_id("subtitle-track", f"{media_id}:{args.media_fingerprint}:whisperx")
    timeline_id = args.timeline_id or stable_id(
        "word-timeline",
        f"{track_id}:{args.algorithm_id}:{args.algorithm_version}:{args.config_hash}",
    )
    segments: list[dict[str, Any]] = []
    timings: list[dict[str, Any]] = []
    skipped_words: list[dict[str, Any]] = []

    for segment_index, segment in enumerate(raw_segments):
        start_ms = ms(segment.get("start"))
        end_ms = ms(segment.get("end"))
        text = str(segment.get("text") or "").strip()
        if start_ms is None or end_ms is None or end_ms <= start_ms or not text:
            skipped_words.append({"segment_index": segment_index, "reason": "invalid_segment"})
            continue
        sentence_id = stable_id("subtitle-sentence", f"{track_id}:{segment_index}:{start_ms}:{end_ms}:{text}")
        tokens = tokenize(text)
        segments.append(
            {
                "id": sentence_id,
                "index": segment_index,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": text,
                "display_text": text,
                "tokens": tokens,
            }
        )

        token_indexes = word_token_indexes(tokens)
        words = segment.get("words") or []
        if not isinstance(words, list):
            skipped_words.append({"segment_index": segment_index, "reason": "invalid_words"})
            continue
        for word_index, word in enumerate(words):
            if word_index >= len(token_indexes) or not isinstance(word, dict):
                skipped_words.append(
                    {
                        "segment_index": segment_index,
                        "word_index": word_index,
                        "reason": "token_missing",
                    }
                )
                continue
            word_start_ms = ms(word.get("start"))
            word_end_ms = ms(word.get("end"))
            if word_start_ms is None or word_end_ms is None or word_end_ms <= word_start_ms:
                skipped_words.append(
                    {
                        "segment_index": segment_index,
                        "word_index": word_index,
                        "word": word.get("word"),
                        "reason": "timing_missing",
                    }
                )
                continue
            timings.append(
                {
                    "sentence_id": sentence_id,
                    "token_index": token_indexes[word_index],
                    "text": str(word.get("word") or "").strip(),
                    "start_ms": word_start_ms,
                    "end_ms": word_end_ms,
                    "confidence": word.get("score"),
                    "timing_source": "forced_aligned",
                    "provider_id": args.algorithm_id,
                    "provider_version": args.algorithm_version,
                }
            )

    if not segments:
        raise SystemExit("no valid WhisperX segments were converted")
    if not timings:
        raise SystemExit("no valid WhisperX word timings were converted")
    artifacts = [
        {
            "kind": "alignment_diagnostics",
            "provider_id": args.algorithm_id,
            "provider_version": args.algorithm_version,
            "payload": {
                "input": str(args.input),
                "skipped_words": skipped_words,
            },
        }
    ]
    if args.preprocessing_artifacts:
        preprocessing = load_json(Path(args.preprocessing_artifacts))
        artifacts.append(
            {
                "kind": "preprocessing",
                "provider_id": "llplayernext-production-pipeline",
                "provider_version": "phase3-v1",
                "payload": preprocessing,
            }
        )

    document = {
        "schema": SCHEMA,
        "metadata": {
            "created_at_ms": created_at,
            "generator": {
                "id": "llplayernext-production-pipeline",
                "version": "phase3-v1",
                "mode": "production_engine",
            },
            "media": {
                "id": media_id,
                "fingerprint": args.media_fingerprint,
                "path": args.media_path,
                "title": args.media_title,
                "duration_ms": args.duration_ms,
            },
            "language": args.language,
            "human_reviewed": False,
            "extra": {
                "track_id": track_id,
                "track_fingerprint": stable_id("track-fingerprint", json.dumps(segments, sort_keys=True)),
                "track_source": "whisperx-json",
                "pipeline": "whisperx-json-import",
            },
        },
        "segments": segments,
        "word_timelines": [
            {
                "id": timeline_id,
                "track_id": track_id,
                "media_id": media_id,
                "algorithm_id": args.algorithm_id,
                "algorithm_version": args.algorithm_version,
                "config_hash": args.config_hash,
                "parent_timeline_id": None,
                "created_by": "algorithm",
                "status": args.status,
                "metrics_json": {
                    "source": "whisperx-json",
                    "converted_at_ms": created_at,
                    "segment_count": len(segments),
                    "word_count": len(timings),
                    "skipped_words": skipped_words,
                },
                "words": timings,
                "created_at_ms": created_at,
                "updated_at_ms": created_at,
            }
        ],
        "active_word_timeline_id": timeline_id if args.status == "active" else None,
        "phone_timelines": [],
        "active_phone_timeline_id": None,
        "chunk_timelines": [],
        "active_chunk_timeline_id": None,
        "artifacts": artifacts,
    }
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    Path(args.output).write_text(output, encoding="utf-8")
    print(json.dumps({"output": args.output, "segments": len(segments), "words": len(timings)}, sort_keys=True))
    return 0


def extract_audio(input_path: str, output: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg not found")
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        input_path,
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-sample_fmt",
        "s16",
        str(output),
    ]
    subprocess.run(command, check=True)


def prepare_audio(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "audio-16k-mono.wav"
    extract_audio(args.input, output)
    print(json.dumps({"audio_path": str(output)}, sort_keys=True))
    return 0


def prepare_media(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_audio = output_dir / "audio-16k-mono.wav"
    vocals_audio = output_dir / "vocals-16k-mono.wav"
    started_at = now_ms()
    extract_audio(args.input, raw_audio)

    isolation: dict[str, Any] = {"enabled": False}
    selected_audio = raw_audio
    if args.vocal_isolation_command:
        command = args.vocal_isolation_command.format(
            input=str(raw_audio),
            output=str(vocals_audio),
            output_dir=str(output_dir),
        )
        subprocess.run(command, shell=True, check=True)
        if not vocals_audio.exists():
            raise SystemExit(f"vocal isolation command did not create {vocals_audio}")
        selected_audio = vocals_audio
        isolation = {
            "enabled": True,
            "command": args.vocal_isolation_command,
            "output_path": str(vocals_audio),
            "sha256": file_sha256(vocals_audio),
        }

    artifacts = {
        "input_path": args.input,
        "started_at_ms": started_at,
        "completed_at_ms": now_ms(),
        "raw_audio": {
            "path": str(raw_audio),
            "sample_rate_hz": 16000,
            "channels": 1,
            "sample_format": "s16",
            "sha256": file_sha256(raw_audio),
        },
        "selected_audio_path": str(selected_audio),
        "vocal_isolation": isolation,
    }
    artifact_path = output_dir / "preprocessing-artifacts.json"
    artifact_path.write_text(json.dumps(artifacts, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "audio_path": str(selected_audio),
                "artifacts_path": str(artifact_path),
                "vocal_isolation": isolation["enabled"],
            },
            sort_keys=True,
        )
    )
    return 0


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
    command = resolve_whisperx_command(args)
    printable = command if isinstance(command, str) else " ".join(shlex.quote(part) for part in command)
    if args.dry_run:
        return {"command": printable, "output_dir": str(output_dir), "dry_run": True}
    started_at = now_ms()
    subprocess.run(command, shell=isinstance(command, str), check=True)
    output_json = find_whisperx_json(output_dir, Path(args.input), args.output_json)
    report = {
        "input": args.input,
        "whisperx_json": str(output_json),
        "output_dir": str(output_dir),
        "model": args.model,
        "language": args.language,
        "device": args.device,
        "compute_type": args.compute_type,
        "started_at_ms": started_at,
        "completed_at_ms": now_ms(),
    }
    report_path = output_dir / "whisperx-run-report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    report["report_path"] = str(report_path)
    return report


def run_mfa_post_alignment(args: argparse.Namespace, document_path: Path, audio_path: Path, output_dir: Path) -> dict[str, Any]:
    request_path = output_dir / "mfa-alignment-request.json"
    aligned_path = output_dir / "mfa-aligned.json"
    work_dir = output_dir / "mfa-work"
    mfa_script = Path(args.mfa_align_cli or REPO_ROOT / "scripts" / "forced-align" / "mfa-align-cli.py")
    command = [
        sys.executable,
        str(mfa_script),
        "--input",
        str(request_path),
        "--work-dir",
        str(work_dir),
        "--output",
        str(aligned_path),
        "--mfa-bin",
        args.mfa_bin or default_mfa_bin(),
        "--mfa-root-dir",
        args.mfa_root_dir or default_mfa_root_dir(),
        "--dictionary",
        args.mfa_dictionary,
        "--acoustic-model",
        args.mfa_acoustic_model,
        "--strategy",
        args.mfa_strategy,
        "--jobs",
        str(args.mfa_jobs),
    ]
    if args.mfa_quiet:
        command.append("--quiet")
    if args.dry_run:
        return {
            "aligner": "mfa",
            "dry_run": True,
            "command": " ".join(shlex.quote(part) for part in command),
            "request_path": str(request_path),
            "aligned_path": str(aligned_path),
            "work_dir": str(work_dir),
        }
    document = load_json(document_path)
    build_mfa_alignment_request(document, audio_path, request_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(command, check=True)
    aligned = load_json(aligned_path)
    timeline = add_aligned_word_timeline(
        document,
        aligned,
        algorithm_id=args.post_algorithm_id,
        algorithm_version=args.post_algorithm_version,
        config_hash=args.post_config_hash,
        status=args.post_status,
    )
    document_path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "aligner": "mfa",
        "request_path": str(request_path),
        "aligned_path": str(aligned_path),
        "timeline_id": timeline["id"],
        "word_count": len(timeline["words"]),
        "replaced_word_count": timeline["metrics_json"]["replaced_word_count"],
        "fallback_word_count": timeline["metrics_json"]["fallback_word_count"],
    }


def run_mms_fa_post_alignment(args: argparse.Namespace, document_path: Path, audio_path: Path, output_dir: Path) -> dict[str, Any]:
    request_path = output_dir / "mms-fa-alignment-request.json"
    aligned_path = output_dir / "mms-fa-aligned.json"
    align_script = Path(args.mms_fa_align_cli or REPO_ROOT / "scripts" / "forced-align" / "align-cli.py")
    command = [
        args.mms_fa_python or default_mms_fa_python(),
        str(align_script),
    ]
    if args.dry_run:
        return {
            "aligner": "mms-fa",
            "dry_run": True,
            "command": " ".join(shlex.quote(part) for part in command),
            "request_path": str(request_path),
            "aligned_path": str(aligned_path),
        }
    document = load_json(document_path)
    request = build_mfa_alignment_request(document, audio_path, request_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        command,
        input=json.dumps(request),
        text=True,
        capture_output=True,
        check=True,
    )
    aligned = json.loads(completed.stdout)
    aligned["provider_id"] = "torchaudio-ctc-forced-aligner"
    aligned["provider_version"] = "mms-fa-v1"
    aligned_path.write_text(json.dumps(aligned, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    timeline = add_aligned_word_timeline(
        document,
        aligned,
        algorithm_id="whisperx-transcript-mms-fa",
        algorithm_version="large-v3-mms-fa-v1",
        config_hash=args.post_config_hash,
        status=args.post_status,
    )
    document_path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "aligner": "mms-fa",
        "request_path": str(request_path),
        "aligned_path": str(aligned_path),
        "timeline_id": timeline["id"],
        "word_count": len(timeline["words"]),
        "replaced_word_count": timeline["metrics_json"]["replaced_word_count"],
        "fallback_word_count": timeline["metrics_json"]["fallback_word_count"],
    }


def post_aligner_chain(args: argparse.Namespace) -> list[str]:
    if args.post_aligner == "none":
        return []
    if args.post_aligner == "auto":
        return ["mfa", "mms-fa"]
    if args.post_aligner == "mfa" and args.post_aligner_fallback:
        return ["mfa", "mms-fa"]
    return [args.post_aligner]


def run_single_post_aligner(
    aligner: str,
    args: argparse.Namespace,
    document_path: Path,
    audio_path: Path,
    output_dir: Path,
) -> dict[str, Any]:
    if aligner == "mfa":
        return run_mfa_post_alignment(argparse.Namespace(**mfa_namespace(args), dry_run=args.dry_run), document_path, audio_path, output_dir / "mfa")
    if aligner == "mms-fa":
        return run_mms_fa_post_alignment(
            argparse.Namespace(**mms_fa_namespace(args), dry_run=args.dry_run),
            document_path,
            audio_path,
            output_dir / "mms-fa",
        )
    raise SystemExit(f"unsupported post aligner: {aligner}")


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
    report = run_mfa_post_alignment(
        args,
        Path(args.input),
        Path(args.audio),
        Path(args.output_dir),
    )
    if args.dry_run:
        print(json.dumps(report, sort_keys=True))
    else:
        quality_path = Path(args.output_dir) / "production-report.json"
        quality = write_production_report(Path(args.input), quality_path)
        report["production_report"] = str(quality_path)
        report["ready_for_manual_review"] = quality["ready_for_manual_review"]
        print(json.dumps(report, sort_keys=True))
    return 0


def apply_mms_fa_alignment(args: argparse.Namespace) -> int:
    report = run_mms_fa_post_alignment(
        argparse.Namespace(**mms_fa_namespace(args), dry_run=args.dry_run),
        Path(args.input),
        Path(args.audio),
        Path(args.output_dir),
    )
    if args.dry_run:
        print(json.dumps(report, sort_keys=True))
    else:
        quality_path = Path(args.output_dir) / "production-report.json"
        quality = write_production_report(Path(args.input), quality_path)
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
    report_path = output_dir / "production-report.json"
    report = write_production_report(output, report_path)
    payload = {
        "output": str(output),
        "preprocessing_artifacts": str(preprocessing_artifacts),
        "production_report": str(report_path),
        "ready_for_manual_review": report["ready_for_manual_review"],
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
        "dry_run": args.dry_run,
    }


def mfa_namespace(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "mfa_align_cli": args.mfa_align_cli,
        "mfa_bin": args.mfa_bin,
        "mfa_root_dir": args.mfa_root_dir,
        "mfa_dictionary": args.mfa_dictionary,
        "mfa_acoustic_model": args.mfa_acoustic_model,
        "mfa_strategy": args.mfa_strategy,
        "mfa_jobs": args.mfa_jobs,
        "mfa_quiet": args.mfa_quiet,
        "post_algorithm_id": args.post_algorithm_id,
        "post_algorithm_version": args.post_algorithm_version,
        "post_config_hash": args.post_config_hash,
        "post_status": args.post_status,
    }


def mms_fa_namespace(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "mms_fa_align_cli": args.mms_fa_align_cli,
        "mms_fa_python": args.mms_fa_python,
        "post_config_hash": args.post_config_hash,
        "post_status": args.post_status,
    }


def add_mfa_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--mfa-align-cli", help="path to scripts/forced-align/mfa-align-cli.py")
    parser.add_argument("--mfa-bin", help="path to the MFA executable")
    parser.add_argument("--mfa-root-dir", help="MFA_ROOT_DIR containing downloaded/extracted models")
    parser.add_argument("--mfa-dictionary", default="english_us_arpa")
    parser.add_argument("--mfa-acoustic-model", default="english_us_arpa")
    parser.add_argument("--mfa-strategy", choices=["align", "align-one"], default="align-one")
    parser.add_argument("--mfa-jobs", type=int, default=4)
    parser.add_argument("--mfa-quiet", action="store_true")
    parser.add_argument("--post-algorithm-id", default="whisperx-transcript-mfa")
    parser.add_argument("--post-algorithm-version", default="large-v3-mfa-arpa-align-one")
    parser.add_argument("--post-config-hash", default="default")
    parser.add_argument("--post-status", choices=["candidate", "active", "archived"], default="active")


def add_mms_fa_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--mms-fa-align-cli", help="path to scripts/forced-align/align-cli.py")
    parser.add_argument("--mms-fa-python", help="path to the MMS_FA research venv Python")


def doctor(_: argparse.Namespace) -> int:
    mfa_bin = default_mfa_bin()
    mms_fa_python = default_mms_fa_python()
    checks = {
        "ffmpeg": shutil.which("ffmpeg") is not None,
        "python": True,
        "whisperx": importlib.util.find_spec("whisperx") is not None,
        "torch": importlib.util.find_spec("torch") is not None,
        "torchaudio": importlib.util.find_spec("torchaudio") is not None,
        "demucs": importlib.util.find_spec("demucs") is not None,
        "mfa": Path(mfa_bin).exists() or shutil.which(mfa_bin) is not None,
        "mfa_bin": mfa_bin,
        "mfa_root_dir": default_mfa_root_dir(),
        "mms_fa_python": mms_fa_python,
        "mms_fa_python_exists": Path(mms_fa_python).exists(),
        "uvr_env": "UVR_MODELS_DIR" in os.environ,
    }
    print(json.dumps(checks, sort_keys=True))
    return 0 if checks["ffmpeg"] else 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    check = subcommands.add_parser("doctor", help="check local production dependencies")
    check.set_defaults(func=doctor)

    audio = subcommands.add_parser("prepare-audio", help="extract normalized wav for alignment")
    audio.add_argument("--input", required=True)
    audio.add_argument("--output-dir", required=True)
    audio.set_defaults(func=prepare_audio)

    media = subcommands.add_parser(
        "prepare-media",
        help="extract normalized audio and optionally run external vocal isolation",
    )
    media.add_argument("--input", required=True)
    media.add_argument("--output-dir", required=True)
    media.add_argument(
        "--vocal-isolation-command",
        help="shell command template; use {input}, {output}, and {output_dir}",
    )
    media.set_defaults(func=prepare_media)

    whisperx = subcommands.add_parser("run-whisperx", help="run WhisperX on prepared audio")
    whisperx.add_argument("--input", required=True)
    whisperx.add_argument("--output-dir", required=True)
    whisperx.add_argument("--output-json")
    whisperx.add_argument("--model", default="large-v3")
    whisperx.add_argument("--language", default="en")
    whisperx.add_argument("--device", default="cpu")
    whisperx.add_argument("--compute-type", default="float32")
    whisperx.add_argument("--batch-size", type=int, default=16)
    whisperx.add_argument("--align-model")
    whisperx.add_argument("--diarize", action="store_true")
    whisperx.add_argument("--hf-token")
    whisperx.add_argument("--whisperx-bin")
    whisperx.add_argument(
        "--whisperx-command",
        help="shell command template; use {input}, {output_dir}, {model}, {language}, {device}, {compute_type}, {batch_size}",
    )
    whisperx.add_argument("--dry-run", action="store_true")
    whisperx.set_defaults(func=run_whisperx)

    convert = subcommands.add_parser("from-whisperx-json", help="convert WhisperX JSON to LLTimeline v1")
    convert.add_argument("--input", required=True)
    convert.add_argument("--output", required=True)
    convert.add_argument("--media-fingerprint", required=True)
    convert.add_argument("--media-title", required=True)
    convert.add_argument("--media-path")
    convert.add_argument("--media-id")
    convert.add_argument("--track-id")
    convert.add_argument("--timeline-id")
    convert.add_argument("--duration-ms", type=int)
    convert.add_argument("--preprocessing-artifacts")
    convert.add_argument("--language", default="en")
    convert.add_argument("--algorithm-id", default="whisperx")
    convert.add_argument("--algorithm-version", default="large-v3-align")
    convert.add_argument("--config-hash", default="default")
    convert.add_argument("--status", choices=["candidate", "active", "archived"], default="active")
    convert.set_defaults(func=convert_whisperx)

    report = subcommands.add_parser("report", help="create a production report for an LLTimeline file")
    report.add_argument("--input", required=True)
    report.add_argument("--output", required=True)
    report.set_defaults(func=report_lltimeline)

    mfa = subcommands.add_parser(
        "apply-mfa-alignment",
        help="append an MFA post-aligned WordTimeline to an existing LLTimeline file",
    )
    mfa.add_argument("--input", required=True, help="LLTimeline JSON file to update in place")
    mfa.add_argument("--audio", required=True, help="16k mono audio used by the LLTimeline")
    mfa.add_argument("--output-dir", required=True)
    mfa.add_argument("--dry-run", action="store_true")
    add_mfa_options(mfa)
    mfa.set_defaults(func=apply_mfa_alignment)

    mms_fa = subcommands.add_parser(
        "apply-mms-fa-alignment",
        help="append an MMS_FA post-aligned WordTimeline to an existing LLTimeline file",
    )
    mms_fa.add_argument("--input", required=True, help="LLTimeline JSON file to update in place")
    mms_fa.add_argument("--audio", required=True, help="16k mono audio used by the LLTimeline")
    mms_fa.add_argument("--output-dir", required=True)
    mms_fa.add_argument("--post-config-hash", default="default")
    mms_fa.add_argument("--post-status", choices=["candidate", "active", "archived"], default="active")
    mms_fa.add_argument("--dry-run", action="store_true")
    add_mms_fa_options(mms_fa)
    mms_fa.set_defaults(func=apply_mms_fa_alignment)

    produce = subcommands.add_parser(
        "produce-whisperx",
        help="prepare media, run WhisperX, and emit LLTimeline v1",
    )
    produce.add_argument("--input", required=True)
    produce.add_argument("--output-dir", required=True)
    produce.add_argument("--output")
    produce.add_argument("--media-fingerprint", required=True)
    produce.add_argument("--media-title", required=True)
    produce.add_argument("--media-path")
    produce.add_argument("--media-id")
    produce.add_argument("--track-id")
    produce.add_argument("--timeline-id")
    produce.add_argument("--duration-ms", type=int)
    produce.add_argument("--language", default="en")
    produce.add_argument("--algorithm-id", default="whisperx")
    produce.add_argument("--algorithm-version", default="large-v3-align")
    produce.add_argument("--config-hash", default="default")
    produce.add_argument("--status", choices=["candidate", "active", "archived"], default="active")
    produce.add_argument("--vocal-isolation-command")
    produce.add_argument("--output-json")
    produce.add_argument("--model", default="large-v3")
    produce.add_argument("--device", default="cpu")
    produce.add_argument("--compute-type", default="float32")
    produce.add_argument("--batch-size", type=int, default=16)
    produce.add_argument("--align-model")
    produce.add_argument("--diarize", action="store_true")
    produce.add_argument("--hf-token")
    produce.add_argument("--whisperx-bin")
    produce.add_argument("--whisperx-command")
    produce.add_argument(
        "--post-aligner",
        choices=["none", "auto", "mfa", "mms-fa"],
        default="none",
        help="optional post-ASR aligner; auto/mfa degrade from MFA to MMS_FA, then keep WhisperX",
    )
    produce.add_argument(
        "--no-post-aligner-fallback",
        dest="post_aligner_fallback",
        action="store_false",
        help="fail instead of trying the next post-aligner when the selected aligner fails",
    )
    produce.set_defaults(post_aligner_fallback=True)
    add_mfa_options(produce)
    add_mms_fa_options(produce)
    produce.add_argument("--dry-run", action="store_true")
    produce.set_defaults(func=produce_whisperx)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
