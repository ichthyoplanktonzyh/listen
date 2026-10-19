#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m20-token"

start_api \
  "$tmp/m20.sqlite" \
  "$tmp/api.log" \
  "$token" \
  LLPLAYERNEXT_ENABLE_FAKE_PHONETIC_PROVIDER=1
base="http://$address"

media="$(api_curl -d '{"path":"/tmp/m20.mp4","fingerprint":"m20","title":"M20","kind":"video"}' "$base/v1/media")"
media_id="$(json_get "$media" '.id')"
request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$root/testdata/subtitles/timeline.srt")"
track="$(api_curl -d "$request" "$base/v1/media/$media_id/subtitles")"
track_id="$(json_get "$track" '.id')"
sentence_id="$(json_get "$track" '.sentences[0].id')"

providers="$(api_curl "$base/v1/phonetic-analysis/providers")"
json_assert "$providers" 'v.length===1&&v[0].experimental===true&&v[0].available===true' "fake phonetic provider should be explicitly experimental and available only in verification"

models="$(api_curl "$base/v1/phonetic-analysis/models")"
json_assert "$models" 'v.length===1&&v[0].application_verified===false&&v[0].distribution_allowed===false' "research model must not claim release verification or distribution rights"
model_id="$(json_get "$models" '[0].id')"

wait_phonetic_job() {
  local id="$1"
  local expected="$2"
  local value=""
  local current=""
  for _ in $(seq 1 100); do
    value="$(api_curl "$base/v1/phonetic-analysis/jobs/$id")"
    current="$(json_get "$value" '.status')"
    [[ "$current" == "$expected" ]] && {
      printf '%s' "$value"
      return
    }
    sleep 0.05
  done
  echo "phonetic job $id did not reach $expected; last status: $current" >&2
  exit 1
}

job="$(api_curl -d "{\"track_id\":\"$track_id\",\"sentence_id\":\"$sentence_id\",\"model_id\":\"$model_id\"}" "$base/v1/phonetic-analysis/jobs")"
job_id="$(json_get "$job" '.id')"
job="$(wait_phonetic_job "$job_id" "completed")"

analyses="$(api_curl "$base/v1/subtitles/$track_id/phonetic-analyses")"
json_assert "$analyses" 'v.length===1&&v[0].detected_phones.length>0&&v[0].findings.every(x=>x.status!=="detected_in_audio")' "research fixture must return a timeline without detected_in_audio claims"
json_assert "$analyses" 'v[0].detected_phones.every((x,i)=>x.start_ms<x.end_ms&&(i===0||x.start_ms>=v[0].detected_phones[i-1].end_ms))' "detected phone timeline should be non-empty and monotonic"

second_sentence_id="$(json_get "$track" '.sentences[1].id')"
cancellable="$(api_curl -d "{\"track_id\":\"$track_id\",\"sentence_id\":\"$second_sentence_id\",\"model_id\":\"$model_id\",\"research_mode\":\"slow\"}" "$base/v1/phonetic-analysis/jobs")"
cancellable_id="$(json_get "$cancellable" '.id')"
cancelled="$(api_curl -X POST "$base/v1/phonetic-analysis/jobs/$cancellable_id/cancel")"
assert_eq "$(json_get "$cancelled" '.status')" "cancelled" "fake phonetic analysis job should cancel"

failed="$(api_curl -d "{\"track_id\":\"$track_id\",\"sentence_id\":\"$sentence_id\",\"model_id\":\"$model_id\",\"research_mode\":\"fail\"}" "$base/v1/phonetic-analysis/jobs")"
failed_id="$(json_get "$failed" '.id')"
failed="$(wait_phonetic_job "$failed_id" "failed")"
assert_eq "$(json_get "$failed" '.error_code')" "research_fixture_failed" "fake phonetic analysis failure should be explicit"
retried="$(api_curl -X POST "$base/v1/phonetic-analysis/jobs/$failed_id/retry")"
json_assert "$retried" "v.retry_of_job_id===\"$failed_id\"" "retry should retain source job"
wait_phonetic_job "$(json_get "$retried" '.id')" "failed" >/dev/null

partial="$(api_curl -d "{\"track_id\":\"$track_id\",\"sentence_id\":\"$sentence_id\",\"model_id\":\"$model_id\",\"research_mode\":\"partial\"}" "$base/v1/phonetic-analysis/jobs")"
partial_id="$(json_get "$partial" '.id')"
wait_phonetic_job "$partial_id" "completed" >/dev/null
analyses="$(api_curl "$base/v1/subtitles/$track_id/phonetic-analyses")"
json_assert "$analyses" "v.some(x=>x.job_id===\"$partial_id\"&&x.detected_phones.length===1&&x.findings.length>0)" "partial fake result should remain viewable and explainable"
finding_id="$(node -e "const v=JSON.parse(process.argv[1]);process.stdout.write(v.find(x=>x.job_id===process.argv[2]).findings[0].id)" "$analyses" "$partial_id")"
feedback="$(api_curl -X PUT -d '{"value":"confirmed","note":"m20 verification"}' "$base/v1/phonetic-analysis/findings/$finding_id/feedback")"
assert_eq "$(json_get "$feedback" '.value')" "confirmed" "phonetic finding feedback should persist"
bundle="$(api_curl "$base/v1/vocabulary/export")"
json_assert "$bundle" "v.version===4&&v.phonetic_finding_feedback.some(x=>x.finding_id===\"$finding_id\"&&x.value===\"confirmed\")" "phonetic feedback should enter versioned user-asset backup"

assert_eq "$(sqlite3 "$tmp/m20.sqlite" 'PRAGMA user_version;')" "9" "database schema version should be 9"
"$root/scripts/verify-m20-phase0.sh"

echo "Milestone 2.0 core contracts and fake-provider verification passed."
stop_api

if [[ "${LLPLAYERNEXT_M20_SKIP_HISTORY:-0}" != "1" ]]; then
  "$root/scripts/validate-contracts.sh"
  "$root/scripts/test.sh" --rust --strict --low-memory
  "$root/scripts/test.sh" --flutter --strict --low-memory
  echo "Milestone 2.0 full headless regression passed."
fi
