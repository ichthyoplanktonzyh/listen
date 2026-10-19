# ADR 0005: Desktop Enhancement Adapters

## Status

Accepted for M8.

## Decision

- Dual subtitles are two independent normalized `SubtitleTrack` timelines. The
  primary track owns learning interaction and diagnosis; the secondary track is
  display and seek capable but does not implicitly change primary learning data.
- Drag and drop delegates to the same media and subtitle import services used by
  file pickers.
- Embedded text subtitles are discovered with `ffprobe`, extracted with
  `ffmpeg`, and then imported through the existing subtitle core. Bitmap
  subtitle codecs are reported but are not converted or made interactive.
- Online URLs are resolved through an isolated `yt-dlp` process adapter. The
  resolved media URL is passed to the existing player adapter. The application
  does not bypass DRM, authentication, or access controls.
- M8 initially discovers user-installed external tools. Missing tools degrade
  only their optional feature and do not block local playback.

## Consequences

External-process timeouts, diagnostics, executable discovery, and future
bundling/licensing review become explicit release responsibilities. The shared
domain and high-frequency playback path remain independent of those tools.
