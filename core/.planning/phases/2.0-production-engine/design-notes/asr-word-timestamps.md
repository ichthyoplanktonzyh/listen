# ASR Word-Level Timestamps

> **Release:** 0.7.1  
> **Branch:** `feature/asr-word-timestamps`  
> **Status:** implemented and verified against bundled whisper.cpp v1.7.6

## Overview

When whisper.cpp transcribes audio for ASR-generated subtitles, it now emits
per-token DTW (Dynamic Time Warping) timestamps via the `-ojf` JSON-full
output. These timestamps are merged into lexical words, stored with
`timing_source = asr_reported`, and consumed by the existing Flutter
current-word highlighting pipeline.

Before this feature, ASR-generated tracks used the **deterministic weighted
estimator** (same as ordinary SRT/VTT files), producing lower-fidelity word
sync. Now ASR-produced subtitles carry **actual audio-aligned word boundaries**
from the cross-attention DTW alignment, giving users visibly tighter current-word
tracking.

## Technical Approach

### Pipeline

```
whisper-cli -ojf -dtw <model_preset> audio.wav
  │
  ├─ output.srt   ──→  subtitle_core::import  ──→  SubtitleTrack (sentences + tokens)
  │
  └─ output.json  ──→  asr_timing::extract_word_timings_from_json()
                         ├─  parse WhisperSegment[] + WhisperToken[].t_dtw
                         ├─  merge lexical subword tokens → words
                         ├─  ignore punctuation timestamps
                         ├─  validate word count matches sentence tokens
                         ├─  validate boundary & monotonicity constraints
                         ├─  produce DTW v2 Vec<WordTiming>
                         ├─  optionally merge research forced alignment
                         └─  refine audible pauses from local PCM WAV
                                │
                                └─→  store_word_timings()
                                      │
                                      └─→  Flutter currentWordTokenIndex()
                                           (no changes needed)
```

### DTW Alignment Algorithm

whisper.cpp v1.5.5+ implements token-level DTW as described in
[PR #1485](https://github.com/ggml-org/whisper.cpp/pull/1485):

1. During autoregressive decoding, the decoder's cross-attention layers
   produce query-key (QK) weight matrices mapping output tokens to encoder
   audio frames.
2. A pre-defined set of **alignment heads** (per-model, e.g. `WHISPER_AHEADS_BASE_EN`)
   is selected; other heads are discarded.
3. The QK weights are scaled, clipped, normalized, and median-filtered.
4. Dynamic Time Warping finds the optimal monotonic alignment path through
   the attention matrix.
5. The path yields a mel-frame index per output token, converted to
   `t_dtw` in centiseconds (divide by 100 for seconds).

This is the C++ equivalent of the algorithm used by `faster-whisper`'s
`word_timestamps=True` (SYSTRAN/CTranslate2) and `whisper-timestamped`
(linto-ai/DTW on cross-attention weights). It requires **no additional
model** — alignment information comes from the Whisper model's own
internal attention.

### Subword → Word Merging

Whisper's tokenizer splits some words into subword units (e.g.,
`" playing"` → `[" play", "ing"]`). The merging logic:

| Token pattern | Action |
|---|---|
| Starts with space or newline | Begins a new word |
| No leading space and lexical content | Appends to the current word |
| First token in segment | Always begins the first word |
| Punctuation or special token | Ignored for word edges |

A word's `start_ms` is the first lexical subword's `t_dtw × 10`. DTW v2 gives
the final lexical point a bounded 80ms duration, capped by the next word, so
single-token words are not zero-duration and punctuation cannot consume a
following pause.

Repeated DTW points are separated deterministically by one millisecond. If the
sentence is too short to create a positive interval for every word, the
sentence falls back to estimation.

Previously stored zero-length ASR timing rows are treated as an invalid cache
and automatically replaced by the deterministic estimator when read.

### DTW Preset Mapping

The `-dtw` parameter value must match the model. The mapping uses
`model.display_name` directly:

| Model file | DTW preset |
|---|---|
| `ggml-base.en.bin` | `base.en` |
| `ggml-small.en.bin` | `small.en` |
| `ggml-medium.en.bin` | `medium.en` |
| `ggml-base.bin` | `base` |
| `ggml-small.bin` | `small` |
| `ggml-medium.bin` | `medium` |
| `ggml-large-v3.bin` / quantized variants | `large.v3` |
| `ggml-large-v3-turbo.bin` / quantized variants | `large.v3.turbo` |
| Custom whisper.cpp models with an unknown stock preset | DTW disabled |

### Graceful Degradation

The extraction fails safely at multiple levels:

| Condition | Behavior |
|---|---|
| JSON unreadable or unparseable | Skip DTW; transcript completes with estimation |
| Segment count ≠ sentence count | Skip DTW for all sentences |
| Word count or normalized text mismatch | Fall back to estimation for that sentence |
| Cannot construct non-empty intervals | Fall back to estimation for that sentence |
| Timing outside sentence boundary | Skip that sentence |
| Non-monotonic word sequence | Skip that sentence |
| Any unavailable lexical token changes the word mapping | Skip that sentence |
| whisper.cpp model name cannot be mapped to a stock DTW preset | DTW flag not passed to whisper-cli |

In all cases, **transcription succeeds** and the track is imported. Missing
ASR timings simply fall back to the existing weighted estimator.

Tracks generated before DTW v2 are not rewritten automatically. Re-transcribe
an existing track to receive punctuation-safe DTW edges and local pause
refinement.

### Research Forced Alignment

When the local research venv exists, transcription can optionally run the
torchaudio MMS_FA sidecar between DTW extraction and pause refinement. The
sidecar is documented in [Forced Alignment Research Mode](forced-alignment.md).
It is not bundled with the app; missing or failed sidecar execution preserves
the DTW v2 timing vector unchanged.

## Code Layout

```
crates/speech-analysis/src/asr_timing.rs    # NEW — JSON parse + subword merge + WordTiming
crates/speech-analysis/src/lib.rs            # +pub mod asr_timing
crates/speech-analysis/Cargo.toml            # +serde_json, +thiserror
crates/api-http/src/transcription.rs         # -ojf, -dtw flags; extraction call
crates/api-http/Cargo.toml                   # +speech-analysis dep
crates/application/src/lib.rs                # reject unusable zero-length timings
```

No persistence schema or Flutter display changes are required.

### Audible-Pause Refinement

During transcription, the existing local WAV is explicit mono PCM16 at 16kHz.
`local-energy-pause-refiner@v1` searches near each DTW word boundary for at
least 120ms below -38 dBFS. When a pause lies inside the adjacent word
interval, only those two word edges move to the pause edges and receive
`timing_source = forced_aligned`.

The refiner is optional and failure-safe. Unsupported WAV data or missing
pauses retain DTW v2 timings.

## Design Decisions

### Why DTW and not forced alignment (WhisperX)?

| Factor | DTW (chosen) | Forced Alignment (WhisperX) |
|---|---|---|
| Extra model | None | Language-specific wav2vec2 |
| Tech stack | Pure Rust/C++ | Requires Python/PyTorch |
| Build | Already in whisper-cli binary | Would need new runtime |
| Accuracy | ±0.1–0.3s (good for word highlight) | ±0.05–0.15s |
| Multi-language | Inherits Whisper 99 languages | One model per language |

DTW is sufficient for current-word highlighting. Forced alignment may be
revisited in Milestone 2.0 if phoneme-level analysis demands higher precision
and the license/distribution constraints of wav2vec2 models are resolved.

### Why not faster-whisper?

faster-whisper (Python/CTranslate2) offers equivalent DTW quality but
introduces a Python runtime dependency incompatible with the LLPlayerNext
Rust + C++ shipping constraint.

### Why inline in transcription.rs instead of a new service?

The extraction is a pure function of (JSON bytes, sentences). It has no
side effects, no state, and runs once per transcription job. A standalone
module in `speech-analysis` is the right abstraction; the call site in
`transcription.rs` is a single `if` block that reads the JSON file and
passes it through.

## Verification

- `speech_analysis::asr_timing` covers subword merge, special-token filtering,
  repeated DTW points, lexical mismatch, and per-sentence fallback.
- The integration fixture includes whisper's real `[_BEG_]` / `[_TT_*]`
  structure, and a regression test uses a reduced bundled-runtime JFK output.
- The existing M1.9 word-timing API tests (`verify-m19.sh`) pass unchanged,
  confirming refined timing priority and estimation fallback are preserved.
- Full `cargo test --workspace`, strict workspace `cargo clippy`, Flutter
  analyze/test, and contract validation pass.

Manual functional testing: open a video, run ASR transcription with a
whisper-family model, and observe that current-word highlighting tracks
audio more precisely than with an ordinary SRT file. The word-timing
diagnostics show the final gap and whether adjacent words use
`whisper.cpp@dtw-v2` or `local-energy-pause-refiner@v1`.

## Known Limitations

1. **n_processors > 1**: whisper.cpp parallel processing breaks DTW timestamps
   (issue #2036). The current invocation uses default `n_processors=1`.
2. **Flash attention**: DTW is silently disabled when `-fa` is used. Not
   applicable to the current configuration.
3. **Custom models**: whisper.cpp custom models enable DTW when their
   registered path or display name maps to a stock preset, including common
   quantized filenames such as `ggml-large-v3-q5_0.bin`. Unknown custom names
   still degrade to transcript-only SRT import.
4. **Token alignment precision**: DTW gives point timestamps. Word intervals
   end at the next word start (or sentence end), which is appropriate for
   continuous highlighting but may need refinement for M2.0 phoneme alignment.

## Future Work (M2.0)

M2.0 phoneme-level analysis requires tighter word boundaries. Options:
- Evaluate DTW quality on the Phase 0 evaluation set; quantify word-boundary
  error against a forced-alignment baseline.
- If DTW precision is insufficient, consider adding a wav2vec2 forced-alignment
  pass for languages where a compatible model is available and licensed.
- The `Phoneme.start_ms/end_ms` fields and `ForcedAligned` timing source are
  already defined in the domain model, ready for a higher-precision provider.

## References

- [whisper.cpp PR #1485 — Token-level timestamps with DTW](https://github.com/ggml-org/whisper.cpp/pull/1485)
- [faster-whisper word_timestamps documentation](https://github.com/SYSTRAN/faster-whisper)
- [WhisperX — Forced alignment with wav2vec2](https://github.com/m-bain/whisperX)
- [whisper-timestamped — DTW on cross-attention weights](https://github.com/linto-ai/whisper-timestamped)
- [VideoCaptioner (卡卡字幕) — faster-whisper word timestamps in production](https://github.com/LaffeyOvO/VideoCaptioner)
- [ADR 0007 — Pronunciation and Word Timing Foundations](../decisions/0007-pronunciation-and-word-timing.md)
- [Milestone 1.9 Planning](../planning/milestone-1.9.md)
