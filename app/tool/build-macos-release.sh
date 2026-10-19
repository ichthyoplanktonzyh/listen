#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter_bin="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
backend_lock="${BACKEND_LOCK:?set BACKEND_LOCK to the generated Core lock}"
gen_lock="${LISTEN_GEN_LOCK_PATH:?set LISTEN_GEN_LOCK_PATH to the generated Gen lock}"
gen_manifest="${LISTEN_GEN_RELEASE_MANIFEST:?set LISTEN_GEN_RELEASE_MANIFEST to the generated Gen manifest}"
release_output="${LISTEN_RELEASE_OUTPUT_DIR:-$root/dist}"
source_root="$(git -C "$root" rev-parse --show-toplevel)"
source_status="$(git -C "$source_root" status --porcelain --untracked-files=all)"

absolute_file() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
  fi
}
backend_lock="$(absolute_file "$backend_lock")"
gen_lock="$(absolute_file "$gen_lock")"
gen_manifest="$(absolute_file "$gen_manifest")"

[[ -f "$backend_lock" ]] || { echo "Core lock not found: $backend_lock" >&2; exit 1; }
[[ -f "$gen_lock" ]] || { echo "Gen lock not found: $gen_lock" >&2; exit 1; }
[[ -f "$gen_manifest" ]] || { echo "Gen release manifest not found: $gen_manifest" >&2; exit 1; }
mkdir -p "$release_output"
release_output="$(cd "$release_output" && pwd)"

build_inputs="$(mktemp -d)"
cleanup() { rm -rf "$build_inputs"; }
trap cleanup EXIT
dart_defines="$build_inputs/dart-defines.json"
python3 - "$gen_lock" "$dart_defines" <<'PY'
import json
import base64
import sys
from pathlib import Path

lock_bytes = Path(sys.argv[1]).read_bytes()
json.loads(lock_bytes.decode("utf-8"))
Path(sys.argv[2]).write_text(
    json.dumps(
        {"LISTEN_GEN_LOCK_BASE64": base64.b64encode(lock_bytes).decode("ascii")}
    ),
    encoding="utf-8",
)
PY

python3 "$root/tool/backend_artifacts.py" --lock "$backend_lock" verify \
  --skip-fixture-check
python3 "$root/tool/listen_gen_artifacts.py" --lock "$gen_lock" verify \
  --manifest "$gen_manifest"

cd "$root"
"$flutter_bin" clean
"$flutter_bin" pub get --enforce-lockfile
"$flutter_bin" build macos --release \
  --no-pub \
  --dart-define-from-file="$dart_defines"

app="$root/build/macos/Build/Products/Release/listen.app"
BACKEND_LOCK="$backend_lock" \
LISTEN_GEN_LOCK_PATH="$gen_lock" \
LISTEN_GEN_RELEASE_MANIFEST="$gen_manifest" \
  "$root/tool/stage-macos-runtime.sh" "$app"
"$root/tool/sanitize-macos-player-framework.sh" "$app"

xattr -cr "$app"
codesign --force --deep --sign - \
  --entitlements "$root/macos/Runner/Release.entitlements" \
  "$app"
xattr -cr "$app"
touch "$app" "$app/Contents"

archive="$release_output/listen-macos-arm64.zip"
rm -f "$archive"
(
  cd "$(dirname "$app")"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$archive" "$(basename "$app")"
)

file "$app/Contents/MacOS/listen" "$app/Contents/MacOS/api-http" \
  "$app/Contents/Resources/runtime/whisper-cli" \
  "$app/Contents/Resources/runtime/ffmpeg" \
  "$app/Contents/Resources/runtime/ffprobe"
final_source_status="$(git -C "$source_root" status --porcelain --untracked-files=all)"
if [[ "$final_source_status" != "$source_status" ]]; then
  echo "Release build changed tracked or untracked source state." >&2
  exit 1
fi
echo "Built $archive"
