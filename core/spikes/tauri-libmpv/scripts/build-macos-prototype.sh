#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"
pnpm tauri build --debug

app="$root/src-tauri/target/debug/bundle/macos/spikestauri-libmpv.app"
cp "$root/src-tauri/lib/libmpv-wrapper.dylib" \
  "$app/Contents/MacOS/libmpv-wrapper.dylib"
ln -sf /opt/homebrew/lib/libmpv.dylib "$app/Contents/MacOS/libmpv.dylib"
codesign --force --deep --sign - "$app"

echo "Prototype bundle prepared at $app"
echo "This prototype still depends on Homebrew mpv and is not distributable."
