# ADR 0007: Pronunciation and Word Timing Foundations

## Status

Accepted for Milestone 1.9 / version 0.7.0.

## Decision

- Public pronunciation, phoneme, rule, and timing contracts remain provider-neutral.
- The first canonical pronunciation provider is the pinned CMU Pronouncing
  Dictionary (`74790861`) with a deterministic fallback when the optional
  resource is unavailable or a word is unknown.
- Internal English canonical phonemes use ARPAbet with lexical stress. The UI
  uses a replaceable ARPAbet-to-IPA mapping.
- Word timing priority is `asr_reported`, `forced_aligned`, `estimated`, then
  `user_adjusted` where a user override explicitly replaces another source.
- Ordinary SRT/VTT cues use a deterministic weighted estimator. Results are
  monotonic, bounded by the cue, and always marked `estimated`.
- Connected-speech hints are deterministic text/context rules. They never claim
  to detect a realization in the audio.

## Spike Findings

- Existing subtitle tokens have stable sentence-local indices and map cleanly
  to word timings and phonemes without changing the subtitle identity model.
- Playback position is already maintained locally in Flutter, so current-word
  selection can remain off the HTTP path.
- The pinned CMUdict resource includes ARPAbet stress digits and a permissive
  BSD-style license. Optional installation was already implemented in M1.8.
- whisper.cpp can expose token timestamps, but the current M1.7 invocation
  imports generated SRT segments only. M1.9 therefore does not label generated
  tracks as word-timed; ASR word timestamp ingestion remains an optional future
  provider improvement.

## Consequences

- Missing CMUdict never blocks playback or subtitle interaction.
- Provider/version changes can invalidate rebuildable analysis rows in schema
  v8 without touching vocabulary assets.
- Actual audio phoneme recognition and claims such as `detected_in_audio`
  remain Milestone 2.0 work.
