# Tauri + libmpv M0 Spike

This spike uses `tauri-plugin-libmpv` to embed libmpv behind a transparent
React WebView. The subtitle button verifies that the WebView remains
interactive over the native video surface.

```sh
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"
pnpm install
pnpm exec tauri-plugin-libmpv-api setup-lib
./scripts/build-macos-prototype.sh
open src-tauri/target/debug/bundle/macos/spikestauri-libmpv.app
```

The upstream plugin marks macOS as untested, so successful local verification
must be recorded in `docs/verification/macos-m0-checklist.md`.

The 2026-06-09 verification found that video opens in a separate mpv window on
macOS. This prevents a React subtitle overlay from appearing over the video and
rejects this implementation as the desktop baseline.
