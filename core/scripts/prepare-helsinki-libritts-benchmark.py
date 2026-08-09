#!/usr/bin/env python3
"""Prepare local-only LLTimeline baselines for Helsinki/LibriTTS scoring.

The generated files live under an ignored output directory and are intended to
be consumed in two steps:

1. Refresh the generated baseline LLTimelines through
   `scripts/run-sound-line-real-media-case.py` to add `sound_analysis.rhythm_frame`.
2. Score the refreshed artifacts with `scripts/evaluate-helsinki-prosody.py`.

No LibriTTS audio or full Helsinki corpus data is written to the repository.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import sys
import tarfile
import time
import wave
from pathlib import Path
from typing import Any


EVALUATOR_PATH = Path(__file__).with_name("evaluate-helsinki-prosody.py")
SPEC = importlib.util.spec_from_file_location("evaluate_helsinki_prosody", EVALUATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
helsinki = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helsinki)

SPLIT_DIRS = {
    "dev": ["dev-clean", "dev-other", "dev"],
    "test": ["test-clean", "test-other", "test"],
    "train_100": ["train-clean-100", "train_100"],
    "train_360": ["train-clean-360", "train_360"],
}


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def stable_id(prefix: str, raw: str) -> str:
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]
    cleaned = re.sub(r"[^a-z0-9-]+", "-", raw.lower()).strip("-")
    if not cleaned or len(cleaned) > 48:
        cleaned = digest
    return f"{prefix}-{cleaned}-{digest}"


def normalize_token(value: str) -> str:
    return re.sub(r"[^a-z0-9']+", "", value.lower()).strip("'")


def render_text(words: list[dict[str, Any]]) -> str:
    tokens = [str(word["word"]) for word in words]
    text = ""
    no_space_before = set(".,?!;:%)]}")
    no_space_after = set("([{")
    for token in tokens:
        if not text:
            text = token
        elif token in no_space_before or text[-1] in no_space_after:
            text += token
        else:
            text += " " + token
    return text


def tokenize(text: str) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    for match in re.finditer(r"[A-Za-z0-9']+|\s+|[^\w\s]", text):
        raw = match.group(0)
        if raw.isspace():
            kind = "whitespace"
            normalized = None
        elif re.match(r"[A-Za-z0-9']", raw):
            kind = "word"
            normalized = normalize_token(raw)
        else:
            kind = "punctuation"
            normalized = None
        values.append(
            {
                "index": len(values),
                "kind": kind,
                "text": raw,
                "normalized": normalized,
                "start_char": match.start(),
                "end_char": match.end(),
            }
        )
    return values


def wav_duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as wav:
        frames = wav.getnframes()
        rate = wav.getframerate()
    return int(round(frames * 1000 / rate)) if rate else 0


def candidate_audio_paths(libritts_dir: Path, split: str, source_file: str) -> list[Path]:
    stem = Path(source_file).stem
    parts = stem.split("_")
    speaker = parts[0] if len(parts) >= 2 else None
    chapter = parts[1] if len(parts) >= 2 else None
    roots = [libritts_dir]
    roots.extend(libritts_dir / dirname for dirname in SPLIT_DIRS.get(split, [split]))

    candidates: list[Path] = []
    for root in roots:
        candidates.append(root / f"{stem}.wav")
        if speaker and chapter:
            candidates.append(root / speaker / chapter / f"{stem}.wav")
    return candidates


def find_audio(libritts_dir: Path, split: str, source_file: str) -> Path | None:
    for candidate in candidate_audio_paths(libritts_dir, split, source_file):
        if candidate.is_file():
            return candidate
    return None


def archive_wav_members(path: Path) -> dict[str, tarfile.TarInfo]:
    members: dict[str, tarfile.TarInfo] = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.endswith(".wav"):
                continue
            stem = Path(member.name).stem
            members[stem] = member
    return members


def extract_archive_audio(
    archive_path: Path,
    member: tarfile.TarInfo,
    output_dir: Path,
) -> Path:
    relative_name = member.name.lstrip("./")
    if relative_name.startswith("/") or ".." in Path(relative_name).parts:
        raise ValueError(f"unsafe archive member path: {member.name}")
    output_path = output_dir / "audio" / relative_name
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.is_file() and output_path.stat().st_size == member.size:
        return output_path
    with tarfile.open(archive_path, "r:gz") as archive:
        source = archive.extractfile(member)
        if source is None:
            raise ValueError(f"cannot read archive member: {member.name}")
        with output_path.open("wb") as target:
            shutil.copyfileobj(source, target)
    return output_path


def baseline_document(
    label_sentence: dict[str, Any],
    audio_path: Path,
    duration_ms: int,
    output_path: Path,
) -> dict[str, Any]:
    source_stem = label_sentence["source_stem"]
    media_id = stable_id("media", source_stem)
    track_id = stable_id("track", source_stem)
    sentence_id = stable_id("sentence", source_stem)
    text = render_text(label_sentence["words"])
    return {
        "schema": "llplayer.timeline.v1",
        "metadata": {
            "created_at_ms": int(time.time() * 1000),
            "generator": {
                "id": "helsinki-libritts-benchmark-prep",
                "version": "v1",
                "mode": "local_benchmark",
            },
            "media": {
                "id": media_id,
                "fingerprint": source_stem,
                "path": str(audio_path),
                "title": f"LibriTTS {source_stem}",
                "duration_ms": duration_ms,
            },
            "language": "en",
            "human_reviewed": False,
            "extra": {
                "track_id": track_id,
                "track_source": "helsinki-libritts-benchmark",
                "helsinki_source_file": label_sentence["source_file"],
                "generated_artifact_path": str(output_path),
            },
        },
        "segments": [
            {
                "id": sentence_id,
                "index": 0,
                "start_ms": 0,
                "end_ms": duration_ms,
                "text": text,
                "display_text": text,
                "tokens": tokenize(text),
            }
        ],
        "word_timelines": [],
        "active_word_timeline_id": None,
        "phone_timelines": [],
        "active_phone_timeline_id": None,
        "artifacts": [
            {
                "kind": "helsinki_prosody_source",
                "provider_id": "helsinki-prosody",
                "provider_version": "2019",
                "payload": {
                    "source_file": label_sentence["source_file"],
                    "source_stem": source_stem,
                },
            }
        ],
    }


def labels_path(args: argparse.Namespace) -> Path:
    if args.labels:
        return Path(args.labels).expanduser()
    return Path(args.prosody_dir).expanduser() / "data" / f"{args.split}.txt"


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    labels = helsinki.parse_helsinki_labels(labels_path(args), limit=args.limit)
    libritts_dir = Path(args.libritts_dir).expanduser() if args.libritts_dir else None
    libritts_archive = Path(args.libritts_archive).expanduser() if args.libritts_archive else None
    if libritts_dir is None and libritts_archive is None:
        raise ValueError("either --libritts-dir or --libritts-archive is required")
    archive_members = archive_wav_members(libritts_archive) if libritts_archive else {}
    output_dir = Path(args.output_dir).expanduser()
    timelines_dir = output_dir / "timelines"
    timelines_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "manifest.jsonl"

    manifest_rows: list[dict[str, Any]] = []
    missing_audio: list[dict[str, str]] = []
    for label_sentence in labels:
        audio_path = find_audio(libritts_dir, args.split, label_sentence["source_file"]) if libritts_dir else None
        if audio_path is None and libritts_archive:
            member = archive_members.get(label_sentence["source_stem"])
            if member is not None:
                audio_path = extract_archive_audio(libritts_archive, member, output_dir)
        if audio_path is None:
            missing_audio.append(
                {
                    "source_file": label_sentence["source_file"],
                    "source_stem": label_sentence["source_stem"],
                }
            )
            continue
        source_stem = label_sentence["source_stem"]
        timeline_path = timelines_dir / f"{source_stem}.lltimeline.json"
        duration_ms = wav_duration_ms(audio_path)
        document = baseline_document(label_sentence, audio_path, duration_ms, timeline_path)
        timeline_path.write_text(compact_json(document), encoding="utf-8")
        sentence_id = document["segments"][0]["id"]
        case_id = f"hpros-{source_stem}"
        manifest_rows.append(
            {
                "case_id": case_id,
                "title": f"Helsinki Prosody / LibriTTS {source_stem}",
                "dataset": "helsinki_prosody_libritts",
                "benchmark_role": "weak_prosody_regression",
                "layer": "supplemental",
                "language": "en-US",
                "source_file": label_sentence["source_file"],
                "source_stem": source_stem,
                "sentence_id": sentence_id,
                "license": {
                    "redistributable": False,
                    "status": "local_only",
                    "notes": "Generated from local LibriTTS audio and Helsinki Prosody labels; do not commit generated timelines or audio.",
                },
                "source": {
                    "kind": "local_file",
                    "locator": str(audio_path.parent),
                    "external_url": "https://github.com/Helsinki-NLP/prosody",
                },
                "media": {
                    "local_path": str(audio_path),
                    "sha256": None,
                    "duration_ms": duration_ms,
                },
                "subtitle": None,
                "lltimeline": {
                    "path": str(timeline_path),
                    "local_path": str(timeline_path),
                    "local_only": True,
                    "sha256": None,
                },
                "targets": {
                    "phenomena": ["prominence", "word_boundary"],
                    "expected_connected_speech_families": [],
                    "min_manual_observations": 0,
                },
                "qa_notes": "",
            }
        )

    manifest_path.write_text(
        "".join(compact_json(row) + "\n" for row in manifest_rows),
        encoding="utf-8",
    )
    return {
        "labels_path": str(labels_path(args)),
        "libritts_dir": str(libritts_dir) if libritts_dir else None,
        "libritts_archive": str(libritts_archive) if libritts_archive else None,
        "output_dir": str(output_dir),
        "manifest_path": str(manifest_path),
        "selected_label_count": len(labels),
        "prepared_count": len(manifest_rows),
        "missing_audio_count": len(missing_audio),
        "missing_audio": missing_audio[:20],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prosody-dir", default="~/prosody")
    parser.add_argument("--labels")
    parser.add_argument("--libritts-dir")
    parser.add_argument("--libritts-archive", help="Path to a LibriTTS split .tar.gz; selected wavs are extracted to output-dir/audio")
    parser.add_argument("--split", default="dev", choices=["dev", "test", "train_100", "train_360"])
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--output-dir", default=".tmp/helsinki-libritts-rhythm")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        result = prepare(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:  # pragma: no cover - CLI guardrail
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
