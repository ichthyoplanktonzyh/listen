#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m17-test-token"

# Mock ffmpeg and whisper-cli
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

# m17 uses python3 for business JSON parsing, while the shared helper owns
# API startup, readiness, and cleanup.
start_api "$tmp/m17.sqlite" "$tmp/api.log" "$token" \
  "LLPLAYERNEXT_SUPPORT_DIR=$tmp/support" \
  "LLPLAYERNEXT_FFMPEG=$tmp/ffmpeg" \
  "LLPLAYERNEXT_WHISPER_CLI=$tmp/whisper-cli"

media="$(api_curl -d '{"path":"'"$tmp/media.mp4"'","fingerprint":"m17-media","title":"M17","kind":"video"}' "$base/v1/media")"
media_id="$(printf '%s' "$media" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
model="$(api_curl -d '{"path":"'"$tmp/model.bin"'"}' "$base/v1/transcription/models/register-custom")"
model_id="$(printf '%s' "$model" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

# Submit transcription job and wait for completion
job="$(api_curl -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
job_id="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

for _ in $(seq 1 100); do
  job="$(api_curl "$base/v1/transcription/jobs/$job_id")"
  status="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$status" == "completed" ]] && break
  [[ "$status" == "failed" ]] && { printf '%s\n' "$job"; exit 1; }
  sleep 0.1
done
assert_eq "$status" "completed" "transcription job should complete"

track_id="$(printf '%s' "$job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["generated_track_id"])')"
api_curl "$base/v1/subtitles/$track_id/export?format=srt" | grep -q "Generated learning subtitle"

# Verify database state
assert_eq "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_track_provenance;')" "1" "should have 1 provenance record"
assert_eq "$(sqlite3 "$tmp/m17.sqlite" 'PRAGMA user_version;')" "9" "schema version should be 9"

# Idempotent job reuse
same_job="$(api_curl -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
same_job_id="$(printf '%s' "$same_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
assert_eq "$same_job_id" "$job_id" "duplicate job request should return same job id"

# Cancel job
touch "$tmp/slow"
cancel_job="$(api_curl -d '{"media_id":"'"$media_id"'","model_id":"'"$model_id"'","destination":"secondary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
cancel_job_id="$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  cancel_job="$(api_curl "$base/v1/transcription/jobs/$cancel_job_id")"
  cancel_status="$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$cancel_status" == "transcribing" ]] && break
  sleep 0.1
done
api_curl -X POST "$base/v1/transcription/jobs/$cancel_job_id/cancel" >/dev/null
sleep 1
cancel_job="$(api_curl "$base/v1/transcription/jobs/$cancel_job_id")"
assert_eq "$(printf '%s' "$cancel_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')" "cancelled" "job should be cancelled"
assert_eq "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" "1" "should still have 1 track after cancellation"

# Retry cancelled job
rm "$tmp/slow"
retry_job="$(api_curl -X POST "$base/v1/transcription/jobs/$cancel_job_id/retry")"
retry_job_id="$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  retry_job="$(api_curl "$base/v1/transcription/jobs/$retry_job_id")"
  retry_status="$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$retry_status" == "completed" ]] && break
  sleep 0.1
done
assert_eq "$retry_status" "completed" "retried job should complete"
assert_eq "$(printf '%s' "$retry_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["retry_of_job_id"])')" "$cancel_job_id" "retry should reference original job"
assert_eq "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" "1" "retry should replace track, not add new one"

# Second model
printf 'second model' >"$tmp/model-2.bin"
model_2="$(api_curl -d '{"path":"'"$tmp/model-2.bin"'"}' "$base/v1/transcription/models/register-custom")"
model_2_id="$(printf '%s' "$model_2" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
model_2_job="$(api_curl -d '{"media_id":"'"$media_id"'","model_id":"'"$model_2_id"'","destination":"primary","purpose":"transcribe","language":"en"}' "$base/v1/transcription/jobs")"
model_2_job_id="$(printf '%s' "$model_2_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
for _ in $(seq 1 100); do
  model_2_job="$(api_curl "$base/v1/transcription/jobs/$model_2_job_id")"
  model_2_status="$(printf '%s' "$model_2_job" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  [[ "$model_2_status" == "completed" ]] && break
  sleep 0.1
done
assert_eq "$model_2_status" "completed" "second model job should complete"
assert_eq "$(sqlite3 "$tmp/m17.sqlite" 'SELECT count(*) FROM subtitle_tracks;')" "2" "should have 2 tracks from different models"

echo "Milestone 1.7 deterministic ASR verification passed."
