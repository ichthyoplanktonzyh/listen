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
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


SCHEMA = "llplayer.timeline.v1"
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)?")


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


def normalize_word(value: str) -> str:
    return value.strip().strip(".,!?;:\"“”‘’()[]{}").replace("’", "'").lower()


def tokenize(text: str) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    index = 0
    cursor = 0
    for match in WORD_RE.finditer(text):
        if match.start() > cursor:
            index = append_non_word_tokens(tokens, text[cursor:match.start()], cursor, index)
        value = match.group(0)
        tokens.append(
            {
                "index": index,
                "kind": "word",
                "text": value,
                "normalized": normalize_word(value),
                "start_char": match.start(),
                "end_char": match.end(),
            }
        )
        index += 1
        cursor = match.end()
    if cursor < len(text):
        append_non_word_tokens(tokens, text[cursor:], cursor, index)
    return tokens


def append_non_word_tokens(
    tokens: list[dict[str, Any]],
    text: str,
    absolute_start: int,
    index: int,
) -> int:
    cursor = 0
    while cursor < len(text):
        start = cursor
        is_space = text[cursor].isspace()
        while cursor < len(text) and text[cursor].isspace() == is_space:
            cursor += 1
        value = text[start:cursor]
        kind = "whitespace" if is_space else "punctuation"
        tokens.append(
            {
                "index": index,
                "kind": kind,
                "text": value,
                "normalized": None,
                "start_char": absolute_start + start,
                "end_char": absolute_start + cursor,
            }
        )
        index += 1
    return index


def word_token_indexes(tokens: list[dict[str, Any]]) -> list[int]:
    return [token["index"] for token in tokens if token["kind"] == "word"]


def convert_whisperx(args: argparse.Namespace) -> int:
    source = json.loads(Path(args.input).read_text(encoding="utf-8"))
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
        preprocessing = json.loads(Path(args.preprocessing_artifacts).read_text(encoding="utf-8"))
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
    executable = args.whisperx_bin or shutil.which("whisperx")
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
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    command = resolve_whisperx_command(args)
    printable = command if isinstance(command, str) else " ".join(shlex.quote(part) for part in command)
    if args.dry_run:
        print(json.dumps({"command": printable, "output_dir": str(output_dir)}, sort_keys=True))
        return 0
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
    print(json.dumps({"whisperx_json": str(output_json), "report_path": str(report_path)}, sort_keys=True))
    return 0


def doctor(_: argparse.Namespace) -> int:
    checks = {
        "ffmpeg": shutil.which("ffmpeg") is not None,
        "python": True,
        "whisperx": importlib.util.find_spec("whisperx") is not None,
        "torch": importlib.util.find_spec("torch") is not None,
        "demucs": importlib.util.find_spec("demucs") is not None,
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
    return root


def main() -> int:
    args = parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
