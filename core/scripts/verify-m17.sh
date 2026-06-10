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
if [[ -f "$(dirname "$0")/slow" ]]; then sleep 10; fi
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

same_job="$(curl -fsS "${auth[@]}" -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
same_job_id="$(printf '%s' "$same_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
[[ "$same_job_id" == "$job_id" ]]

touch "$tmp/slow"
cancel_job="$(curl -fsS "${auth[@]}" -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"secondary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
cancel_job_id="$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  cancel_job="$(curl -fsS "${auth[@]}" "$base/v1/transcription/jobs/$cancel_job_id")"
  cancel_status="$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$cancel_status" == "transcribing" ]] && break
  sleep 0.1
done
curl -fsS "${auth[@]}" -X POST "$base/v1/transcription/jobs/$cancel_job_id/cancel" >/dev/null
sleep 1
cancel_job="$(curl -fsS "${auth[@]}" "$base/v1/transcription/jobs/$cancel_job_id")"
[[ "$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')" == "cancelled" ]]
[[ "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" == "1" ]]
rm "$tmp/slow"
retry_job="$(curl -fsS "${auth[@]}" -X POST "$base/v1/transcription/jobs/$cancel_job_id/retry")"
retry_job_id="$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  retry_job="$(curl -fsS "${auth[@]}" "$base/v1/transcription/jobs/$retry_job_id")"
  retry_status="$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$retry_status" == "completed" ]] && break
  sleep 0.1
done
[[ "$retry_status" == "completed" ]]
[[ "$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["retry_of_job_id"])')" == "$cancel_job_id" ]]
[[ "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" == "1" ]]

printf 'second model' >"$tmp/model-2.bin"
model_2="$(curl -fsS "${auth[@]}" -d '{"path":"'"$tmp/model-2.bin"'"}' "$base/v1/transcription/models/register-custom")"
model_2_id="$(printf '%s' "$model_2" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
model_2_job="$(curl -fsS "${auth[@]}" -d '{"media_id":"'"$media_id"'","model_id":"'"$model_2_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
model_2_job_id="$(printf '%s' "$model_2_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  model_2_job="$(curl -fsS "${auth[@]}" "$base/v1/transcription/jobs/$model_2_job_id")"
  model_2_status="$(printf '%s' "$model_2_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$model_2_status" == "completed" ]] && break
  sleep 0.1
done
[[ "$model_2_status" == "completed" ]]
[[ "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" == "2" ]]

echo "Milestone 1.7 deterministic ASR verification passed."
