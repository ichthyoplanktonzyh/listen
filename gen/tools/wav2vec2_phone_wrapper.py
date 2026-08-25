#!/usr/bin/env python3
"""wav2vec2 CTC phoneme sidecar for listen-gen.

Runs a ``facebook/wav2vec2-*-espeak-*`` CTC phoneme-recognition checkpoint over
one audio clip and prints a single JSON object on stdout::

    {
      "phones": [
        {"symbol": "n", "start_ms": 0, "end_ms": 60,
         "confidence": 0.83, "display_ipa": "n"},
        ...
      ]
    }

The heavy runtime (torch / transformers / soundfile) lives only here so the base
``listen-gen`` install stays light.  The listen-gen phone adapter
(:class:`listen_gen.phone.Wav2Vec2CtcPhoneAdapter`) invokes this wrapper as::

    <python> <this-sidecar> --model-dir DIR --audio WAV --start-ms 0 --end-ms N

and wraps the emitted ``phones`` into a ``listen_gen.phone-result`` payload,
stamping provider/model provenance and the ``ipa`` phone set.  Each observed
phone keeps its real acoustic ``start_ms``/``end_ms``; the adapter never clamps
or drops them, so this wrapper must emit them **sorted and non-overlapping**
(``start_ms >= previous end_ms`` and ``end_ms > start_ms``), which the CTC
collapse below guarantees.

The espeak-flavoured checkpoints emit IPA phoneme tokens directly, so this
wrapper reads ``vocab.json`` from the model directory for the id->token map and
never imports ``phonemizer``/``espeak-ng`` (only the *processor's* tokenizer
needs those; the feature path here does not).  Audio normalization mirrors
``Wav2Vec2FeatureExtractor(do_normalize=True)`` (per-utterance zero-mean,
unit-variance) so logits match the reference pipeline.

Install the runtime with::

    pip install "listen-gen[phones-wav2vec2]"
    # torch + transformers + soundfile

The model directory must be a self-contained snapshot holding ``config.json``,
``vocab.json``, ``preprocessor_config.json`` and a weight file
(``model.safetensors`` or ``pytorch_model.bin``) -- e.g. a resolved Hugging Face
cache snapshot of ``facebook/wav2vec2-lv-60-espeak-cv-ft``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# Vocab ids 0..3 are ``<pad> <s> </s> <unk>`` in the espeak checkpoints; ``<pad>``
# doubles as the CTC blank.  None of these are real phones.
SPECIAL_IDS = frozenset({0, 1, 2, 3})
# A 320-sample total conv stride at 16 kHz makes every CTC frame exactly 20 ms.
TARGET_SR = 16_000
MS_PER_FRAME = 20


def _load_audio(path: Path, start_ms: int, end_ms: int) -> "Any":
    """Return the mono float32 waveform slice ``[start_ms, end_ms)`` at 16 kHz."""
    import numpy as np
    import soundfile as sf

    data, sr = sf.read(str(path), dtype="float32", always_2d=False)
    if getattr(data, "ndim", 1) > 1:  # stereo -> mono
        data = data.mean(axis=1)
    if sr != TARGET_SR:
        import librosa

        data = librosa.resample(data, orig_sr=sr, target_sr=TARGET_SR)
        sr = TARGET_SR
    start = max(0, int(start_ms * sr / 1000))
    stop = int(end_ms * sr / 1000) if end_ms > 0 else len(data)
    stop = min(max(stop, start), len(data))
    return np.ascontiguousarray(data[start:stop]), sr


def _collapse(pred_ids: list[int], max_probs: list[float], id_to_token: dict[int, str],
              offset_ms: int) -> list[dict[str, Any]]:
    """CTC-collapse frame argmaxes into sorted, non-overlapping phone spans."""
    phones: list[dict[str, Any]] = []
    index = 0
    total = len(pred_ids)
    while index < total:
        token_id = pred_ids[index]
        end_index = index
        while end_index + 1 < total and pred_ids[end_index + 1] == token_id:
            end_index += 1
        symbol = id_to_token.get(token_id)
        if token_id not in SPECIAL_IDS and symbol and symbol.strip():
            start_ms = offset_ms + index * MS_PER_FRAME
            end_ms = offset_ms + (end_index + 1) * MS_PER_FRAME
            span = max_probs[index : end_index + 1]
            confidence = sum(span) / len(span) if span else None
            entry: dict[str, Any] = {
                "symbol": symbol,
                "start_ms": int(start_ms),
                "end_ms": int(end_ms),
                "display_ipa": symbol,
            }
            if confidence is not None:
                entry["confidence"] = round(min(max(float(confidence), 0.0), 1.0), 4)
            phones.append(entry)
        index = end_index + 1
    return phones


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="wav2vec2 CTC phoneme sidecar")
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--start-ms", type=int, default=0)
    parser.add_argument("--end-ms", type=int, required=True)
    args = parser.parse_args(argv)

    import numpy as np
    import torch
    from transformers import Wav2Vec2ForCTC

    waveform, _ = _load_audio(args.audio, args.start_ms, args.end_ms)
    if waveform.size == 0:
        json.dump({"phones": []}, sys.stdout)
        return 0

    # Per-utterance zero-mean / unit-variance, matching Wav2Vec2FeatureExtractor.
    wave64 = waveform.astype("float64")
    normalized = (wave64 - wave64.mean()) / np.sqrt(wave64.var() + 1e-7)
    inputs = torch.from_numpy(normalized.astype("float32")).unsqueeze(0)

    model = Wav2Vec2ForCTC.from_pretrained(str(args.model_dir))
    model.eval()
    with torch.no_grad():
        logits = model(inputs).logits[0]  # [frames, vocab]
    probabilities = torch.softmax(logits, dim=-1)
    pred_ids = logits.argmax(dim=-1).tolist()
    max_probs = probabilities.max(dim=-1).values.tolist()

    vocab = json.loads((args.model_dir / "vocab.json").read_text(encoding="utf-8"))
    id_to_token = {int(token_id): token for token, token_id in vocab.items()}

    phones = _collapse(pred_ids, max_probs, id_to_token, args.start_ms)
    json.dump({"phones": phones}, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
