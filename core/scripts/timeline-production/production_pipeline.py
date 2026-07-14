#!/usr/bin/env python3
"""Local heavy timeline production helpers.

This script intentionally lives outside the app bundle path. It is a production
sidecar utility for local research and content production, and its stable output
is an LLTimeline JSON resource.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import importlib.util
import json
import math
import os
import shlex
import shutil
import subprocess
import sys
import time
import wave
from pathlib import Path
from typing import Any

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lltimeline_common import align_asr_words_to_tokens, tokenize, word_key, word_token_indexes

from aligners import all_aligners, available_aligners, get_aligner

SCHEMA = "llplayer.timeline.v1"
REPO_ROOT = Path(__file__).resolve().parents[2]
RHYTHM_WORD_ACOUSTIC_CUES_KIND = "rhythm_word_acoustic_cues"
RHYTHM_WORD_ACOUSTIC_PROVIDER_ID = "rms-word-energy-prominence"
RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION = "v1"
ENERGY_PROMINENCE_DB_FOR_MAX = 6.0


from production_pipeline_common import active_word_timeline, file_sha256, load_json, now_ms, stable_id
from production_pipeline_acoustics import append_rhythm_word_acoustic_cues, append_rhythm_word_acoustic_cues_safe
from production_pipeline_alignment import add_aligned_word_timeline, build_mfa_alignment_request, record_post_alignment_failure
from production_pipeline_report import build_production_report, write_production_report

from production_pipeline_conversion import convert_whisperx, report_lltimeline
from production_pipeline_audio import prepare_audio, prepare_media
from production_pipeline_orchestration import (
    apply_mfa_alignment,
    apply_mms_fa_alignment,
    default_mlx_whisper_python,
    default_whisperx_bin,
    produce_whisperx,
    run_whisperx,
)

def add_mfa_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--mfa-align-cli", help="path to scripts/forced-align/mfa-align-cli.py")
    parser.add_argument("--mfa-bin", help="path to the MFA executable")
    parser.add_argument("--mfa-root-dir", help="MFA_ROOT_DIR containing downloaded/extracted models")
    parser.add_argument("--mfa-dictionary", default="english_us_arpa")
    parser.add_argument("--mfa-acoustic-model", default="english_us_arpa")
    parser.add_argument("--mfa-strategy", choices=["align", "align-one"], default="align",
                        help="MFA alignment strategy: 'align' loads the acoustic model once and "
                        "aligns all segments in batch (fast); 'align-one' spawns a separate MFA "
                        "process per segment (slower due to per-segment model loading, but kept "
                        "as a fallback if the batch path encounters export errors)")
    parser.add_argument("--mfa-jobs", type=int, default=4)
    parser.add_argument("--mfa-quiet", action="store_true")
    parser.add_argument("--post-algorithm-id", default="whisperx-transcript-mfa")
    parser.add_argument("--post-algorithm-version", default="large-v3-mfa-arpa-align")
    parser.add_argument("--post-config-hash", default="default")
    parser.add_argument("--post-status", choices=["candidate", "active", "archived"], default="active")


def add_mms_fa_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--mms-fa-align-cli", help="path to scripts/forced-align/align-cli.py")
    parser.add_argument("--mms-fa-python", help="path to the MMS_FA research venv Python")


def list_aligners(_: argparse.Namespace) -> int:
    print(json.dumps(all_aligners(), indent=2, sort_keys=True))
    return 0


def doctor(_: argparse.Namespace) -> int:
    checks: dict[str, Any] = {
        "ffmpeg": shutil.which("ffmpeg") is not None,
        "python": True,
        "whisperx": importlib.util.find_spec("whisperx") is not None,
        "torch": importlib.util.find_spec("torch") is not None,
        "torchaudio": importlib.util.find_spec("torchaudio") is not None,
        "demucs": importlib.util.find_spec("demucs") is not None,
        "uvr_env": "UVR_MODELS_DIR" in os.environ,
        "aligners": all_aligners(),
    }
    print(json.dumps(checks, sort_keys=True))
    return 0 if checks["ffmpeg"] else 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    check = subcommands.add_parser("doctor", help="check local production dependencies")
    check.set_defaults(func=doctor)

    aligners_cmd = subcommands.add_parser("list-aligners", help="list registered aligner plugins")
    aligners_cmd.set_defaults(func=list_aligners)

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
    mfa.add_argument("--language", default="en")
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
    mms_fa.add_argument("--language", default="en")
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
    produce.add_argument("--asr", choices=["whisperx", "mlx-whisper"], default="whisperx",
                         help="ASR engine: whisperx (CPU/CUDA) or mlx-whisper (Apple GPU)")
    produce.add_argument("--mlx-whisper-python", help="path to the mlx-whisper venv Python")
    produce.add_argument("--mlx-whisper-model", default="mlx-community/whisper-large-v3-mlx")
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
