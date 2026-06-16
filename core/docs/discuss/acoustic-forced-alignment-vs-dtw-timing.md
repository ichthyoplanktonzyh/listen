# Acoustic Forced Alignment vs DTW Token Timing

## Background

LLPlayerNext currently uses whisper.cpp DTW (Dynamic Time Warping) v2 timestamps
for word-level subtitle highlighting. While this works correctly in most cases,
occasional timing drift has been observed in real-video testing. This prompted
an exploration of whether direct acoustic analysis could yield more reliable
time alignment.

## Current Approach: DTW Token Timing

DTW timestamps are derived from whisper's internal cross-attention weights:

```
whisper encoder hidden states → cross-attention to audio frames → DTW smoothing → word timings
```

**What it measures**: where the model *attended* in the audio when producing each
output token.

**Strengths**:
- Zero additional cost (built into whisper.cpp `-dtw` output)
- Accurate in the majority of cases
- Requires no additional models, dependencies, or inference

**Weaknesses**:
- Attention position ≠ physical sound position. The model may attend semantically
  (e.g., context before the word) rather than acoustically to the exact phoneme
- Drift occurs with fast speech, minimal pauses, or overlapping speakers
- Single-point failure: if encoder attention is imprecise for a token, no
  downstream correction exists

## Proposed Approach: Acoustic Forced Alignment

Forced alignment directly processes the audio waveform to locate phoneme boundaries:

```
audio waveform → frame segmentation → MFCC/filterbank features → acoustic model
→ per-frame phoneme probabilities → Viterbi/CTC decoding constrained by known text
→ phone-level timestamps
```

**What it measures**: where each phoneme *physically occurs* in the audio signal,
based on spectral features (formants, energy, transitions).

**Strengths**:
- Higher precision: phone-level accuracy typically within 10–20 ms
- Works independently of any ASR model's internal state
- Well-established in linguistics (Montreal Forced Aligner, Kaldi, CTC-based aligners)
- Can produce time-aligned IPA phone timelines that track connected-speech phenomena

**Weaknesses**:
- Requires additional model inference (compute cost)
- Sensitive to background noise and non-standard pronunciation
- Adds a dependency on an alignment model/runtime
- Phone-level alignment is more expensive than word-level (more tokens to align)

## Key Insight: Physical vs Representational Time

| | DTW (current) | Forced Alignment (proposed) |
|---|---|---|
| **Input** | Cross-attention weight matrix (model-internal) | Raw audio samples → acoustic features (physical) |
| **Space** | Model representation space (e.g., 768-dim vectors) | Acoustic space (spectrum, formants, energy) |
| **Analogy** | Watching where eyes land on a page to infer reading position | Listening to the sounds coming out of the mouth |
| **Nature** | Indirect inference from model state | Direct measurement from physical signal |

The core argument: acoustic forced alignment operates at the physical layer. Audio
waveforms are the closest representation to the actual speech event — they capture
the air vibrations that constitute speech. DTW operates in a representational
layer that is optimized for semantic understanding, not temporal precision.

## Architecture Alignment

The codebase already has the data model foundation for this direction:

- `crates/speech-analysis/src/phonetic_alignment.rs` — phone alignment structures
  (already exists alongside DTW's `asr_timing.rs`)
- `crates/speech-analysis/src/phonetic_findings.rs` — detected-phone findings
  with start/end timestamps
- `DetectedPhone` — per-phone `start_ms` / `end_ms` / `phone_set` / `stress`

This means the database already stores phone-level timestamps. The gap is in
the *source* of those timestamps (currently estimated, could be replaced by
forced alignment output).

## Phone-Level Visual Highlighting

A related goal: IPA phone displays should highlight synchronously with audio
playback, at phone-level granularity rather than word-level.

**Current state**: phones are rendered as a static string per sentence.

**Target state**: each phone is an individual widget; the active phone (matching
playback position) is visually distinct.

**What's already in place**:
1. `subtitle_controller.currentDetectedPhone` / `currentDetectedPhoneAt(ms)` —
   binary search over phone timeline to find the active phone at a given
   playback position
2. `player` emits `currentPosition` events — the same stream that drives
   word-level subtitle highlighting
3. `DetectedPhone` has `start_ms` / `end_ms` fields

**What needs to change**:
1. UI layer: split the phone display string into individual phone widgets
   (one per `DetectedPhone`), rather than rendering as a single text span
2. Highlight logic: apply active/inactive styling based on the current
   phone index, using the same `currentDetectedPhoneAt(ms)` lookup that
   already exists
3. This is architecturally identical to word-level highlighting, just at
   phone granularity

## Recommended Path

1. **Keep DTW as the default** — covers 90%+ of cases at zero cost
2. **Integrate a lightweight forced aligner** — options include:
   - CTC-based: reuse whisper encoder hidden states + CTC decoding with text constraint
   - Dedicated: `ctc-forced-aligner`, `torchaudio` forced alignment, or whisper's
     own cross-attention outputs reinterpreted through a CTC lens
   - Traditional: Montreal Forced Aligner (MFA) via subprocess
3. **Trigger selectively** — re-align only sentences where DTW confidence is low,
   or offer user-initiated "precise timing" mode
4. **Combine sources** — DTW provides a prior distribution; forced alignment
   refines boundaries; phone-level timestamps from either source feed the
   same `DetectedPhone` structure

## References

- McAuliffe et al., "Montreal Forced Aligner: Trainable Text-Speech Alignment
  Using Kaldi" (Interspeech 2017)
- Kürzinger et al., "CTC-Segmentation of Large Corpora for German End-to-End
  Speech Recognition" (SPECOM 2020)
- The current `phonetic_alignment.rs` and `phonetic_findings.rs` modules in
  `crates/speech-analysis/src/`
- DTW v2 discussion in `docs/features/asr-word-timestamps.md`
