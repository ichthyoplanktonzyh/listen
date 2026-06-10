#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
app="$root/apps/desktop/build/macos/Build/Products/Release/LLPlayerNext.app"
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

if [[ ! -f "$root/testdata/generated/sample-video.mp4" ]]; then
  "$root/testdata/generate.sh"
fi
if [[ ! -x "$app/Contents/MacOS/api-http" ]]; then
  "$root/scripts/build-macos-mvp.sh"
fi

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$root/testdata/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$root/testdata/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/LLPlayerNext" >"$tmp/desktop.log" 2>&1 &
pid=$!

for _ in $(seq 1 100); do
  if [[ -f "$tmp/mvp.sqlite" ]] && \
    [[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM subtitle_sentences;' 2>/dev/null || true)" == "2104" ]]; then
    break
  fi
  sleep 0.2
done

kill -0 "$pid"
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM media_items;')" == "1" ]]
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" == "2" ]]
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM subtitle_sentences;')" == "2104" ]]
sleep 6
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM playback_progress WHERE position_ms > 0;')" == "1" ]]
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-video.mp4" \
LLPLAYERNEXT_SMOKE_SUBTITLE="$root/testdata/generated/long-timeline.srt" \
LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE="$root/testdata/subtitles/timeline.vtt" \
  "$app/Contents/MacOS/LLPlayerNext" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
kill -0 "$pid"
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM media_items;')" == "1" ]]
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" == "2" ]]
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$root/testdata/generated/sample-audio.m4a" \
  "$app/Contents/MacOS/LLPlayerNext" >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
kill -0 "$pid"
[[ "$(sqlite3 "$tmp/mvp.sqlite" 'SELECT count(*) FROM media_items;')" == "2" ]]
[[ -f "$app/Contents/MacOS/api-http" ]]
[[ -x "$app/Contents/Resources/runtime/whisper-cli" ]]
[[ -x "$app/Contents/Resources/runtime/ffmpeg" ]]
[[ -x "$app/Contents/Resources/runtime/ffprobe" ]]
codesign --verify --deep --strict "$app"
echo "Packaged macOS MVP smoke test passed."
