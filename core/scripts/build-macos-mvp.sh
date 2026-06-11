#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter_bin="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$(dirname "$flutter_bin"):$PATH"

cd "$root"
"$cargo_bin" build --release -p api-http
(
  cd apps/desktop
  "$flutter_bin" pub get
  "$flutter_bin" build macos --release
)

app="$root/apps/desktop/build/macos/Build/Products/Release/LLPlayerNext.app"
cp "$root/target/release/api-http" "$app/Contents/MacOS/api-http"
chmod +x "$app/Contents/MacOS/api-http"
runtime="$root/third_party/runtime/macos-arm64"
if [[ ! -x "$runtime/whisper-cli" || ! -x "$runtime/ffmpeg" || ! -x "$runtime/ffprobe" ]]; then
  "$root/scripts/build-asr-runtime.sh"
fi
mkdir -p "$app/Contents/Resources/runtime"
cp "$runtime/whisper-cli" "$runtime/ffmpeg" "$runtime/ffprobe" \
  "$app/Contents/Resources/runtime/"
cp "$root/third_party/runtime/manifest.json" \
  "$app/Contents/Resources/runtime/manifest.json"
cp "$root/third_party/runtime/THIRD_PARTY_NOTICES.md" \
  "$app/Contents/Resources/runtime/THIRD_PARTY_NOTICES.md"
"$root/scripts/sanitize-macos-player-framework.sh" "$app"
codesign --force --deep --sign - "$app"

mkdir -p "$root/dist"
rm -f "$root/dist/LLPlayerNext-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "$app" "$root/dist/LLPlayerNext-macos-arm64.zip"

file "$app/Contents/MacOS/LLPlayerNext" "$app/Contents/MacOS/api-http" \
  "$app/Contents/Resources/runtime/whisper-cli" \
  "$app/Contents/Resources/runtime/ffmpeg" \
  "$app/Contents/Resources/runtime/ffprobe"
echo "Built $root/dist/LLPlayerNext-macos-arm64.zip"
