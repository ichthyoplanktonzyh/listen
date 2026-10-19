# Milestone 1 Completion

- Product version: 0.2.0
- Completion date: 2026-06-09
- Target: macOS Apple Silicon single-user MVP
- Status: Complete

## Delivered

Milestone 1 combines roadmap implementation stages M0-M6 and M8:

- clean-room Rust shared core, versioned contracts, SQLite migrations, and local
  loopback sidecar;
- local video/audio playback, seeking, rate, volume, tracks, progress recovery,
  and sentence looping;
- SRT/WebVTT parsing, large-timeline synchronization, transcript, offsets, and
  clickable primary subtitles;
- word status, context observations, dictionary lookup/cache, and explainable
  current-sentence diagnosis;
- simultaneous primary and secondary text subtitles;
- drag-and-drop import, versioned settings, and configurable subtitle
  appearance/layout;
- optional ffprobe/ffmpeg embedded text-subtitle extraction;
- optional yt-dlp resolution for legally accessible online media;
- ad-hoc signed macOS release package and automated packaged-app smoke tests.

## Deferred To Milestone 2 Or Later

- Windows and Linux desktop adapters;
- OpenSubtitles search and download;
- bitmap subtitle display, OCR, and learning interaction;
- mobile technical validation and clients;
- Whisper ASR, translation, cloud sync, and advanced review workflows;
- notarization and App Sandbox hardening for public distribution.

## Verification

Evidence is recorded in `docs/verification/`, especially:

- `m6-mvp-report.md`
- `m8-report.md`
- `m6-performance.md`
- `m6-fault-recovery.md`

The release artifact is generated at `dist/LLPlayerNext-macos-arm64.zip`.
