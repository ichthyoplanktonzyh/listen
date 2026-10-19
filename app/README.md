# Listen App

Flutter desktop learning experience in the Listen monorepo. Start the complete
current-source product with `./dev setup` and `./dev run` from the repository
root. See [DEVELOPMENT.md](../DEVELOPMENT.md) for checks and product releases.

[CONTEXT.md](CONTEXT.md) adds App interaction terms. Root documents own shared
product semantics, active status and roadmap. App keeps its native Flutter
project and local HTTP sidecar lifecycle; Core and Gen source changes can be
integrated in the same branch without component release/pin handoffs.

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

Verification and packaging use the shared root commands `./dev check`,
`./dev test integration`, and `./dev release`. For focused native checks run
Flutter analysis/tests and the Python `tool/` unit suite from this directory;
see [DEVELOPMENT.md](../DEVELOPMENT.md) for exact commands and release inputs.
