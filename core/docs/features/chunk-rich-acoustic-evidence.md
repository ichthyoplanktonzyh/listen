# Rich Acoustic Chunk Evidence

Milestone C3 adds independent evidence providers to the stable chunk partition
pipeline. Providers emit boundary evidence; they never construct display
chunks or alter the Flutter contract.

## Providers

### Pre-Boundary Lengthening

Provider: `word-duration-lengthening@v1`

For each possible word boundary, the provider compares the duration of the
left word with a robust median from nearby real-timed words. It emits positive
evidence when:

- both adjacent words have non-estimated timing;
- enough nearby real-timed reference words exist;
- the left word exceeds a minimum duration;
- the duration ratio crosses the configured threshold.

This cue can create a boundary without a large pause. Coarse Whisper DTW
timings often produce zero-duration words and therefore safely emit no
lengthening evidence. Forced-aligned or user-adjusted timings are preferred.

### Filled-Pause Hesitation

Provider: `filled-pause-hesitation@v1`

This conservative provider emits negative evidence around ASR-recognized
filled pauses such as `uh`, `um`, `erm`, `hmm`, and `mm`. It reduces ordinary
pause false positives but does not erase a very large, otherwise decisive
pause.

This is explicitly a filled-pause context signal. It does not claim to detect
breathing from audio.

## Failure And Fallback

Providers run synchronously over the already-loaded sentence word timings.
They perform no audio decoding, model loading, persistence, or playback-thread
work.

When timings are estimated, context is insufficient, or providers are disabled,
they emit no evidence. The partitioner then reproduces C2 acoustic-gap, text,
punctuation, and readability behavior.

## Diagnostics And Calibration

Inspect provider evidence through:

```text
GET /v1/subtitles/{track_id}/chunk-diagnostics
```

The C3 calibration corpus is:

```text
testdata/chunk/v3-rich-acoustic.json
```

The C4 learned provider follows the same evidence-first architecture. Future
pitch, energy, breath, alignment, or learned providers should remain
provider-attributed and leave the product-facing `SentenceChunkPartition`
contract unchanged.
