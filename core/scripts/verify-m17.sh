#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$PATH"
tmp="$(mktemp -d)"
token="m17-test-token"
pid=""

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/ffmpeg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output="${@: -1}"
printf 'fake wav' >"$output"
SH
cat >"$tmp/whisper-cli" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then exit 0; fi
output=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-of" ]]; then output="$2"; shift 2; else shift; fi
done
cat >"${output}.srt" <<'SRT'
1
00:00:00,000 --> 00:00:01,500
Generated learning subtitle.
SRT
SH
chmod +x "$tmp/ffmpeg" "$tmp/whisper-cli"
printf 'model' >"$tmp/model.bin"
printf 'media' >"$tmp/media.mp4"

LLPLAYERNEXT_DB="$tmp/m17.sqlite" \
LLPLAYERNEXT_SUPPORT_DIR="$tmp/support" \
LLPLAYERNEXT_API_TOKEN="$token" \
LLPLAYERNEXT_FFMPEG="$tmp/ffmpeg" \
LLPLAYERNEXT_WHISPER_CLI="$tmp/whisper-cli" \
  "$cargo_bin" run --quiet -p api-http >"$tmp/api.log" 2>&1 &
pid=$!

for _ in $(seq 1 100); do
  address="$(/usr/bin/python3 -c 'import json,sys
for line in open(sys.argv[1], errors="ignore"):
  try:
    value=json.loads(line)
    if value.get("event")=="api.started":
      print(value["address"]); break
  except Exception: pass' "$tmp/api.log")"
  [[ -n "$address" ]] && break
  sleep 0.1
done
base="http://$address"
auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")

media="$(curl -fsS "${auth[@]}" -d '{"path":"'"$tmp/media.mp4"'","fingerprint":"m17-media","title":"M17","kind":"video"}' "$base/v1/media")"
media_id="$(printf '%s' "$media" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
model="$(curl -fsS "${auth[@]}" -d '{"path":"'"$tmp/model.bin"'"}' "$base/v1/transcription/models/register-custom")"
model_id="$(printf '%s' "$model" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
job="$(curl -fsS "${auth[@]}" -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
job_id="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

for _ in $(seq 1 100); do
  job="$(curl -fsS "${auth[@]}" "$base/v1/transcription/jobs/$job_id")"
  status="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$status" == "completed" ]] && break
  [[ "$status" == "failed" ]] && { printf '%s\n' "$job"; exit 1; }
  sleep 0.1
done
[[ "$status" == "completed" ]]
track_id="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["generated_track_id"])')"
curl -fsS "${auth[@]}" "$base/v1/subtitles/$track_id/export?format=srt" | grep -q "Generated learning subtitle"
[[ "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_track_provenance;')" == "1" ]]
[[ "$(sqlite3 "$tmp/m17.sqlite" 'PRAGMA user_version;')" == "6" ]]

echo "Milestone 1.7 deterministic ASR verification passed."
