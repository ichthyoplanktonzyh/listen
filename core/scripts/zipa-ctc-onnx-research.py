#!/usr/bin/env python3
"""Research-only ZIPA CTC ONNX adapter that preserves experimental frame spans."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


MODEL_REVISION = "9a8d85ba0d2adcbafe7087b82180d0e65c6f3426"
MODEL_SHA256_INT8 = "8f0505173e4606b4afe041f19477b38d6a72a98a19863562749066dc496e86ae"


def load_tokens(path: Path) -> dict[int, str]:
    values = {}
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            parts = line.strip().split()
            if not parts:
                continue
            try:
                token_id = int(parts[-1])
            except ValueError as error:
                raise ValueError(
                    f"{path}:{line_number}: token ID must be an integer"
                ) from error
            symbol = " ".join(parts[:-1])
            if not symbol:
                raise ValueError(f"{path}:{line_number}: token symbol is required")
            values[token_id] = symbol
    if not values:
        raise ValueError("token file is empty")
    return values


def softmax_confidence(row) -> float:
    maximum = float(row.max())
    denominator = sum(math.exp(float(value) - maximum) for value in row)
    return 1.0 / denominator


def derive_phones(frame_ids, confidences, tokens, duration_ms: int, blank_id: int):
    phones = []
    index = 0
    while index < len(frame_ids):
        token_id = int(frame_ids[index])
        end = index + 1
        while end < len(frame_ids) and int(frame_ids[end]) == token_id:
            end += 1
        if token_id != blank_id:
            if token_id not in tokens:
                raise ValueError(f"token ID {token_id} is missing from token file")
            start_ms = round(index * duration_ms / len(frame_ids))
            end_ms = round(end * duration_ms / len(frame_ids))
            if start_ms >= end_ms:
                raise ValueError("projected CTC phone span is empty")
            phones.append(
                {
                    "symbol": tokens[token_id],
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                    "confidence": round(
                        sum(confidences[index:end]) / (end - index),
                        6,
                    ),
                }
            )
        index = end
    return phones


def run(args: argparse.Namespace) -> dict:
    try:
        import librosa
        import numpy as np
        import onnxruntime as ort
        import soundfile as sf
        import torch
        from lhotse.features.kaldi.extractors import Fbank, FbankConfig
    except ImportError as error:
        raise RuntimeError(
            "ZIPA research dependencies are unavailable; use an isolated "
            "Python 3.11 environment with onnxruntime, soundfile, librosa, "
            "lhotse, and torch"
        ) from error

    audio, sample_rate = sf.read(args.audio)
    if len(audio.shape) > 1:
        audio = audio[:, 0]
    if sample_rate != 16000:
        audio = librosa.resample(audio, orig_sr=sample_rate, target_sr=16000)
        sample_rate = 16000
    duration_ms = round(len(audio) * 1000 / sample_rate)
    if duration_ms <= 0:
        raise ValueError("audio is empty")

    extractor = Fbank(FbankConfig(num_filters=80, dither=0.0, snip_edges=False))
    audio_tensor = torch.from_numpy(np.asarray(audio)).float()
    feature = extractor.extract_batch([audio_tensor], sampling_rate=sample_rate)[
        0
    ].unsqueeze(0)
    feature_lengths = np.array([feature.shape[1]], dtype=np.int64)

    session = ort.InferenceSession(
        str(args.model),
        providers=["CPUExecutionProvider"],
    )
    outputs = session.run(None, {"x": feature.numpy(), "x_lens": feature_lengths})
    log_probs = outputs[0][0]
    output_length = int(outputs[1][0]) if len(outputs) > 1 else len(log_probs)
    output_length = min(output_length, len(log_probs))
    if output_length <= 0:
        raise ValueError("model emitted no CTC frames")
    log_probs = log_probs[:output_length]
    frame_ids = log_probs.argmax(axis=-1)
    confidences = [softmax_confidence(row) for row in log_probs]
    phones = derive_phones(
        frame_ids,
        confidences,
        load_tokens(args.tokens),
        duration_ms,
        args.blank_id,
    )
    return {
        "time_base": "relative",
        "phone_set": args.phone_set,
        "phones": phones,
        "provider_id": "zipa-ctc-onnx-research",
        "model_revision": MODEL_REVISION,
        "model_checksum_sha256": MODEL_SHA256_INT8,
        "timestamp_method": "ctc_argmax_linear_frame_projection_v1_experimental",
        "raw_output": {
            "sample_rate_hz": sample_rate,
            "duration_ms": duration_ms,
            "feature_frame_count": int(feature.shape[1]),
            "ctc_frame_count": output_length,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio", type=Path)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--tokens", type=Path, required=True)
    parser.add_argument("--phone-set", default="zipa_ipa_simplified")
    parser.add_argument("--blank-id", type=int, default=0)
    args = parser.parse_args()
    try:
        if not args.audio.is_file():
            raise ValueError("audio file does not exist")
        if not args.model.is_file():
            raise ValueError("model file does not exist")
        if not args.tokens.is_file():
            raise ValueError("tokens file does not exist")
        print(json.dumps(run(args), sort_keys=True))
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
