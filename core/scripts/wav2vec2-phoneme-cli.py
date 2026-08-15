#!/usr/bin/env python3
"""wav2vec2 CTC phoneme recognition sidecar for LLPlayerNext.

Runs facebook/wav2vec2-lv-60-espeak-cv-ft (or compatible model from a local
directory) on an audio segment and outputs per-phone IPA symbols with
timestamps as JSON to stdout.

Usage:
    python3 wav2vec2-phoneme-cli.py \
        --model-dir /path/to/model \
        --audio /path/to/audio.wav \
        --start-ms 1200 --end-ms 4500

Output (stdout):
    {"phones": [{"symbol": "ʃ", "start_ms": 1200, "end_ms": 1240, "confidence": 0.92}, ...]}

Long windows are chunked and forwarded in parallel worker processes; the
per-chunk logits are concatenated back into one tensor before the (unchanged)
CTC decode. Chunk borders sit on plain time slices, so a phone whose span
crosses a border may shift by a frame or two — the same tolerance the CTC
decode already has for boundary frames.
"""
import argparse
import json
import os
import sys
import time as _time
from multiprocessing import get_context

import numpy as np
import soundfile as sf
import torch
import torchaudio
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

# Chunked parallel forward knobs. A chunk is skipped (honestly, with a
# warning) if its worker fails; an entirely failed window yields an empty
# phone list, which the caller treats as a degraded stage.
_LISTEN_FA_CHUNK_MS_ENV = "LISTEN_FA_CHUNK_MS"
_LISTEN_FA_CHUNKS_ENV = "LISTEN_FA_CHUNKS"
_LISTEN_FA_WORKERS_ENV = "LISTEN_FA_WORKERS"
_CHUNK_MS_DEFAULT = 180_000  # 3 minutes of audio per chunk
_MAX_WORKERS_DEFAULT = 4


def load_audio(path: str, start_ms: int, end_ms: int) -> tuple[np.ndarray, int]:
    waveform, sr = torchaudio.load(path)
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if sr != 16000:
        waveform = torchaudio.functional.resample(waveform, sr, 16000)
        sr = 16000
    start_sample = int(start_ms * sr / 1000)
    end_sample = int(end_ms * sr / 1000)
    waveform = waveform[:, start_sample:end_sample]
    return waveform.squeeze(0).numpy(), sr


def load_audio_slice(path: str, start_ms: int, end_ms: int) -> tuple[np.ndarray, int]:
    """Load only the [start_ms, end_ms) window, 16 kHz mono.

    torchaudio (TorchCodec) is the primary reader because the Gen pipeline
    hands us compressed containers (m4a/mp4); soundfile cannot decode those.
    """
    try:
        info = sf.info(path)
    except Exception:
        info = None
    if info is not None:
        sr = int(info.samplerate)
        start_sample = int(start_ms / 1000 * sr)
        num_samples = max(1, int((end_ms - start_ms) / 1000 * sr))
        try:
            waveform, sr = torchaudio.load(
                path, frame_offset=start_sample, num_frames=num_samples
            )
        except Exception:
            info = None
    if info is None:
        waveform, sr = torchaudio.load(path)
        start_sample = int(start_ms / 1000 * sr)
        num_samples = max(1, int((end_ms - start_ms) / 1000 * sr))
        waveform = waveform[:, start_sample : start_sample + num_samples]
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if sr != 16000:
        waveform = torchaudio.functional.resample(waveform, sr, 16000)
        sr = 16000
    return waveform[0].numpy(), sr


def ctc_decode_with_timestamps(
    logits: torch.Tensor,
    processor: Wav2Vec2Processor,
    audio_start_ms: int,
    audio_duration_ms: int,
) -> list[dict]:
    predicted_ids = torch.argmax(logits, dim=-1)[0]
    num_frames = predicted_ids.shape[0]
    ms_per_frame = audio_duration_ms / num_frames if num_frames > 0 else 20.0

    phones = []
    prev_id = -1
    phone_start_frame = 0

    for frame_idx, token_id in enumerate(predicted_ids.tolist()):
        if token_id != prev_id:
            if prev_id > 0:
                symbol = processor.decode([prev_id]).strip()
                if symbol:
                    frame_logits = logits[0, phone_start_frame:frame_idx, prev_id]
                    confidence = float(torch.sigmoid(frame_logits.mean()).item())
                    phones.append({
                        "symbol": symbol,
                        "start_ms": audio_start_ms + int(phone_start_frame * ms_per_frame),
                        "end_ms": audio_start_ms + int(frame_idx * ms_per_frame),
                        "confidence": round(confidence, 4),
                    })
            phone_start_frame = frame_idx
            prev_id = token_id

    if prev_id > 0:
        symbol = processor.decode([prev_id]).strip()
        if symbol:
            frame_logits = logits[0, phone_start_frame:num_frames, prev_id]
            confidence = float(torch.sigmoid(frame_logits.mean()).item())
            phones.append({
                "symbol": symbol,
                "start_ms": audio_start_ms + int(phone_start_frame * ms_per_frame),
                "end_ms": audio_start_ms + int(num_frames * ms_per_frame),
                "confidence": round(confidence, 4),
            })

    return phones


def _inference_device() -> torch.device:
    """Metal (MPS) when available and not disabled; the CTC decode moves the
    logits back to CPU because argmax/sigmoid loops are not MPS-safe."""
    forced = os.environ.get("LISTEN_FA_DEVICE", "").strip().lower()
    if forced in ("cpu", "mps"):
        return torch.device(forced)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _chunk_job(args: tuple) -> torch.Tensor | None:
    """Worker process: forward one [start_ms, end_ms) slice, return logits."""
    model_dir, audio, start_ms, end_ms, device = args
    try:
        processor = Wav2Vec2Processor.from_pretrained(model_dir)
        model = Wav2Vec2ForCTC.from_pretrained(model_dir).to(device)
        model.eval()
        audio_arr, sr = load_audio_slice(audio, start_ms, end_ms)
        if audio_arr.shape[0] == 0:
            return None
        inputs = processor(audio_arr, sampling_rate=sr, return_tensors="pt", padding=True)
        with torch.no_grad():
            logits = model(**{key: value.to(device) for key, value in inputs.items()}).logits
        if device != torch.device("cpu"):
            logits = logits.cpu()
        return logits
    except Exception as exc:
        print(
            f"wav2vec2-phoneme-cli: chunk forward failed for "
            f"[{start_ms},{end_ms}): {exc}",
            file=sys.stderr,
        )
        return None


def _chunk_config(total_ms: int) -> tuple[int, int]:
    if total_ms <= 0:
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


def main():
    _started_at = _time.monotonic()
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--start-ms", type=int, required=True)
    parser.add_argument("--end-ms", type=int, required=True)
    args = parser.parse_args()

    device = _inference_device()
    processor = Wav2Vec2Processor.from_pretrained(args.model_dir)
    total_ms = args.end_ms - args.start_ms
    n_chunks, n_workers = _chunk_config(total_ms)

    if n_chunks > 1:
        bounds = [
            args.start_ms + int(total_ms * i / n_chunks)
            for i in range(n_chunks + 1)
        ]
        jobs = [
            (args.model_dir, args.audio, bounds[i], bounds[i + 1], str(device))
            for i in range(n_chunks)
        ]
        with get_context("spawn").Pool(processes=n_workers) as pool:
            chunk_logits = pool.map(_chunk_job, jobs)
        parts = [logits for logits in chunk_logits if logits is not None]
        if parts:
            logits = torch.cat(parts, dim=1)
        else:
            logits = None
    else:
        model = Wav2Vec2ForCTC.from_pretrained(args.model_dir).to(device)
        model.eval()
        audio, sr = load_audio(args.audio, args.start_ms, args.end_ms)
        inputs = processor(audio, sampling_rate=sr, return_tensors="pt", padding=True)
        with torch.no_grad():
            logits = model(**{key: value.to(device) for key, value in inputs.items()}).logits
        if device != torch.device("cpu"):
            logits = logits.cpu()

    if logits is None:
        json.dump({"phones": []}, sys.stdout)
        return

    phones = ctc_decode_with_timestamps(logits, processor, args.start_ms, total_ms)

    json.dump({"phones": phones, "elapsed_seconds": round(_time.monotonic() - _started_at, 1)}, sys.stdout)


if __name__ == "__main__":
    main()
