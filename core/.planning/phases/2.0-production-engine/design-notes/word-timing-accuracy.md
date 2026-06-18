# Word Timing Accuracy Milestone

## Goal

Recover audible pauses that coarse Whisper DTW token timestamps can hide, so
the existing acoustic-first chunk partitioner receives meaningful inter-word
gaps without changing the display partition contract.

## Problem

Whisper DTW emits token alignment points rather than reliable lexical word
intervals. The previous `dtw-v1` conversion also attached punctuation
timestamps to the previous word. A punctuation point aligned near the far side
of a pause could extend the previous word across that pause and make the
computed gap zero even when a listener clearly heard a break.

## Delivery Phases

### WTA-1: Preserve DTW Pause Space

- Ignore punctuation and special-token timestamps during lexical word merging.
- Give lexical DTW points a bounded local duration instead of zero-duration
  words.
- Publish the corrected conversion as `whisper.cpp@dtw-v2`.

### WTA-2: Local Audible-Pause Refinement

- Decode the transcription input as explicit mono PCM16 16kHz WAV.
- Search near each DTW boundary for a sustained low-energy interval.
- Move the adjacent word edges to the detected pause edges.
- Attribute only corrected adjacent words to
  `local-energy-pause-refiner@v1` with `timing_source = forced_aligned`.
- Emit no correction when audio is unsupported, no pause is found, or the
  candidate pause lies outside the adjacent word interval.

### WTA-3: Provider Precedence And Diagnostics

- Prefer `ForcedAligned` timings over coarse `AsrReported` timings while
  retaining `UserAdjusted` as the highest-priority source.
- Expose every stored inter-word gap and adjacent provider provenance at:

```text
GET /v1/subtitles/{track_id}/word-timing-diagnostics
```

## Completion Gate

- [x] Punctuation timestamps cannot consume a lexical pause.
- [x] A sustained audible pause can restore a gap from a coarse zero-gap
  boundary.
- [x] Refined timings override coarse ASR timings but not user adjustments.
- [x] Timing diagnostics expose final gap values and provider provenance.
- [x] Missing or unsupported audio safely retains DTW or estimated timings.

Existing tracks are intentionally not migrated in place. They must be
re-transcribed to receive `dtw-v2` and pause refinement.

## Remaining Calibration Work

The local energy detector is a conservative first deployable refinement, not a
general forced aligner. Real-media evaluation should compare the audible
pause, DTW v2 word edges, detected low-energy pause edges, final timing
diagnostics, and selected chunk boundary.

Future work may add adaptive noise-floor estimation, VAD, or a licensed
phoneme/word forced-alignment provider behind the same timing contract.
