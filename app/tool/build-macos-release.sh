#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter_bin="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
runtime="$root/.backend/runtime"
api_http="$runtime/bin/api-http"
backend_lock="${BACKEND_LOCK:-$root/backend.lock.json}"

python3 "$root/tool/backend_artifacts.py" --lock "$backend_lock" verify
[[ -x "$api_http" ]] || {
  echo "Installed listen-core runtime is missing api-http." >&2
  exit 1
}

cd "$root"
"$flutter_bin" clean
"$flutter_bin" pub get
"$flutter_bin" build macos --release

app="$root/build/macos/Build/Products/Release/listen.app"
cp "$api_http" "$app/Contents/MacOS/api-http"
chmod +x "$app/Contents/MacOS/api-http"
mkdir -p "$app/Contents/Resources/runtime"
cp -R "$runtime/runtime/." "$app/Contents/Resources/runtime/"
cp "$runtime/THIRD_PARTY_NOTICES.md" \
  "$app/Contents/Resources/runtime/THIRD_PARTY_NOTICES.md"
"$root/tool/sanitize-macos-player-framework.sh" "$app"

xattr -cr "$app"
codesign --force --deep --sign - \
  --entitlements "$root/macos/Runner/Release.entitlements" \
  "$app"
xattr -cr "$app"
touch "$app" "$app/Contents"

mkdir -p "$root/dist"
archive="$root/dist/listen-macos-arm64.zip"
rm -f "$archive"
(
  cd "$(dirname "$app")"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$archive" "$(basename "$app")"
)

file "$app/Contents/MacOS/listen" "$app/Contents/MacOS/api-http" \
  "$app/Contents/Resources/runtime/whisper-cli" \
  "$app/Contents/Resources/runtime/ffmpeg" \
  "$app/Contents/Resources/runtime/ffprobe"
echo "Built $archive"
