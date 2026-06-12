#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
archive="$root/dist/LLPlayerNext-macos-arm64.zip"
app="$tmp/package/LLPlayerNext.app"
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

if [[ ! -f "$root/testdata/generated/sample-video.mp4" ]]; then
  "$root/testdata/generate.sh"
fi
if [[ ! -f "$archive" ]]; then
  "$root/scripts/build-macos-mvp.sh"
fi
mkdir -p "$tmp/package"
ditto -x -k "$archive" "$tmp/package"
[[ -x "$app/Contents/MacOS/api-http" ]] ||
  fail "release archive does not contain the API sidecar"

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$root/testdata/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$root/testdata/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/LLPlayerNext" >"$tmp/desktop.log" 2>&1 &
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
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$root/testdata/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$root/testdata/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/LLPlayerNext" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "1" "reopen media item count"
assert_sqlite_value 'SELECT count(*) FROM subtitle_tracks;' "2" "reopen subtitle track count"
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-audio.m4a" \
  "$app/Contents/MacOS/LLPlayerNext" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "2" "audio media item count"
[[ -f "$app/Contents/MacOS/api-http" ]]
[[ -x "$app/Contents/Resources/runtime/whisper-cli" ]]
[[ -x "$app/Contents/Resources/runtime/ffmpeg" ]]
[[ -x "$app/Contents/Resources/runtime/ffprobe" ]]
codesign --verify --deep --strict "$app"
echo "Packaged macOS MVP smoke test passed."
