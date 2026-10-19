#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="$root/test/fixtures/smoke"
tmp="$(mktemp -d)"
release_output="${LISTEN_RELEASE_OUTPUT_DIR:-$root/dist}"
archive="$release_output/listen-macos-arm64.zip"
backend_lock="${BACKEND_LOCK:?set BACKEND_LOCK to the generated Core lock}"
gen_lock="${LISTEN_GEN_LOCK_PATH:?set LISTEN_GEN_LOCK_PATH to the generated Gen lock}"
gen_manifest="${LISTEN_GEN_RELEASE_MANIFEST:?set LISTEN_GEN_RELEASE_MANIFEST to the generated Gen manifest}"
app="$tmp/package/listen.app"
pid=""

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 "$root/tool/backend_artifacts.py" --lock "$backend_lock" verify \
  --skip-fixture-check
python3 "$root/tool/listen_gen_artifacts.py" --lock "$gen_lock" verify \
  --manifest "$gen_manifest"

stop_app() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  pid=""
}

fail() {
  echo "Packaged macOS MVP smoke test failed: $*" >&2
  if [[ -f "$tmp/desktop.log" ]]; then
    echo "--- desktop.log ---" >&2
    cat "$tmp/desktop.log" >&2
  fi
  exit 1
}

assert_app_running() {
  kill -0 "$pid" 2>/dev/null || fail "desktop process exited unexpectedly"
}

sqlite_value() {
  local query="$1"
  [[ -f "$tmp/mvp.sqlite" ]] || return 1
  sqlite3 -cmd '.timeout 5000' "$tmp/mvp.sqlite" "$query" 2>/dev/null
}

assert_sqlite_value() {
  local query="$1"
  local expected="$2"
  local description="$3"
  local actual
  actual="$(sqlite_value "$query")" ||
    fail "database query failed while checking $description"
  [[ "$actual" == "$expected" ]] ||
    fail "$description: expected $expected, got $actual"
}

if [[ ! -f "$fixtures/generated/sample-video.mp4" ]]; then
  "$fixtures/generate.sh"
fi
if [[ ! -f "$archive" ]]; then
  "$root/tool/build-macos-release.sh"
fi
if unzip -Z1 "$archive" | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
  fail "release archive contains macOS metadata files"
fi
mkdir -p "$tmp/package"
ditto -x -k "$archive" "$tmp/package"
cd "$tmp/package"
[[ -x "$app/Contents/MacOS/api-http" ]] ||
  fail "release archive does not contain the API sidecar"

# Exercise the exact Dart define embedded into the release. A deliberately
# invalid debug lock path proves the packaged app ignores development inputs;
# the manifest is resolved only from the released app bundle.
invalid_dev_lock="$tmp/invalid-development-lock.json"
printf '{"not":"a Listen lock"}\n' > "$invalid_dev_lock"
if ! (
  unset LISTEN_GEN_RELEASE_MANIFEST
  LLPLAYERNEXT_VERIFY_GEN_BUNDLE=1 \
  LISTEN_GEN_LOCK_PATH="$invalid_dev_lock" \
    "$app/Contents/MacOS/listen"
) >"$tmp/gen-verification.log" 2>&1; then
  cat "$tmp/gen-verification.log" >&2
  fail "the packaged app rejected its compiled Gen lock"
fi
python3 - "$tmp/gen-verification.log" "$gen_lock" <<'PY'
import json
import sys
from pathlib import Path

probe_path, lock_path = map(Path, sys.argv[1:])
lock = json.loads(lock_path.read_text(encoding="utf-8"))
probe = None
for line in probe_path.read_text(encoding="utf-8").splitlines():
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and value.get("status") == "verified":
        probe = value
        break
if probe is None:
    raise SystemExit("packaged app returned no structured Gen verification result")
expected_artifact = lock.get("artifact", {})
if (
    probe.get("source_commit") != lock.get("source_git_sha")
    or probe.get("artifact_sha256") != expected_artifact.get("sha256")
    or probe.get("tool_version") != lock.get("tool", {}).get("version")
):
    raise SystemExit("packaged app verified a different Gen release than the generated lock")
print(
    "Packaged Gen release verified by the app:",
    probe["source_commit"],
    probe["artifact_sha256"],
)
PY

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$fixtures/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$fixtures/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$fixtures/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/listen" >"$tmp/desktop.log" 2>&1 &
pid=$!

for _ in $(seq 1 100); do
  assert_app_running
  if [[ "$(sqlite_value 'SELECT count(*) FROM subtitle_sentences;' || true)" == "2104" ]]; then
    break
  fi
  sleep 0.2
done

assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "1" "video media item count"
assert_sqlite_value 'SELECT count(*) FROM subtitle_tracks;' "2" "subtitle track count"
assert_sqlite_value 'SELECT count(*) FROM subtitle_sentences;' "2104" "subtitle sentence count"
sleep 6
assert_sqlite_value \
  'SELECT count(*) FROM playback_progress WHERE position_ms > 0;' \
  "1" \
  "playback progress count"
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$fixtures/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$fixtures/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$fixtures/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/listen" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "1" "reopen media item count"
assert_sqlite_value 'SELECT count(*) FROM subtitle_tracks;' "2" "reopen subtitle track count"
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$fixtures/generated/sample-audio.m4a" \
  "$app/Contents/MacOS/listen" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "2" "audio media item count"
[[ -f "$app/Contents/MacOS/api-http" ]]
[[ -x "$app/Contents/Resources/runtime/whisper-cli" ]]
[[ -x "$app/Contents/Resources/runtime/ffmpeg" ]]
[[ -x "$app/Contents/Resources/runtime/ffprobe" ]]
python3 "$root/tool/listen_gen_artifacts.py" --lock "$gen_lock" verify \
  --bundle-dir "$app/Contents/Resources/runtime/listen-gen"
codesign --verify --deep --strict "$app"
echo "Packaged macOS MVP smoke test passed."
