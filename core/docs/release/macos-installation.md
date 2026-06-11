# macOS Apple Silicon Installation

The Milestone 1 MVP version is `0.2.0`. Its artifact is
`dist/LLPlayerNext-macos-arm64.zip`.

1. Unzip the archive.
2. Move `LLPlayerNext.app` to `/Applications`.
3. On first launch, macOS may require Control-clicking the app and choosing
   Open because the MVP is ad-hoc signed and not notarized.
4. Use **Open media**, then **Primary subtitle** or **Secondary subtitle**.

Optional enhanced features:

- Drag local media and up to two SRT/VTT files onto the window.
- Install `ffmpeg` and `ffprobe` to import embedded text subtitles for learning.
- Install `yt-dlp` to play or explicitly download legally accessible supported
  media from **Open URL**. Downloads continue in the background and the bundled
  `ffmpeg` merges separate video and audio streams.
- Configure subtitle appearance and optional tool paths from **Settings**.

The bundled `api-http` sidecar listens only on a random loopback port. User data
is stored in:

```text
~/Library/Application Support/LLPlayerNext/llplayernext.sqlite
```

The app supports macOS Apple Silicon only for this MVP. The Flutter executable
is universal, but the bundled Rust sidecar is arm64.
