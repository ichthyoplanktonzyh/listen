# macOS M0 Verification Checklist

Target: Apple Silicon macOS.

| Capability | Flutter + media_kit | Tauri + libmpv |
|---|---|---|
| Build and launch | Pass | Pass |
| Open generated video | Pass | Pass |
| Open generated audio | Pass | Implemented; manual check pending |
| Video rendering | Pass: embedded Flutter texture | Fail: separate mpv window |
| Play/pause/stop | Pass | Implemented; manual check pending |
| Position and duration events | Pass | Implemented; manual check pending |
| Forward/backward seek | Pass | Implemented; manual check pending |
| Playback rate and volume | Pass: adapter methods available | Implemented; manual check pending |
| Track discovery | Pass | Implemented; manual check pending |
| Interactive subtitle overlay | Pass | Fail: overlay is not above separate mpv window |
| Cue interval loop | Pass | Implemented; manual check pending |
| Packaged app launch | Pass | Pass after prototype dylib fixup |

Record measured position-event cadence, seek error, loop-boundary error, known
issues, and the exact dependency versions before approving a candidate.

## 2026-06-09 Result

- Flutter 3.44.1, Dart 3.12.1, media_kit 1.2.6, Xcode 26.5.
- Flutter analysis, local timeline tests, and Release macOS build pass.
- Runtime inspection confirms a single Flutter window, bundled `Mpv.framework`,
  and embedded video rendering without a separate mpv window.
- Runtime diagnostics confirm generated video and audio open successfully,
  position events advance, tracks are discovered, subtitle-overlay seek reaches
  3000 ms, and the 3000-4800 ms cue loop returns to 3000 ms.
- Tauri 2.11.2, tauri-plugin-libmpv 0.3.2, mpv 0.41.0.
- Tauri frontend, Rust adapter, App, and DMG build successfully.
- Runtime probe confirms libmpv loads and opens `sample-video.mp4`.
- Runtime window inspection shows one Tauri window and a separate mpv window.
  The required interactive subtitle overlay cannot cover that separate window.

M0 has reached its macOS-first exit gate. Flutter + media_kit is selected.
Tauri + libmpv is rejected in its current form.

## Known risks

- Current media_kit macOS plugins still use CocoaPods and warn that Swift
  Package Manager support is missing.
- The M0 prototype disables App Sandbox to load generated fixtures directly.
  The product implementation must use a file picker and security-scoped access.
- Packaging, signing, and notarization remain M6 work.
