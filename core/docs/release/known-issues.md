# MVP Known Issues

- The release is ad-hoc signed and not notarized; first launch can require
  Control-click **Open**, and newly built independently extracted apps may be
  rejected entirely on the current development Mac. Use `flutter run` for
  functional testing until Developer ID signing/notarization is implemented.
- The macOS app sandbox remains disabled because the MVP launches a bundled
  sidecar and opens user-selected media. Harden sandboxing before public
  distribution.
- The macOS player uses fvp/libmdk with VideoToolbox and Metal after Xcode 26.5
  exposed black frames in media_kit_video's deprecated OpenGL path. AV1
  playback was confirmed working during Milestone 1.9 collaborative
  acceptance.
- The fvp/libmdk binary SDK distribution and commercial-use terms require final
  review before public distribution.
- Free Dictionary API requires internet for uncached words, has no service-level
  guarantee, and its content provenance needs confirmation before commercial
  distribution.
- Lemma normalization combines deterministic rules and optional ECDICT data;
  uncommon forms can still require a user correction.
- Windows and Linux adapters are intentionally postponed until after MVP.
- M8 online playback and user-initiated download require an installed `yt-dlp`;
  extractor behavior can change when supported websites change. Downloads run
  in the background, prefer H.264/M4A sources, and use the bundled `ffmpeg` to
  merge separate streams into one MP4.
- M8 embedded learning-subtitle import requires user-installed `ffprobe` and
  `ffmpeg`. Text subtitle codecs are supported; bitmap subtitle display and OCR
  learning interaction remain deferred.
- OpenSubtitles requires a user-supplied API key and remains subject to provider
  authentication, quotas, availability, and terms.
- Pronunciation audio is available only when an enabled dictionary provider
  supplies a playable audio resource.
