# Milestone 1.8 Completion

- Product version: 0.6.0
- Completion date: 2026-06-12
- Target: macOS Apple Silicon learning-quality release
- Status: Complete with documented AV1 playback limitation

## Delivered

- Unified durable word and phrase learning assets with schema v7 and asset v3.
- Phrase candidates and explicit phrase learning interactions in subtitles.
- Provider-neutral lexical normalization with optional ECDICT and CMUdict
  resources.
- OpenSubtitles search, download, and primary/secondary subtitle import.
- Provider-supplied pronunciation audio that does not interrupt video playback.
- Migration from media_kit's deprecated macOS OpenGL path to
  video_player/fvp/libmdk with VideoToolbox and Metal.
- Background yt-dlp downloads with progress, cancellation, H.264 preference,
  and bundled-ffmpeg audio/video merge.
- Playback progress restoration before playback starts, avoiding a visible
  jump from the beginning.

## Playback Limitation At M1.8 Closure

At M1.8 closure, the reported AV1 MP4 and 4K WebM samples could still produce
audio with a black video frame through the current fvp/libmdk path. The
investigation branch
`fix/webm-vp8-vp9-decoders` is retained as evidence, but its custom FFmpeg
replacement is not part of this release because it did not fix the actual AV1
sample and introduced packaging and ABI risk.

Milestone 1.9 collaborative acceptance subsequently confirmed that the
reported AV1 video now displays normally. The following were the M1.8
workarounds and are retained for historical context:

- Prefer the application's H.264/M4A yt-dlp download selection.
- For incompatible local AV1 media, create an H.264 compatibility copy.
- Revisit after an upstream fvp/libmdk fix or a separately planned native-player
  evaluation. Do not spend Milestone 1.9 capacity on this investigation.

## Verification

- The original collaborative 20-item checklist passed.
- Ordinary local video playback was confirmed after the final player migration.
- Rust, Flutter, contracts, historical regressions, M1.8 verification, package
  build, signing, sanitized rpaths, and packaged-app smoke tests passed.
- Detailed evidence is recorded in
  `docs/verification/milestone-1.8-acceptance.md`.
