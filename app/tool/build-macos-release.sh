#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter_bin="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
backend_lock="${BACKEND_LOCK:-$root/backend.lock.json}"

python3 "$root/tool/backend_artifacts.py" --lock "$backend_lock" verify
python3 "$root/tool/listen_gen_artifacts.py" verify

cd "$root"
"$flutter_bin" clean
"$flutter_bin" pub get
"$flutter_bin" build macos --release

app="$root/build/macos/Build/Products/Release/listen.app"
BACKEND_LOCK="$backend_lock" "$root/tool/stage-macos-runtime.sh" "$app"
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
