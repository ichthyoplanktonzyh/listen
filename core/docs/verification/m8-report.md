# M8 Desktop Enhancement Verification

## Scope

M8 implements the first five approved LLPlayer experience enhancements:

- simultaneous primary and secondary text subtitles;
- subtitle appearance, placement, transcript-width, offset, and external-tool settings;
- media and subtitle drag and drop;
- embedded text-subtitle extraction through optional `ffprobe` and `ffmpeg` adapters;
- online-media URL resolution through an optional `yt-dlp` adapter.

OpenSubtitles and bitmap-subtitle display/OCR interaction remain deferred.

## Behavioral Boundaries

- The primary subtitle owns token interaction, word status, sentence loop,
  transcript, and diagnosis.
- The secondary subtitle has its own timeline, visibility, offset, style, and
  click-to-seek behavior.
- Bitmap embedded tracks are disclosed but cannot be imported as learning text.
- Missing external tools only disable their optional feature.
- Online-media resolution does not bypass authentication, DRM, access control,
  or site policy.

## Verification

- Flutter analyzer and tests cover settings migration, dual-timeline primitives,
  configured external-tool execution, and bitmap rejection.
- The packaged macOS smoke test continues to cover local video/audio, long
  subtitle import, progress recovery, bundle signing, and bundled sidecar.
- Manual runtime acceptance should use a local MKV with an embedded text track
  and a legally accessible URL supported by the user's installed `yt-dlp`.
