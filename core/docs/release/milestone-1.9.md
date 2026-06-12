# Milestone 1.9 / 0.7.0

## Highlights

- Canonical en-US pronunciation with token-to-phoneme mapping and IPA display.
- Optional pinned CMUdict resource with deterministic offline fallback.
- Estimated word timings for ordinary SRT/VTT and local current-word highlight.
- Explicit timing source, provider, version, confidence, and degradation data.
- Rule-based weak form, contraction, linking, flapping, deletion, and
  assimilation hints with a prominent no-audio-detection disclaimer.
- Fixed 18-rule metadata catalog with examples, conditions, counterexamples,
  and stable IDs.
- Non-blocking track speech jobs with progress, cancellation, retry, and a
  10,000-sentence regression.
- Provider/version-isolated pronunciation caches and visible provider, timing,
  cache, and degradation diagnostics.
- Schema v8 and desktop settings v7 migrations.

## Known Limits

- Current whisper.cpp generated subtitles remain segment-timed; native ASR word
  timestamp ingestion is not enabled yet.
- Pronunciation fallback is deterministic and safe, but unknown names and
  non-English text may be approximate.
- Real audio phoneme analysis is deferred to Milestone 2.0.
