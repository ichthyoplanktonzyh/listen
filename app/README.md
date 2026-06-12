# LLPlayerNext Desktop

Formal macOS Apple Silicon desktop client using Flutter and fvp/libmdk.

During development, build the Rust sidecar first and run Flutter from the
repository root so the client can discover `target/debug/api-http`:

```sh
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH"
cargo build -p api-http
cd apps/desktop
flutter run -d macos
```

This is also the standard functional-test fallback when macOS signing or AMFI
prevents a newly built `.app` from launching. It does not replace packaged-app
smoke verification. See
`../../docs/development/macos-functional-testing.md`.

The player adapter, position events, subtitle cursor, seeking, offset, and
sentence loop all run locally in the client. The loopback sidecar owns subtitle
import, persistence, progress, word state, dictionary, and diagnosis services.

## Enhanced desktop workflow

- Use **Primary subtitle** for the interactive learning track.
- Use **Secondary subtitle** for the second independently synchronized text
  track.
- Drop a media file plus up to two SRT/VTT files onto the window to open them
  together.
- Use the overflow menu to import a supported embedded text subtitle, configure
  subtitle appearance/layout, or export logs.
- Use **Open URL** to resolve and play, or explicitly download, a legally
  accessible page URL with an installed `yt-dlp`. Downloads continue in the
  background while the player remains usable; the bundled `ffmpeg` merges
  separate video and audio streams into one final MP4.

Embedded text-subtitle extraction requires installed `ffprobe` and `ffmpeg`.
The application auto-detects Homebrew paths, or explicit paths can be entered
in **Settings**. OpenSubtitles and bitmap subtitle display/OCR interaction are
deferred.

Verification:

```sh
flutter analyze
flutter test
flutter build macos --release
```
