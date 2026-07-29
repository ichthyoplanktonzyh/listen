#!/usr/bin/env python3
"""Acoustic forced alignment sidecar.

Reads a JSON request on stdin describing an audio file and the known word
sequences per segment, runs torchaudio's CTC forced aligner (MMS_FA), and
writes word-level start/end timestamps (in milliseconds) as JSON on stdout.

This is a *research mode* tool invoked by the Rust transcription coordinator
only when the forced-align venv is detected. The Rust side tolerates any
failure here and falls back to whisper DTW timestamps, so this script may
exit non-zero freely on malformed input or unsupported audio.

Input (stdin, one JSON object):
    {
      "audio_path": "/tmp/.../audio.wav",
      "segments": [
        {
          "index": 0,
          "text": "hello world",
          "words": ["hello", "world"],
          "start_ms": 0,
          "end_ms": 2000
        }
      ]
    }

Output (stdout, one JSON object):
    {
      "timings": [
        {
          "segment_index": 0,
          "word_index": 0,
          "text": "hello",
          "start_ms": 120,
          "end_ms": 480,
          "score": 0.95
        },
        {
          "segment_index": 0,
          "word_index": 1,
          "skipped": true
        }
      ]
    }

Alignment is performed *per segment* using the segment's [start_ms, end_ms]
window as an anchor into the full audio. This avoids global Viterbi drift on
long recordings and lets each sentence align independently.

The word-span reconstruction follows torchaudio 2.9's MMS_FA tokenizer API:
tokenize a list of words, flatten those per-word token ids for forced_align,
then split the merged token spans back by each word's token count.
"""

from __future__ import annotations

import json
import sys

import soundfile as sf
import torch
import torchaudio
import torchaudio.functional as F

_BUNDLE = torchaudio.pipelines.MMS_FA
_TOKENIZER = _BUNDLE.get_tokenizer()
_SUPPORTED_TOKENS = set(_TOKENIZER.dictionary)
_SPECIAL_TOKENS = {"-", "*"}


def _load_audio(audio_path: str) -> tuple[torch.Tensor, int]:
    try:
        return torchaudio.load(audio_path)  # (C, N)
    except Exception as torchaudio_exc:
        try:
            data, sr = sf.read(audio_path, dtype="float32", always_2d=True)
        except Exception:
            raise torchaudio_exc
        waveform = torch.from_numpy(data.T).contiguous()
        return waveform, int(sr)


def _normalize_word(word: str) -> str:
    normalized = word.lower().replace("’", "'")
    return "".join(
        char
        for char in normalized
        if char in _SUPPORTED_TOKENS and char not in _SPECIAL_TOKENS
    )


def _tokenize_words(words: list[str]) -> tuple[list[tuple[int, str]], list[list[int]], list[int]]:
    alignable_words: list[tuple[int, str]] = []
    token_groups: list[list[int]] = []
    skipped_word_indexes: list[int] = []
    for word_index, word in enumerate(words):
        normalized = _normalize_word(word)
        if not normalized:
            skipped_word_indexes.append(word_index)
            continue
        ids = [int(token) for token in _TOKENIZER([normalized])[0]]
        if ids:
            alignable_words.append((word_index, word))
            token_groups.append(ids)
        else:
            skipped_word_indexes.append(word_index)
    return alignable_words, token_groups, skipped_word_indexes


def _frame_span_to_ms(
    frame_ratio_ms: float, start: int, end: int, seg_start_ms: int,
    seg_end_ms: int,
) -> tuple[int, int]:
    local_start_ms = start * frame_ratio_ms
    local_end_ms = (end + 1) * frame_ratio_ms
    start_ms = seg_start_ms + local_start_ms
    end_ms = seg_start_ms + local_end_ms
    start_ms = max(seg_start_ms, min(start_ms, seg_end_ms))
    end_ms = max(start_ms, min(end_ms, seg_end_ms))
    return int(round(start_ms)), int(round(end_ms))


def main() -> int:
    try:
        request = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"align-cli: invalid stdin JSON: {exc}", file=sys.stderr)
        return 2

    audio_path = request.get("audio_path")
    segments = request.get("segments", [])
    if not audio_path or not isinstance(segments, list):
        print("align-cli: missing audio_path or segments", file=sys.stderr)
        return 2

    try:
        waveform, sr = _load_audio(audio_path)
    except Exception as exc:
        print(f"align-cli: failed to load audio {audio_path}: {exc}", file=sys.stderr)
        return 4

    # MMS_FA expects 16 kHz mono.
    if sr != _BUNDLE.sample_rate:
        waveform = torchaudio.functional.resample(waveform, sr, _BUNDLE.sample_rate)
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    waveform = waveform[0:1]  # (1, N)

    with torch.no_grad():
        emissions, _ = _BUNDLE.get_model()(waveform)  # (1, T_frames, vocab)

    # Derive the ms-per-frame ratio from the actual emission length so we don't
    # hard-code a hop length.
    n_samples = waveform.shape[1]
    n_frames = emissions.shape[1]
    frame_ratio_ms = (n_samples / _BUNDLE.sample_rate) * 1000.0 / max(n_frames, 1)

    timings: list[dict] = []
    for seg in segments:
        words = [w for w in seg.get("words", []) if w]
        if not words:
            continue
        seg_index = int(seg.get("index", 0))
        seg_start_ms = int(seg.get("start_ms", 0))
        seg_end_ms = int(seg.get("end_ms", seg_start_ms))
        if seg_end_ms <= seg_start_ms:
            continue

        # Slice emissions to the segment window.
        start_frame = max(0, int(seg_start_ms / frame_ratio_ms))
        end_frame = max(start_frame + 1, int(seg_end_ms / frame_ratio_ms))
        seg_emissions = emissions[
            :, start_frame : min(end_frame, n_frames), :
        ]

        segment_timings: list[dict] = []
        alignable_words, token_groups, skipped_word_indexes = _tokenize_words(words)
        for word_index in skipped_word_indexes:
            segment_timings.append(
                {
                    "segment_index": seg_index,
                    "word_index": word_index,
                    "skipped": True,
                }
            )
        flat_token_ids = [token for group in token_groups for token in group]
        if not flat_token_ids:
            timings.extend(sorted(segment_timings, key=lambda row: row["word_index"]))
            continue

        targets = torch.tensor([flat_token_ids], dtype=torch.int32)
        try:
            aligned, scores = F.forced_align(seg_emissions, targets)
            token_spans = F.merge_tokens(aligned[0], scores[0])
        except Exception as exc:
            print(
                f"align-cli: alignment failed for segment {seg_index}: {exc}",
                file=sys.stderr,
            )
            timings.extend(sorted(segment_timings, key=lambda row: row["word_index"]))
            continue

        span_cursor = 0
        for (word_index, word), group in zip(alignable_words, token_groups):
            group_spans = token_spans[span_cursor : span_cursor + len(group)]
            span_cursor += len(group)
            if not group_spans:
                continue
            s_frame = int(group_spans[0].start)
            e_frame = int(group_spans[-1].end)
            if e_frame < s_frame:
                e_frame = s_frame
            word_scores = [float(span.score) for span in group_spans]
            score = (
                sum(word_scores) / len(word_scores)
                if word_scores
                else 0.0
            )
            start_ms, end_ms = _frame_span_to_ms(
                frame_ratio_ms, s_frame, e_frame, seg_start_ms, seg_end_ms
            )
            segment_timings.append(
                {
                    "segment_index": seg_index,
                    "word_index": word_index,
                    "text": word,
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                    "score": round(float(score), 4),
                }
            )
        timings.extend(sorted(segment_timings, key=lambda row: row["word_index"]))

    json.dump(
        {
            "timings": timings,
            "provenance": {
                "torchaudio_version": torchaudio.__version__,
                "model_bundle": "torchaudio.pipelines.MMS_FA",
                "model_asset": getattr(_BUNDLE, "_path", "unknown"),
            },
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
