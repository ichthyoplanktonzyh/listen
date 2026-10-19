# macOS Apple Silicon MVP Verification

- Version: 0.1.0
- Date: 2026-06-09
- Result: Passed with documented distribution limitations

## Core Flow

The signed packaged application was launched with its bundled arm64 Rust
sidecar. Automated smoke verified:

1. Open and play generated local video.
2. Import and persist a 2,100-cue SRT timeline.
3. Position-driven current subtitle and transcript rendering.
4. Persist positive playback progress on the five-second timer.
5. Restart with the same database without duplicate media or subtitle tracks.
6. Open and play pure audio without learning features.
7. Verify the app bundle signature and bundled sidecar.

Visual runtime inspection confirmed embedded video, clickable subtitle overlay,
current transcript highlight, sentence diagnosis, controls, rate, audio-track
selection, and subtitle/word-style toggles.

## Release Artifact

`dist/LLPlayerNext-macos-arm64.zip` contains `LLPlayerNext.app` and its bundled
`api-http` sidecar. Installation, backup/recovery, performance, fault recovery,
and known issues are documented under `docs/release/` and
`docs/verification/`.

## Manual Acceptance Note

The repository contains license-clear synthetic media rather than CNN/NBC
material. The complete daily-training flow was verified with those fixtures.
Before broader distribution, repeat visual acceptance with the user's own
long-form news video; this does not block the personal macOS MVP artifact.
