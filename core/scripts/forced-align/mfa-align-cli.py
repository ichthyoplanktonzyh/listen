#!/usr/bin/env python3
"""Run Montreal Forced Aligner for an alignment-request.json file.

The script bridges LLPlayerNext's existing forced-alignment request contract to
MFA's corpus workflow:

1. split each requested segment into a short wav file,
2. write a matching transcript `.lab`,
3. run `mfa align`,
4. parse MFA TextGrid word tiers back into `{ "timings": [...] }`.

It is research-only and expects MFA to be installed separately.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from lltimeline_common import normalize_word


TEXTGRID_ITEM_RE = re.compile(r"item \[\d+\]:")
TEXTGRID_NAME_RE = re.compile(r'name = "([^"]*)"')
TEXTGRID_INTERVAL_RE = re.compile(
    r"intervals \[\d+\]:\s+"
    r"xmin = ([0-9.]+)\s+"
    r"xmax = ([0-9.]+)\s+"
    r'text = "(.*?)"',
    re.S,
)
SILENCE_LABELS = {"", "<eps>", "sil", "sp", "spn", "<sil>", "{sl}"}
ACOUSTIC_MODEL_REQUIRED_FILES = {
    "final.alimdl",
    "final.mdl",
    "graphemes.txt",
    "lda.mat",
    "meta.json",
    "phones.txt",
    "phone_lm.fst",
    "phone_pdf.counts",
    "rules.yaml",
    "tree",
}


def seconds(value_ms: int) -> str:
    return f"{value_ms / 1000:.6f}"


def require_ffmpeg() -> str:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg not found")
    return ffmpeg


def segment_basename(segment_index: int) -> str:
    return f"seg_{segment_index:06d}"


def default_mfa_root_dir() -> Path:
    if "LLPLAYERNEXT_MFA_ROOT_DIR" in os.environ:
        return Path(os.environ["LLPLAYERNEXT_MFA_ROOT_DIR"])
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_MFA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mfa"),
        )
    )
    return research_root / "root"


def acoustic_model_is_complete(path: Path) -> bool:
    return path.is_dir() and all((path / file_name).exists() for file_name in ACOUSTIC_MODEL_REQUIRED_FILES)


def resolve_acoustic_model_path(model: str, mfa_root_dir: Path) -> str:
    model_path = Path(model)
    if model_path.exists():
        return str(model_path)

    extracted_dir = mfa_root_dir / "extracted_models" / "acoustic" / f"{model}_acoustic"
    if acoustic_model_is_complete(extracted_dir):
        return str(extracted_dir)

    zip_path = mfa_root_dir / "pretrained_models" / "acoustic" / f"{model}.zip"
    if not zip_path.exists():
        return model

    temp_dir = extracted_dir.with_name(f"{extracted_dir.name}.tmp")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(temp_dir)
    source_dir = temp_dir / model
    if not source_dir.exists():
        source_dir = temp_dir
    if extracted_dir.exists():
        shutil.rmtree(extracted_dir)
    extracted_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source_dir), str(extracted_dir))
    shutil.rmtree(temp_dir, ignore_errors=True)
    if not acoustic_model_is_complete(extracted_dir):
        raise SystemExit(f"incomplete MFA acoustic model extraction: {extracted_dir}")
    return str(extracted_dir)


def resolve_dictionary_path(dictionary: str, mfa_root_dir: Path) -> str:
    dictionary_path = Path(dictionary)
    if dictionary_path.exists():
        return str(dictionary_path)
    saved_dictionary = mfa_root_dir / "pretrained_models" / "dictionary" / f"{dictionary}.dict"
    if saved_dictionary.exists():
        return str(saved_dictionary)
    return dictionary


def prepare_corpus(request: dict[str, Any], corpus_dir: Path) -> list[dict[str, Any]]:
    ffmpeg = require_ffmpeg()
    audio_path = Path(str(request["audio_path"]))
    if not audio_path.exists():
        raise SystemExit(f"audio file not found: {audio_path}")
    corpus_dir.mkdir(parents=True, exist_ok=True)

    prepared: list[dict[str, Any]] = []
    for segment in request.get("segments", []):
        segment_index = int(segment["index"])
        start_ms = int(segment["start_ms"])
        end_ms = int(segment["end_ms"])
        words = [str(word).strip() for word in segment.get("words", []) if str(word).strip()]
        if end_ms <= start_ms or not words:
            continue
        basename = segment_basename(segment_index)
        wav_path = corpus_dir / f"{basename}.wav"
        lab_path = corpus_dir / f"{basename}.lab"
        subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-ss",
                seconds(start_ms),
                "-i",
                str(audio_path),
                "-t",
                seconds(end_ms - start_ms),
                "-ac",
                "1",
                "-ar",
                "16000",
                "-sample_fmt",
                "s16",
                str(wav_path),
            ],
            check=True,
        )
        lab_path.write_text(" ".join(words) + "\n", encoding="utf-8")
        prepared.append(
            {
                "segment_index": segment_index,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "words": words,
                "basename": basename,
            }
        )
    return prepared


def run_mfa(args: argparse.Namespace, corpus_dir: Path, output_dir: Path, temp_dir: Path) -> None:
    mfa_bin = args.mfa_bin or shutil.which("mfa")
    if not mfa_bin:
        raise SystemExit("mfa not found; run scripts/forced-align/setup-mfa-research.sh first")
    mfa_root_dir = Path(args.mfa_root_dir)
    mfa_root_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    temp_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["MFA_ROOT_DIR"] = str(mfa_root_dir)
    mfa_bin_dir = str(Path(mfa_bin).resolve().parent)
    env["PATH"] = mfa_bin_dir + os.pathsep + env.get("PATH", "")
    command = [
        mfa_bin,
        "align",
        str(corpus_dir),
        args.dictionary,
        args.acoustic_model,
        str(output_dir),
        "--clean",
        "--single_speaker",
        "--output_format",
        "long_textgrid",
        "--temporary_directory",
        str(temp_dir),
        "-j",
        str(args.jobs),
    ]
    if args.quiet:
        command.append("--quiet")
    subprocess.run(command, check=True, env=env)


def run_mfa_align_one(
    args: argparse.Namespace, prepared: list[dict[str, Any]], corpus_dir: Path, output_dir: Path, temp_dir: Path
) -> None:
    mfa_bin = args.mfa_bin or shutil.which("mfa")
    if not mfa_bin:
        raise SystemExit("mfa not found; run scripts/forced-align/setup-mfa-research.sh first")
    mfa_root_dir = Path(args.mfa_root_dir)
    mfa_root_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    temp_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["MFA_ROOT_DIR"] = str(mfa_root_dir)
    mfa_bin_dir = str(Path(mfa_bin).resolve().parent)
    env["PATH"] = mfa_bin_dir + os.pathsep + env.get("PATH", "")
    dictionary = resolve_dictionary_path(args.dictionary, mfa_root_dir)
    acoustic_model = resolve_acoustic_model_path(args.acoustic_model, mfa_root_dir)

    def align_segment(segment: dict[str, Any]) -> None:
        basename = segment["basename"]
        segment_temp_dir = temp_dir / basename
        segment_root_dir = temp_dir / "mfa-roots" / basename
        segment_root_dir.mkdir(parents=True, exist_ok=True)
        segment_env = env.copy()
        segment_env["MFA_ROOT_DIR"] = str(segment_root_dir)
        command = [
            mfa_bin,
            "align_one",
            str(corpus_dir / f"{basename}.wav"),
            str(corpus_dir / f"{basename}.lab"),
            dictionary,
            acoustic_model,
            str(output_dir / f"{basename}.TextGrid"),
            "--clean",
            "--single_speaker",
            "--output_format",
            "long_textgrid",
            "--temporary_directory",
            str(segment_temp_dir),
            "-j",
            "1",
        ]
        if args.quiet:
            command.append("--quiet")
        subprocess.run(command, check=True, env=segment_env)

    max_workers = max(1, int(args.jobs))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(align_segment, segment) for segment in prepared]
        for future in concurrent.futures.as_completed(futures):
            future.result()


def parse_textgrid(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    items = TEXTGRID_ITEM_RE.split(text)
    best_intervals: list[dict[str, Any]] = []
    for item in items:
        name_match = TEXTGRID_NAME_RE.search(item)
        if not name_match:
            continue
        tier_name = name_match.group(1).casefold()
        intervals = [
            {
                "start": float(match.group(1)),
                "end": float(match.group(2)),
                "text": match.group(3).replace('""', '"').strip(),
            }
            for match in TEXTGRID_INTERVAL_RE.finditer(item)
        ]
        if not intervals:
            continue
        if tier_name in {"words", "word", "orthography"}:
            return intervals
        if not best_intervals:
            best_intervals = intervals
    return best_intervals


def interval_words(intervals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        interval
        for interval in intervals
        if normalize_word(str(interval.get("text", ""))) not in SILENCE_LABELS
    ]


def timings_from_textgrids(prepared: list[dict[str, Any]], output_dir: Path) -> dict[str, Any]:
    timings: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    textgrid_paths = {path.stem: path for path in output_dir.rglob("*.TextGrid")}
    textgrid_paths.update({path.stem: path for path in output_dir.rglob("*.textgrid")})

    for segment in prepared:
        path = textgrid_paths.get(segment["basename"])
        if not path:
            for word_index, _word in enumerate(segment["words"]):
                timings.append(
                    {
                        "segment_index": segment["segment_index"],
                        "word_index": word_index,
                        "skipped": True,
                    }
                )
            skipped.append({"segment_index": segment["segment_index"], "reason": "textgrid_missing"})
            continue

        aligned_words = interval_words(parse_textgrid(path))
        source_words = segment["words"]
        if len(aligned_words) != len(source_words):
            skipped.append(
                {
                    "segment_index": segment["segment_index"],
                    "reason": "word_count_mismatch",
                    "expected": len(source_words),
                    "actual": len(aligned_words),
                    "textgrid": str(path),
                }
            )
        for word_index, source_word in enumerate(source_words):
            if word_index >= len(aligned_words):
                timings.append(
                    {
                        "segment_index": segment["segment_index"],
                        "word_index": word_index,
                        "skipped": True,
                    }
                )
                continue
            aligned = aligned_words[word_index]
            start_ms = segment["start_ms"] + int(round(float(aligned["start"]) * 1000))
            end_ms = segment["start_ms"] + int(round(float(aligned["end"]) * 1000))
            start_ms = max(segment["start_ms"], min(start_ms, segment["end_ms"]))
            end_ms = max(start_ms + 1, min(end_ms, segment["end_ms"]))
            timings.append(
                {
                    "segment_index": segment["segment_index"],
                    "word_index": word_index,
                    "text": source_word,
                    "aligned_text": aligned["text"],
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                    "score": None,
                }
            )
    return {
        "provider_id": "montreal-forced-aligner",
        "provider_version": "mfa-research-v1",
        "timings": sorted(timings, key=lambda row: (row["segment_index"], row["word_index"])),
        "diagnostics": {
            "skipped": skipped,
        },
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--input", required=True, help="alignment-request.json path")
    root.add_argument("--output", help="write aligned JSON here; stdout is used when omitted")
    root.add_argument("--work-dir", required=True, help="scratch directory for MFA corpus/output")
    root.add_argument("--mfa-bin", help="path to mfa executable")
    root.add_argument(
        "--mfa-root-dir",
        default=str(default_mfa_root_dir()),
        help="MFA_ROOT_DIR for models and temporary defaults",
    )
    root.add_argument("--dictionary", default="english_mfa")
    root.add_argument("--acoustic-model", default="english_mfa")
    root.add_argument("--jobs", type=int, default=3)
    root.add_argument(
        "--strategy",
        choices=["align", "align-one"],
        default="align",
        help="MFA execution strategy; align-one bypasses MFA's batch database export path",
    )
    root.add_argument("--quiet", action="store_true")
    root.add_argument("--skip-run", action="store_true", help="only parse existing MFA output")
    return root


def main() -> int:
    args = parser().parse_args()
    request = json.loads(Path(args.input).read_text(encoding="utf-8"))
    work_dir = Path(args.work_dir)
    corpus_dir = work_dir / "corpus"
    output_dir = work_dir / "mfa-output"
    temp_dir = work_dir / "mfa-temp"
    prepared = prepare_corpus(request, corpus_dir)
    if not prepared:
        raise SystemExit("no valid segments to align")
    if not args.skip_run and args.strategy == "align":
        run_mfa(args, corpus_dir, output_dir, temp_dir)
    elif not args.skip_run:
        run_mfa_align_one(args, prepared, corpus_dir, output_dir, temp_dir)
    result = timings_from_textgrids(prepared, output_dir)
    payload = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(payload, encoding="utf-8")
        print(json.dumps({"output": str(output), "timings": len(result["timings"])}, sort_keys=True))
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
