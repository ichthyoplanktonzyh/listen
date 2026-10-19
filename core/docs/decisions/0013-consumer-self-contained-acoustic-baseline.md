# ADR 0013: Consumer Self-Contained Acoustic Baseline

Status: Accepted

Date: 2026-07-01

## Context

LLPlayerNext has a lightweight consumer track and a heavier production/sidecar
track. The earlier boundary treated several audible-structure features as
production-only, which allowed a local whisper.cpp transcription to have word
timestamps while still missing downstream Listening structure.

RMS energy and classical F0 extraction do not require Python, PyTorch, a model
checkpoint, or a heavy forced aligner. Keeping them sidecar-only made feature
availability depend on deployment shape rather than computational weight.

## Decision

The lightweight consumer must form a complete lower-precision learning ecosystem.

- Bundled whisper.cpp word timing must unlock every baseline feature that depends
  on WordTimeline, including word sync, chunk analysis, and RhythmFrame.
- `AsrReported` timing is audio-backed but coarse. `Estimated` timing remains the
  text-only category.
- The Rust local service owns lightweight PCM analysis used by the baseline:
  pause refinement, per-word RMS energy, F0/pitch prominence, and pitch reset.
- Acoustic cues are persisted through the versioned
  `rhythm_word_acoustic_cues` artifact before temporary transcription audio is
  deleted.
- Flutter renders typed results and does not perform DSP.
- Python/WhisperX/MFA/CTC and future model-backed providers remain optional quality
  upgrades. They may replace or enrich the same timeline and acoustic contracts.
- Manual product QA calibrates thresholds and guards regressions; it does not gate
  whether lightweight RMS/F0 capability exists in the consumer baseline.

## Consequences

- Local transcription errors that prevent WordTimeline or acoustic artifact
  persistence are surfaced instead of silently discarded.
- RhythmFrame provenance can include `timing`, `energy`, and `pitch` without phone
  evidence or a Python runtime.
- The distributed application gains modest CPU work after transcription, bounded
  by word windows and capped F0 frames, but no additional model dependency.
- Sidecars are evaluated by quality improvement rather than by whether a feature
  becomes available at all.

## Rejected Alternatives

- Keep RMS/F0 production-only: rejected because it makes lightweight feature
  availability incomplete for reasons unrelated to model weight.
- Put DSP in Flutter: rejected because analysis belongs in the Rust application
  boundary and should be reusable by HTTP, future FFI, and tests.
- Wait for manual QA before implementing F0: rejected as an adoption gate. QA
  remains necessary for calibration and release confidence.
