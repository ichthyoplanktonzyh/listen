# Milestone 1.8 Acceptance Report

Status: **awaiting collaborative manual acceptance**

## Automated Gates

- [x] Rust formatting, tests, and clippy
- [x] Flutter analysis and widget tests
- [x] Contract validation and historical verification
- [x] M1.8 lexical/provider verification
- [x] macOS Apple Silicon package and smoke test

## Manual Acceptance

Record each item as pass, fail, or pending:

1. Existing playback, dual subtitles, learning panel, notes, and ASR work.
2. Existing `0.5.0` assets survive schema v7 migration and v3 export/import.
3. Common `go` forms normalize correctly and a user correction survives restart.
4. A phrase candidate requires confirmation, can differ from its component
   words, and retains its source sentence and token range.
5. ECDICT and CMUdict show provenance, install explicitly, and remove safely.
6. OpenSubtitles title, filename, and media-hash searches work; downloads import
   as primary and secondary learning tracks.
7. Invalid credentials or no network do not affect playback, and the API key
   is absent from logs and asset exports.
8. Chinese/English UI and the packaged app behave normally.

The release commit and `v0.6.0` tag remain blocked on user confirmation.
