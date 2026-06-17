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
        }
      ]
    }

Alignment is performed *per segment* using the segment's [start_ms, end_ms]
window as an anchor into the full audio. This avoids global Viterbi drift on
long recordings and lets each sentence align independently.

The word-span reconstruction follows the canonical torchaudio forced-alignment
tutorial: tokenize with a "|" separator between words, run forced_align +
merge_tokens, then split the per-character token spans back into words at the
separator positions.
"""

from __future__ import annotations

import json
import sys

import torch
import torchaudio
import torchaudio.functional as F

_BUNDLE = torchaudio.pipelines.MMS_FA
_TOKENIZER = _BUNDLE.get_tokenizer()
_SEPARATOR = "|"


def _unflatten(token_indices: list[int], transcript: str) -> list[list[int]]:
    """Split the flat token-id list into per-word groups using the separator.

    The tokenizer was applied to `"|".join(words)`, so separator token ids mark
    word boundaries. Returns a list whose length equals the number of words.
    """
    sep_token = _TOKENIZER(_SEPARATOR)[0].item()
    groups: list[list[int]] = []
    current: list[int] = []
    for tok in token_indices:
        if tok == sep_token:
            if current:
                groups.append(current)
                current = []
        else:
            current.append(int(tok))
    if current:
        groups.append(current)
    return groups


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
        waveform, sr = torchaudio.load(audio_path)  # (C, N)
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

        transcript_str = _SEPARATOR.join(words)
        token_ids = _TOKENIZER(transcript_str)
        if token_ids.numel() == 0:
            continue

        word_groups = _unflatten(token_ids.tolist(), transcript_str)
        # Build the per-character transcript with separators to map token spans.
        targets = token_ids.view(1, -1).to(torch.int32)
        try:
            aligned, scores = F.forced_align(seg_emissions, targets)
            token_spans = F.merge_tokens(aligned[0], scores[0])
        except Exception as exc:
            print(
                f"align-cli: alignment failed for segment {seg_index}: {exc}",
                file=sys.stderr,
            )
            continue

        # Walk the merged token spans, grouping characters into words at the
        # separator boundaries (matching _unflatten's logic).
        sep_token = _TOKENIZER(_SEPARATOR)[0].item()
        word_starts: list[int] = []
        word_ends: list[int] = []
        word_scores: list[list[float]] = []
        cur_start: int | None = None
        cur_scores: list[float] = []

        for span in token_spans:
            tok = int(span.token)
            if tok == sep_token:
                if cur_start is not None:
                    word_starts.append(cur_start)
                    word_ends.append(int(span.start) - 1)
                    word_scores.append(cur_scores)
                    cur_start = None
                    cur_scores = []
            else:
                if cur_start is None:
                    cur_start = int(span.start)
                    cur_scores = [float(span.score)]
                else:
                    cur_scores.append(float(span.score))

        # Flush the trailing word using the last span's end.
        if cur_start is not None and token_spans:
            word_starts.append(cur_start)
            word_ends.append(int(token_spans[-1].end))
            word_scores.append(cur_scores)

        n_words = min(len(words), len(word_starts))
        for w_idx in range(n_words):
            s_frame = word_starts[w_idx]
            e_frame = word_ends[w_idx]
            if e_frame < s_frame:
                e_frame = s_frame
            score = (
                sum(word_scores[w_idx]) / len(word_scores[w_idx])
                if word_scores[w_idx]
                else 0.0
            )
            start_ms, end_ms = _frame_span_to_ms(
                frame_ratio_ms, s_frame, e_frame, seg_start_ms, seg_end_ms
            )
            timings.append(
                {
                    "segment_index": seg_index,
                    "word_index": w_idx,
                    "text": words[w_idx],
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                    "score": round(float(score), 4),
                }
            )

    json.dump({"timings": timings}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
