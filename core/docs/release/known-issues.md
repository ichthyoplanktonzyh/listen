# MVP Known Issues

- The release is ad-hoc signed and not notarized; first launch can require
  Control-click **Open**.
- The macOS app sandbox remains disabled because the MVP launches a bundled
  sidecar and opens user-selected media. Harden sandboxing before public
  distribution.
- media_kit macOS packages currently use CocoaPods and emit a future Swift
  Package Manager compatibility warning.
- Free Dictionary API requires internet for uncached words, has no service-level
  guarantee, and its content provenance needs confirmation before commercial
  distribution.
- The first lemma strategy is lowercase normalization, not linguistic
  lemmatization.
- Windows and Linux adapters are intentionally postponed until after MVP.
- M8 online playback requires a user-installed `yt-dlp`; extractor behavior can
  change when supported websites change.
- M8 embedded learning-subtitle import requires user-installed `ffprobe` and
  `ffmpeg`. Text subtitle codecs are supported; bitmap subtitle display and OCR
  learning interaction remain deferred.
- OpenSubtitles search and download remain deferred.
