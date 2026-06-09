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
codesign --force --deep --sign - "$app"

mkdir -p "$root/dist"
rm -f "$root/dist/LLPlayerNext-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "$app" "$root/dist/LLPlayerNext-macos-arm64.zip"

file "$app/Contents/MacOS/LLPlayerNext" "$app/Contents/MacOS/api-http"
echo "Built $root/dist/LLPlayerNext-macos-arm64.zip"
