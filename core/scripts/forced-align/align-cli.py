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
import os
import sys
from multiprocessing import get_context

import soundfile as sf
import torch
import torchaudio
import torchaudio.functional as F

_BUNDLE = torchaudio.pipelines.MMS_FA
_TOKENIZER = _BUNDLE.get_tokenizer()
_SUPPORTED_TOKENS = set(_TOKENIZER.dictionary)
_SPECIAL_TOKENS = {"-", "*"}

# Chunked parallel forward. The segment list is partitioned so that every
# chunk boundary falls on a segment boundary (each chunk contains whole
# sentences), a worker process forwards its chunk independently, and the CTC
# decoding below runs per segment exactly as in the single-shot path. The
# emissions are never spliced, so chunk borders never cut through a word.
_LISTEN_FA_CHUNK_MS_ENV = "LISTEN_FA_CHUNK_MS"
_LISTEN_FA_CHUNKS_ENV = "LISTEN_FA_CHUNKS"
_LISTEN_FA_WORKERS_ENV = "LISTEN_FA_WORKERS"
_CHUNK_MS_DEFAULT = 180_000  # 3 minutes of audio per chunk
_MAX_WORKERS_DEFAULT = 4


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


def _load_audio_block(
    audio_path: str, start_ms: int, end_ms: int
) -> tuple[torch.Tensor, int]:
    """Load only the [start_ms, end_ms) slice of the audio, in native sample
    rate. The caller resamples like the full-audio path does.

    torchaudio (TorchCodec) is the primary reader because the Gen pipeline
    hands us compressed containers (m4a/mp4); soundfile cannot decode those.
    """
    try:
        info = sf.info(audio_path)
    except Exception:
        info = None
    if info is not None:
        sr = int(info.samplerate)
        start_sample = int(start_ms / 1000 * sr)
        num_samples = max(1, int((end_ms - start_ms) / 1000 * sr))
        try:
            waveform = torchaudio.load(
                audio_path, frame_offset=start_sample, num_frames=num_samples
            )[0]
            return waveform, sr
        except Exception:
            pass
    try:
        waveform, sr = _load_audio(audio_path)
    except Exception as exc:
        raise exc
    if sr != 0:
        start_sample = int(start_ms / 1000 * sr)
        num_samples = max(1, int((end_ms - start_ms) / 1000 * sr))
        waveform = waveform[:, start_sample : start_sample + num_samples]
    return waveform, sr


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


def _inference_device() -> torch.device:
    """Metal (MPS) when available and not disabled; the emulsions move back to
    CPU for the cheap CTC decoding steps, which are not always MPS-safe."""
    forced = os.environ.get("LISTEN_FA_DEVICE", "").strip().lower()
    if forced in ("cpu", "mps"):
        return torch.device(forced)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _align_segments(
    emissions: torch.Tensor,
    frame_ratio_ms: float,
    segments: list[dict],
    chunk_start_ms: int,
) -> list[dict]:
    """Run CTC forced alignment for every segment against ``emissions``,
    which covers the [chunk_start_ms, ...) window of the audio. Segment
    windows are absolute; frames are relative to the chunk start."""
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
        n_frames = emissions.shape[1]
        start_frame = max(0, int((seg_start_ms - chunk_start_ms) / frame_ratio_ms))
        end_frame = max(start_frame + 1, int((seg_end_ms - chunk_start_ms) / frame_ratio_ms))
        seg_emissions = emissions[:, start_frame : min(end_frame, n_frames), :]

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
    return timings


def _degraded_chunk(segments: list[dict]) -> list[dict]:
    """Honest degradation: every word of the chunk is reported skipped."""
    timings: list[dict] = []
    for seg in segments:
        for word_index in range(len([w for w in seg.get("words", []) if w])):
            timings.append(
                {
                    "segment_index": int(seg.get("index", 0)),
                    "word_index": word_index,
                    "skipped": True,
                }
            )
    return timings


def _forward_chunk(args: tuple) -> list[dict]:
    """Worker process: load the chunk slice, forward it, decode it."""
    audio_path, start_ms, end_ms, segments, device = args
    try:
        waveform, sr = _load_audio_block(audio_path, start_ms, end_ms)
        if sr != _BUNDLE.sample_rate:
            waveform = torchaudio.functional.resample(waveform, sr, _BUNDLE.sample_rate)
        if waveform.shape[0] > 1:
            waveform = waveform.mean(dim=0, keepdim=True)
        waveform = waveform[0:1]  # (1, N)
        with torch.no_grad():
            model = _BUNDLE.get_model().to(device)
            emissions, _ = model(waveform.to(device))  # (1, T_frames, vocab)
        if device != torch.device("cpu"):
            emissions = emissions.cpu()
        del model
        n_samples = waveform.shape[1]
        n_frames = emissions.shape[1]
        frame_ratio_ms = (n_samples / _BUNDLE.sample_rate) * 1000.0 / max(n_frames, 1)
        return _align_segments(emissions, frame_ratio_ms, segments, start_ms)
    except Exception as exc:
        print(
            f"align-cli: chunk forward failed for [{start_ms},{end_ms}): {exc}",
            file=sys.stderr,
        )
        return _degraded_chunk(segments)


def _partition_segments(segments: list[dict], n_chunks: int) -> list[tuple[int, int, list[dict]]]:
    """Greedily pack whole segments into ~n_chunks time-ordered chunks. Every
    chunk boundary falls on a segment boundary, so no word is ever cut."""
    ordered = sorted(segments, key=lambda seg: (int(seg.get("start_ms", 0)), int(seg.get("index", 0))))
    total_ms = max(int(seg.get("end_ms", 0)) for seg in ordered) if ordered else 0
    target_ms = max(total_ms / max(n_chunks, 1), 1)
    chunks: list[tuple[int, int, list[dict]]] = []
    current: list[dict] = []
    for seg in ordered:
        start = int(seg.get("start_ms", 0))
        end = int(seg.get("end_ms", start))
        if current and end - int(current[0].get("start_ms", 0)) >= target_ms and len(chunks) + 1 < n_chunks:
            first = int(current[0].get("start_ms", 0))
            last = max(int(s.get("end_ms", first)) for s in current)
            chunks.append((first, last, current))
            current = []
        current.append(seg)
    if current:
        first = int(current[0].get("start_ms", 0))
        last = max(int(s.get("end_ms", first)) for s in current)
        chunks.append((first, last, current))
    return chunks


def _chunk_config(segments: list[dict]) -> tuple[int, int]:
    total_ms = max((int(seg.get("end_ms", 0)) for seg in segments), default=0)
    if not segments or total_ms <= 0:
        return 1, 1
    forced_chunks = os.environ.get(_LISTEN_FA_CHUNKS_ENV, "").strip()
    if forced_chunks.isdigit() and int(forced_chunks) > 0:
        n_chunks = int(forced_chunks)
    else:
        chunk_ms = os.environ.get(_LISTEN_FA_CHUNK_MS_ENV, "").strip()
        chunk_ms = int(chunk_ms) if chunk_ms.isdigit() and int(chunk_ms) > 0 else _CHUNK_MS_DEFAULT
        n_chunks = max(1, -(-total_ms // chunk_ms))
    workers = os.environ.get(_LISTEN_FA_WORKERS_ENV, "").strip()
    if workers.isdigit() and int(workers) > 0:
        max_workers = int(workers)
    else:
        max_workers = _MAX_WORKERS_DEFAULT
    return n_chunks, min(max_workers, n_chunks)


def main() -> int:
    import time as _time

    _started_at = _time.monotonic()
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

    device = _inference_device()
    n_chunks, n_workers = _chunk_config(segments)
    if n_chunks > 1:
        chunks = _partition_segments(segments, n_chunks)
        if len(chunks) > 1:
            jobs = [
                (audio_path, start_ms, end_ms, chunk_segments, str(device))
                for start_ms, end_ms, chunk_segments in chunks
            ]
            with get_context("spawn").Pool(processes=n_workers) as pool:
                results = pool.map(_forward_chunk, jobs)
            timings = sorted(
                [row for result in results for row in result],
                key=lambda row: (row["segment_index"], row["word_index"]),
            )
            json.dump(
                {
                    "timings": timings,
                    "provenance": {
                        "torchaudio_version": torchaudio.__version__,
                        "model_bundle": "torchaudio.pipelines.MMS_FA",
                        "model_asset": getattr(_BUNDLE, "_path", "unknown"),
                        "chunked": {"chunks": len(chunks), "workers": n_workers},
                        "elapsed_seconds": round(_time.monotonic() - _started_at, 1),
                    },
                },
                sys.stdout,
            )
            sys.stdout.write("\n")
            return 0

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
        model = _BUNDLE.get_model().to(device)
        emissions, _ = model(waveform.to(device))  # (1, T_frames, vocab)
    if device != torch.device("cpu"):
        emissions = emissions.cpu()
    del model

    # Derive the ms-per-frame ratio from the actual emission length so we don't
    # hard-code a hop length.
    n_samples = waveform.shape[1]
    n_frames = emissions.shape[1]
    frame_ratio_ms = (n_samples / _BUNDLE.sample_rate) * 1000.0 / max(n_frames, 1)

    timings = _align_segments(emissions, frame_ratio_ms, segments, 0)

    json.dump(
        {
            "timings": timings,
            "provenance": {
                "torchaudio_version": torchaudio.__version__,
                "model_bundle": "torchaudio.pipelines.MMS_FA",
                "model_asset": getattr(_BUNDLE, "_path", "unknown"),
                "elapsed_seconds": round(_time.monotonic() - _started_at, 1),
            },
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
