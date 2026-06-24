#!/usr/bin/env python3
"""MLX-Whisper transcription script — outputs WhisperX-compatible JSON.

Usage:
    python mlx-whisper-transcribe.py \
        --input audio.wav \
        --output-dir ./out \
        --model mlx-community/whisper-large-v3-mlx \
        --language zh

The output JSON has the same schema as WhisperX: segments with word-level
timestamps, suitable for convert_whisperx() in production_pipeline.py.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


def transcribe(args: argparse.Namespace) -> dict:
    import mlx_whisper

    started = time.time()
    result = mlx_whisper.transcribe(
        str(args.input),
        path_or_hf_repo=args.model,
        language=args.language if args.language != "auto" else None,
        word_timestamps=True,
        verbose=args.verbose,
    )
    elapsed = time.time() - started

    segments = []
    word_segments = []

    for seg in result.get("segments", []):
        words = []
        for w in seg.get("words", []):
            entry = {
                "word": w.get("word", "").strip(),
                "start": w.get("start"),
                "end": w.get("end"),
                "score": w.get("probability", w.get("score", 0.0)),
            }
            words.append(entry)
            word_segments.append(entry)

        segments.append({
            "start": seg.get("start"),
            "end": seg.get("end"),
            "text": seg.get("text", "").strip(),
            "words": words,
            "avg_logprob": seg.get("avg_logprob", 0.0),
        })

    output = {
        "segments": segments,
        "word_segments": word_segments,
        "language": result.get("language", args.language),
    }

    if args.verbose:
        print(
            f"mlx-whisper: {len(segments)} segments, "
            f"{len(word_segments)} words, {elapsed:.1f}s",
            file=sys.stderr,
        )

    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="path to audio file")
    parser.add_argument("--output-dir", required=True, help="output directory")
    parser.add_argument("--output-json", help="explicit output JSON path")
    parser.add_argument(
        "--model",
        default="mlx-community/whisper-large-v3-mlx",
        help="HuggingFace repo or local path for MLX whisper model",
    )
    parser.add_argument("--language", default="en")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    result = transcribe(args)

    output_path = Path(args.output_json) if args.output_json else (
        output_dir / (Path(args.input).stem + ".json")
    )
    output_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"output": str(output_path)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
