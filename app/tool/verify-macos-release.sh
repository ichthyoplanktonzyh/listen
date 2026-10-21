#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if ! bash -n "$0"; then
  echo "Refusing to run the macOS release verifier with invalid shell syntax." >&2
  exit 2
fi
fixture_source="${LISTEN_SMOKE_FIXTURE_SOURCE:-$root/test/fixtures/smoke}"
tmp="$(mktemp -d)"
fixtures="$tmp/fixtures"
release_output="${LISTEN_RELEASE_OUTPUT_DIR:-$root/dist}"
archive="$release_output/listen-macos-arm64.zip"
backend_lock="${BACKEND_LOCK:?set BACKEND_LOCK to the generated Core lock}"
gen_lock="${LISTEN_GEN_LOCK_PATH:?set LISTEN_GEN_LOCK_PATH to the generated Gen lock}"
gen_manifest="${LISTEN_GEN_RELEASE_MANIFEST:?set LISTEN_GEN_RELEASE_MANIFEST to the generated Gen manifest}"
release_version="${LISTEN_RELEASE_VERSION:-}"
release_channel="${LISTEN_RELEASE_CHANNEL:-}"
source_commit="${LISTEN_SOURCE_COMMIT:-}"
minimum_macos="${LISTEN_RELEASE_MINIMUM_MACOS_VERSION:-}"
release_build_number="${LISTEN_RELEASE_BUILD_NUMBER:-}"
app="$tmp/package/listen.app"
isolated_home="$tmp/home"
isolated_support="$tmp/support"
minimal_path="/usr/bin:/bin:/usr/sbin:/sbin"
pid=""

cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if rm -rf "$tmp"; then
    :
  else
    cleanup_status=$?
  fi
  if [[ "$status" -eq 0 && "$cleanup_status" -ne 0 ]]; then
    status="$cleanup_status"
  fi
  exit "$status"
}
trap cleanup EXIT
mkdir -p "$isolated_home" "$isolated_support"

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

preserve_audio_smoke_diagnostics() {
  local diagnostics
  diagnostics="$(mktemp -d "${TMPDIR:-/tmp}/listen-audio-smoke-timeout.XXXXXX")" ||
    return 1
  chmod 700 "$diagnostics"
  for file in \
    "$tmp/desktop.log" \
    "$isolated_home/Library/Logs/listen/core.log" \
    "$tmp/mvp.sqlite" \
    "$tmp/mvp.sqlite-wal" \
    "$tmp/mvp.sqlite-shm"; do
    if [[ -f "$file" ]]; then
      cp "$file" "$diagnostics/$(basename "$file")" || return 1
      chmod 600 "$diagnostics/$(basename "$file")" || return 1
    fi
  done
  echo "Isolated audio smoke diagnostics preserved at: $diagnostics" >&2
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

launch_packaged_app() (
  unset LISTEN_SOURCE_ROOT LISTEN_CORE_RUNTIME_DIR LISTEN_GEN_RELEASE_MANIFEST
  unset LISTEN_GEN_LOCK_PATH LLPLAYERNEXT_API_BINARY LLPLAYERNEXT_WHISPER_CLI
  unset LLPLAYERNEXT_FFMPEG LLPLAYERNEXT_FFPROBE LLPLAYERNEXT_VERIFY_GEN_BUNDLE
  export HOME="$isolated_home"
  export PATH="$minimal_path"
  export LLPLAYERNEXT_SUPPORT_DIR="$isolated_support"
  exec "$app/Contents/MacOS/listen"
)

if [[ ! -f "$fixture_source/generated/sample-video.mp4" ]]; then
  "$fixture_source/generate.sh"
fi
cp -R "$fixture_source" "$fixtures"
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

if [[ -n "$release_version$release_channel$source_commit$minimum_macos$release_build_number" ]]; then
  [[ -n "$release_version" && -n "$release_channel" && -n "$source_commit" && -n "$minimum_macos" && -n "$release_build_number" ]] ||
    fail "release metadata environment is incomplete"
  if ! python3 - "$app/Contents/Info.plist" "$backend_lock" "$gen_lock" \
    "$release_version" "$release_channel" "$source_commit" "$minimum_macos" \
    "$release_build_number" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

plist_path, backend_path, gen_path = map(Path, sys.argv[1:4])
version, channel, source_commit, minimum_macos, build_number = sys.argv[4:9]
info = plistlib.loads(plist_path.read_bytes())
backend = json.loads(backend_path.read_text(encoding="utf-8"))
gen = json.loads(gen_path.read_text(encoding="utf-8"))
if (
    info.get("ListenReleaseVersion") != version
    or info.get("ListenReleaseChannel") != channel
    or info.get("ListenSourceCommit") != source_commit
    or info.get("LSMinimumSystemVersion") != minimum_macos
    or info.get("CFBundleShortVersionString") != version.split("-", 1)[0]
    or info.get("CFBundleVersion") != build_number
    or backend.get("core_git_sha") != source_commit
    or gen.get("source_git_sha") != source_commit
):
    raise SystemExit(1)
print(
    "Release identity verified:",
    version,
    "build",
    info["CFBundleVersion"],
    source_commit,
    "minimum macOS",
    minimum_macos,
)
PY
  then
    fail "release bundle version, minimum OS, or source metadata is inconsistent"
  fi
fi

# Exercise the exact Dart define embedded into the release. A deliberately
# invalid debug lock path proves the packaged app ignores development inputs;
# the manifest is resolved only from the released app bundle.
invalid_dev_lock="$tmp/invalid-development-lock.json"
printf '{"not":"a Listen lock"}\n' > "$invalid_dev_lock"
if ! (
  unset LISTEN_SOURCE_ROOT LISTEN_CORE_RUNTIME_DIR LISTEN_GEN_RELEASE_MANIFEST
  unset LLPLAYERNEXT_API_BINARY LLPLAYERNEXT_WHISPER_CLI LLPLAYERNEXT_FFMPEG LLPLAYERNEXT_FFPROBE
  export HOME="$isolated_home"
  export PATH="$minimal_path"
  export LLPLAYERNEXT_SUPPORT_DIR="$isolated_support"
  LLPLAYERNEXT_VERIFY_GEN_BUNDLE=1 \
  LISTEN_GEN_LOCK_PATH="$invalid_dev_lock" \
    exec "$app/Contents/MacOS/listen"
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
  launch_packaged_app >"$tmp/desktop.log" 2>&1 &
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
  launch_packaged_app >>"$tmp/desktop.log" 2>&1 &
pid=$!
sleep 3
assert_app_running
assert_sqlite_value 'SELECT count(*) FROM media_items;' "1" "reopen media item count"
assert_sqlite_value 'SELECT count(*) FROM subtitle_tracks;' "2" "reopen subtitle track count"
stop_app

LLPLAYERNEXT_DB="$tmp/mvp.sqlite" \
LLPLAYERNEXT_SMOKE_MEDIA="$fixtures/generated/sample-audio.m4a" \
  launch_packaged_app >>"$tmp/desktop.log" 2>&1 &
pid=$!
if ! python3 "$root/tool/wait_for_sqlite_value.py" \
  "$tmp/mvp.sqlite" \
  'SELECT count(*) FROM media_items;' \
  2 \
  --timeout-seconds 20 \
  --interval-seconds 0.2 \
  --description "audio media item count"; then
  stop_app
  preserve_audio_smoke_diagnostics ||
    echo "Could not preserve isolated audio smoke diagnostics." >&2
  fail "audio media item registration did not reach 2 within 20 seconds"
fi
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
