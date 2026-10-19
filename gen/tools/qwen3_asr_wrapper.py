#!/usr/bin/env python3
"""Qwen3-ASR sidecar for listen-gen.

Runs the official ``qwen-asr`` Transformers backend with the Qwen3 forced
aligner attached and prints one ``listen_gen.qwen3-asr-core.v1`` JSON object on
stdout:

    {
      "schema": "listen_gen.qwen3-asr-core.v1",
      "runtime_version": "0.0.6",
      "language": "English",            # raw Qwen language name (may be "")
      "text": "Hello world. ...",       # merged transcript text
      "duration_ms": 12345,
      "items": [                        # forced-align items, absolute ms
        {"text": "Hello", "start_ms": 0, "end_ms": 500},
        ...
      ]
    }

The heavy runtime (torch / transformers / qwen-asr / librosa) lives only here so
the base ``listen-gen`` install stays light.  The ``qwen-asr`` toolkit already
chunks long audio and merges the per-token timestamps back to absolute time, so
this wrapper does no chunking of its own.  The listen-gen ASR adapter maps the
language name to a stable tag, anchors these items onto reading word tokens, and
stamps provider provenance; the authoritative word timeline is still produced by
the configured forced aligner in the rich chain.

Install the runtime with::

    pip install "listen-gen[asr-qwen]"
    # plus a Transformers build that ships the Qwen3-ASR classes
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def _fail(message: str) -> "NoReturn":  # type: ignore[valid-type]
    sys.stderr.write(message.rstrip() + "\n")
    raise SystemExit(1)


def _runtime_version() -> str:
    try:
        from importlib.metadata import version

        return version("qwen-asr")
    except Exception:
        try:
            import qwen_asr  # type: ignore

            return str(getattr(qwen_asr, "__version__", "unknown"))
        except Exception:
            return "unknown"


def _select_device(preference: str, torch: Any) -> str:
    choice = (preference or "auto").strip().lower()
    if choice in ("cpu", "cuda", "mps"):
        return choice
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


def _resolve_dtype(preference: str, device: str, torch: Any) -> Any:
    choice = (preference or "auto").strip().lower()
    if choice in ("float32", "fp32"):
        return torch.float32
    if choice in ("bfloat16", "bf16"):
        return torch.bfloat16
    if choice in ("float16", "fp16", "half"):
        return torch.float16
    # auto: bf16 only pays off on CUDA; MPS/CPU stay in float32 for op coverage.
    return torch.bfloat16 if device == "cuda" else torch.float32


def main() -> None:
    parser = argparse.ArgumentParser(description="Qwen3-ASR sidecar for listen-gen")
    parser.add_argument("--audio", required=True, help="normalized 16 kHz mono WAV path")
    parser.add_argument("--model-id", default="Qwen/Qwen3-ASR-0.6B")
    parser.add_argument(
        "--forced-aligner-model-id", default="Qwen/Qwen3-ForcedAligner-0.6B"
    )
    parser.add_argument(
        "--language",
        default="auto",
        help="'auto' or a Qwen language name such as 'English'",
    )
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "cuda", "mps"])
    parser.add_argument("--dtype", default="auto")
    args = parser.parse_args()

    # Keep stdout clean for the single result JSON: route any library banners or
    # progress output (transformers/qwen-asr) to stderr instead.
    real_stdout = sys.stdout
    sys.stdout = sys.stderr

    try:
        import numpy as np  # noqa: F401
        import soundfile as sf
        import torch
        from qwen_asr import Qwen3ASRModel
    except ImportError as error:  # pragma: no cover - environment dependent
        _fail(
            "qwen-asr runtime is not installed. Install with "
            "'pip install \"listen-gen[asr-qwen]\"' (plus a Transformers build "
            f"that ships the Qwen3-ASR classes). Import error: {error}"
        )

    try:
        samples, sample_rate = sf.read(args.audio, dtype="float32", always_2d=False)
    except Exception as error:  # pragma: no cover - decode failure
        _fail(f"could not read audio: {error}")
    if getattr(samples, "ndim", 1) > 1:
        samples = samples.mean(axis=1)
    total = int(getattr(samples, "shape", [0])[0])
    if sample_rate <= 0 or total == 0:
        _fail("audio is empty")
    duration_ms = int(round(total * 1000 / sample_rate))

    device = _select_device(args.device, torch)
    dtype = _resolve_dtype(args.dtype, device, torch)
    device_map = "cuda:0" if device == "cuda" else device
    try:
        model = Qwen3ASRModel.from_pretrained(
            args.model_id,
            forced_aligner=args.forced_aligner_model_id,
            dtype=dtype,
            device_map=device_map,
        )
    except Exception as error:  # pragma: no cover - model init failure
        _fail(f"could not load Qwen3-ASR model: {error}")

    language = None if args.language.strip().lower() in ("", "auto", "und") else args.language
    try:
        results = model.transcribe(
            (samples, int(sample_rate)),
            language=language,
            return_time_stamps=True,
        )
    except Exception as error:  # pragma: no cover - inference failure
        _fail(f"qwen3 asr inference failed: {error}")

    if not results:
        _fail("qwen3 asr returned no result")
    result = results[0]
    raw_language = str(getattr(result, "language", "") or "")
    text = str(getattr(result, "text", "") or "")

    items: list[dict[str, Any]] = []
    time_stamps = getattr(result, "time_stamps", None)
    for item in _iter_items(time_stamps):
        item_text = str(getattr(item, "text", "") or "")
        start_ms = _seconds_to_ms(getattr(item, "start_time", 0.0))
        end_ms = _seconds_to_ms(getattr(item, "end_time", 0.0))
        if end_ms < start_ms:
            end_ms = start_ms
        items.append({"text": item_text, "start_ms": start_ms, "end_ms": end_ms})

    document = {
        "schema": "listen_gen.qwen3-asr-core.v1",
        "runtime_version": _runtime_version(),
        "language": raw_language,
        "text": text,
        "duration_ms": duration_ms,
        "items": items,
    }
    json.dump(document, real_stdout, ensure_ascii=False)
    real_stdout.write("\n")


def _iter_items(time_stamps: Any) -> list[Any]:
    if time_stamps is None:
        return []
    items = getattr(time_stamps, "items", None)
    if items is not None:
        return list(items)
    try:
        return list(time_stamps)
    except TypeError:
        return []


def _seconds_to_ms(value: Any) -> int:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return 0
    if seconds < 0:
        seconds = 0.0
    return int(round(seconds * 1000))


if __name__ == "__main__":
    main()
