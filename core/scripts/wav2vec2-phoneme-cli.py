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
"""
import argparse
import json
import sys

import numpy as np
import torch
import torchaudio
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--start-ms", type=int, required=True)
    parser.add_argument("--end-ms", type=int, required=True)
    args = parser.parse_args()

    processor = Wav2Vec2Processor.from_pretrained(args.model_dir)
    model = Wav2Vec2ForCTC.from_pretrained(args.model_dir)
    model.eval()

    audio, sr = load_audio(args.audio, args.start_ms, args.end_ms)
    duration_ms = args.end_ms - args.start_ms

    inputs = processor(audio, sampling_rate=sr, return_tensors="pt", padding=True)
    with torch.no_grad():
        logits = model(**inputs).logits

    phones = ctc_decode_with_timestamps(logits, processor, args.start_ms, duration_ms)

    json.dump({"phones": phones}, sys.stdout)


if __name__ == "__main__":
    main()
