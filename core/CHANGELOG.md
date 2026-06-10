# Changelog

## 0.5.0 - 2026-06-10

Milestone 1.7 local ASR learning subtitle release.

- Provider-, runtime-, model-, and profile-neutral transcription contracts.
- Durable single-concurrency whole-media jobs with progress, cancellation,
  retry, restart interruption handling, provenance, and idempotent completion.
- whisper.cpp model catalog, explicit verified downloads, custom model
  registration, model management, and persistent job center.
- Generated subtitles become ordinary interactive learning tracks and support
  SRT export.
- Reproducible macOS arm64 whisper.cpp and LGPL-only FFmpeg runtime build,
  license validation, application bundling, and deterministic fake-runtime
  acceptance test.

## 0.4.1 - 2026-06-10

- Draggable viewport-relative subtitle placement, independent primary/secondary
  font controls, and a stable video viewport when subtitle visibility changes.
- Restored the media-kit video texture layout after the subtitle overlay
  refactor, fixing the black video screen regression.

## 0.4.0 - 2026-06-10

Milestone 1.6 desktop learning experience release.

- Responsive subtitle presets and automatic native-subtitle suppression.
- Simplified Chinese and English desktop localization.
- TXT/CSV existing vocabulary import with conflict-safe status initialization.
- Unified word learning panel with durable user definitions and notes.
- Provider-agnostic aggregated dictionary API and multi-source UI.

## 0.3.0 - 2026-06-10

Milestone 1.5 vocabulary learning asset release.

- Status-driven vocabulary books with user-selected status as the authority.
- Durable status history and source sentence snapshots.
- Missing-media recovery and independent vocabulary asset backup/restore.
- Latest-effective context observations with clear support.
- Schema v4 migration with legacy history and source backfill.

## 0.2.0 - 2026-06-09

Milestone 1 macOS Apple Silicon MVP.

### Added

- Local video/audio playback and complete subtitle-learning loop.
- SRT/WebVTT import, interactive transcript, sentence navigation and loop.
- Word status, dictionary lookup, context observations, and diagnosis.
- Dual text subtitles with independent offsets.
- Drag-and-drop import and configurable subtitle appearance/layout.
- Embedded text-subtitle extraction through optional ffprobe/ffmpeg.
- Online-media URL resolution through optional yt-dlp.
- Versioned local settings, progress recovery, diagnostics, and release package.

### Deferred

- Windows/Linux, OpenSubtitles, bitmap subtitle interaction, mobile, ASR, and
  translation.
