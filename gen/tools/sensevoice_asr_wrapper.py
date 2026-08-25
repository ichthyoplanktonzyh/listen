#!/usr/bin/env python3
"""SenseVoiceSmall sidecar for listen-gen.

Runs the FunASR SenseVoice + FSMN-VAD pipeline and prints one
``listen_gen.sensevoice-asr-core.v1`` JSON object on stdout:

    {
      "schema": "listen_gen.sensevoice-asr-core.v1",
      "runtime_version": "1.1.0",
      "segments": [                       # one entry per VAD speech region
        {"start_ms": 0, "end_ms": 2000, "text": "<|en|><|NEUTRAL|><|Speech|>Hello."},
        ...
      ]
    }

The FSMN-VAD stage supplies real speech-region boundaries, and SenseVoice
transcribes each region.  The ``<|...|>`` meta tags (language / emotion / audio
event) are left in the text here; the listen-gen ASR adapter extracts the
language tag and strips every meta tag so only the transcript reaches
Structured Reading.  SenseVoice does not emit reliable word timing, so no word
spans are produced — forced alignment supplies the final word timeline.

Install the runtime with::

    pip install "listen-gen[asr-sensevoice]"
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

        return version("funasr")
    except Exception:
        try:
            import funasr  # type: ignore

            return str(getattr(funasr, "__version__", "unknown"))
        except Exception:
            return "unknown"


def _select_device(preference: str) -> str:
    choice = (preference or "auto").strip().lower()
    if choice in ("cpu", "mps"):
        return choice
    if choice == "cuda":
        return "cuda:0"
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda:0"
        mps = getattr(torch.backends, "mps", None)
        if mps is not None and mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def _vad_regions(vad_model: Any, samples: Any, sample_rate: int, total: int) -> list[tuple[int, int]]:
    """Return ordered [start_ms, end_ms] speech regions, or the whole clip."""
    try:
        results = vad_model.generate(input=samples, cache={}, disable_pbar=True)
    except Exception:
        results = []
    regions: list[tuple[int, int]] = []
    if results:
        value = results[0].get("value") if isinstance(results[0], dict) else None
        for span in value or []:
            try:
                start_ms, end_ms = int(span[0]), int(span[1])
            except (TypeError, ValueError, IndexError):
                continue
            start_ms = max(0, start_ms)
            end_ms = min(int(round(total * 1000 / sample_rate)), end_ms)
            if end_ms > start_ms:
                regions.append((start_ms, end_ms))
    if not regions:
        regions = [(0, int(round(total * 1000 / sample_rate)))]
    return regions


def main() -> None:
    parser = argparse.ArgumentParser(description="SenseVoiceSmall sidecar for listen-gen")
    parser.add_argument("--audio", required=True, help="normalized 16 kHz mono WAV path")
    # FunASR resolves models from ModelScope, so this is the FunASR/ModelScope
    # id for SenseVoiceSmall (the same model published on Hugging Face as
    # FunAudioLLM/SenseVoiceSmall).
    parser.add_argument("--model-id", default="iic/SenseVoiceSmall")
    parser.add_argument(
        "--language", default="auto", choices=["auto", "zh", "en", "yue", "ja", "ko"]
    )
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "cuda", "mps"])
    parser.add_argument("--vad-model", default="fsmn-vad")
    args = parser.parse_args()

    # FunASR prints a version banner and progress bars to stdout; keep stdout
    # clean for the single result JSON by routing all library noise to stderr.
    real_stdout = sys.stdout
    sys.stdout = sys.stderr

    try:
        import soundfile as sf
        from funasr import AutoModel
    except ImportError as error:  # pragma: no cover - environment dependent
        _fail(
            "FunASR runtime is not installed. Install with "
            f"'pip install \"listen-gen[asr-sensevoice]\"'. Import error: {error}"
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

    device = _select_device(args.device)
    try:
        asr_model = AutoModel(
            model=args.model_id, device=device, disable_update=True
        )
        vad_model = AutoModel(
            model=args.vad_model, device=device, disable_update=True
        )
    except Exception as error:  # pragma: no cover - model init failure
        _fail(f"could not load SenseVoice / VAD model: {error}")

    regions = _vad_regions(vad_model, samples, int(sample_rate), total)

    segments: list[dict[str, Any]] = []
    for start_ms, end_ms in regions:
        start_sample = max(0, int(start_ms * sample_rate / 1000))
        end_sample = min(total, int(end_ms * sample_rate / 1000))
        if end_sample <= start_sample:
            continue
        window = samples[start_sample:end_sample]
        try:
            results = asr_model.generate(
                input=window,
                cache={},
                language=args.language,
                use_itn=True,
                disable_pbar=True,
            )
        except Exception as error:  # pragma: no cover - inference failure
            _fail(f"sensevoice inference failed: {error}")
        text = ""
        if results and isinstance(results[0], dict):
            text = str(results[0].get("text", "") or "")
        segments.append({"start_ms": start_ms, "end_ms": end_ms, "text": text})

    document = {
        "schema": "listen_gen.sensevoice-asr-core.v1",
        "runtime_version": _runtime_version(),
        "segments": segments,
    }
    json.dump(document, real_stdout, ensure_ascii=False)
    real_stdout.write("\n")


if __name__ == "__main__":
    main()
