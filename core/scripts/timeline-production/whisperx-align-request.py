#!/usr/bin/env python3
"""Run WhisperX alignment against an existing alignment-request.json file.

This helper is for benchmark evaluation, where the transcript is already known
from a gold corpus. It deliberately skips Whisper ASR and only asks WhisperX's
alignment model to place those words on the audio timeline.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def ms(value: float | int) -> int:
    return int(round(float(value) * 1000))


def segment_text(segment: dict[str, Any]) -> str:
    words = [str(word).strip() for word in segment.get("words", []) if str(word).strip()]
    return " ".join(words) or str(segment.get("text", "")).strip()


def run_alignment(args: argparse.Namespace) -> dict[str, Any]:
    try:
        import whisperx
    except ImportError as error:
        raise SystemExit("whisperx is not installed in this Python environment") from error

    request = json.loads(Path(args.input).read_text(encoding="utf-8"))
    audio_path = str(request["audio_path"])
    source_segments = request.get("segments")
    if not isinstance(source_segments, list) or not source_segments:
        raise SystemExit("alignment request must contain a non-empty segments array")

    print(
        f"loading WhisperX align model language={args.language} device={args.device}",
        file=sys.stderr,
    )
    model, metadata = whisperx.load_align_model(language_code=args.language, device=args.device)

    timings: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for segment in source_segments:
        segment_index = int(segment["index"])
        words = [str(word).strip() for word in segment.get("words", []) if str(word).strip()]
        text = segment_text(segment)
        if not words or not text:
            skipped.append({"segment_index": segment_index, "reason": "empty_words"})
            continue

        transcript = [
            {
                "start": int(segment["start_ms"]) / 1000,
                "end": int(segment["end_ms"]) / 1000,
                "text": text,
            }
        ]
        try:
            aligned = whisperx.align(
                transcript,
                model,
                metadata,
                audio_path,
                args.device,
                return_char_alignments=False,
            )
        except Exception as error:  # noqa: BLE001 - benchmark tool records per-segment failures.
            skipped.append(
                {
                    "segment_index": segment_index,
                    "reason": "alignment_error",
                    "error": str(error),
                }
            )
            continue

        aligned_words: list[dict[str, Any]] = []
        for aligned_segment in aligned.get("segments", []):
            if isinstance(aligned_segment, dict):
                aligned_words.extend(
                    word for word in aligned_segment.get("words", []) if isinstance(word, dict)
                )

        if len(aligned_words) != len(words):
            skipped.append(
                {
                    "segment_index": segment_index,
                    "reason": "word_count_mismatch",
                    "expected": len(words),
                    "actual": len(aligned_words),
                }
            )

        for word_index, (source_word, aligned_word) in enumerate(zip(words, aligned_words)):
            start = aligned_word.get("start")
            end = aligned_word.get("end")
            if start is None or end is None or float(end) <= float(start):
                skipped.append(
                    {
                        "segment_index": segment_index,
                        "word_index": word_index,
                        "word": source_word,
                        "reason": "invalid_timing",
                    }
                )
                continue
            timings.append(
                {
                    "segment_index": segment_index,
                    "word_index": word_index,
                    "text": source_word,
                    "aligned_text": aligned_word.get("word"),
                    "start_ms": ms(start),
                    "end_ms": ms(end),
                    "score": aligned_word.get("score"),
                }
            )

    return {
        "provider_id": "whisperx-align",
        "provider_version": args.provider_version,
        "audio_path": audio_path,
        "timings": timings,
        "skipped": skipped,
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--input", required=True, help="alignment-request.json path")
    root.add_argument("--output", help="write aligned JSON here; stdout is used when omitted")
    root.add_argument("--language", default="en")
    root.add_argument("--device", default="cpu")
    root.add_argument("--provider-version", default="wav2vec2-base-ls960")
    return root


def main() -> int:
    args = parser().parse_args()
    result = run_alignment(args)
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
