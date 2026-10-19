#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m1-smoke-token"

start_api "$tmp/m1.sqlite" "$tmp/api.log" "$token"
base="http://$address"

# Health and auth checks (use raw curl for unauthorized test)
curl --fail --silent "$base/v1/health" >/dev/null
unauthorized="$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST "$base/v1/media")"
assert_eq "$unauthorized" "401" "unauthorized POST should return 401"

# Media idempotency
media='{"path":"/tmp/m1.mp4","fingerprint":"m1-fixture","title":"M1","kind":"video","duration_ms":5000}'
first="$(api_curl -d "$media" "$base/v1/media")"
second="$(api_curl -d "$media" "$base/v1/media")"
media_id="$(json_get "$first" '.id')"
second_id="$(json_get "$second" '.id')"
assert_eq "$media_id" "$second_id" "duplicate media should return same id"

# Subtitle import
subtitle_path="$root/testdata/subtitles/timeline.srt"
subtitle_request="$(node -e 'process.stdout.write(JSON.stringify({path: process.argv[1], language: "en"}))' "$subtitle_path")"
track="$(api_curl -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
track_again="$(api_curl -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
json_assert "$track" 'v.sentences.length===4' "should import 4 sentences"
track_id="$(json_get "$track" '.id')"
sentence_id="$(json_get "$track" '.sentences[0].id')"
track_again_id="$(json_get "$track_again" '.id')"
assert_eq "$track_id" "$track_again_id" "duplicate subtitle import should return same id"

api_curl "$base/v1/subtitles/$track_id" >/dev/null

# Playback progress
api_curl -X PUT -d '{"position_ms":1234}' "$base/v1/media/$media_id/progress" >/dev/null
progress="$(api_curl "$base/v1/media/$media_id/progress")"
json_assert "$progress" 'v.position_ms===1234' "progress position_ms should be 1234"

# Lexical entry CRUD
word='{"language":"en","kind":"word","canonical_form":"Hello","display_form":"Hello","status":"known_recognized"}'
updated_entry="$(api_curl -X PUT -d "$word" "$base/v1/lexical-entries")"
entry_id="$(json_get "$updated_entry" '.entry.id')"
json_assert "$updated_entry" 'v.entry.status==="known_recognized"' "lexical entry status should be known_recognized"

# Batch lookup
batch="$(api_curl -d '{"language":"en","kind":"word","forms":["hello","missing"]}' "$base/v1/lexical-entries/batch")"
json_assert "$batch" 'v.length===1' "batch should return 1 entry for existing lexical form only"

# Lexical observation
observation="$(node -e 'process.stdout.write(JSON.stringify({lexical_entry_id:process.argv[1],sentence_id:process.argv[2],original_form:"Hello",result:"recognized_in_context"}))' "$entry_id" "$sentence_id")"
api_curl -d "$observation" "$base/v1/lexical-observations" >/dev/null

# Diagnosis
diagnosis="$(api_curl "$base/v1/sentences/$sentence_id/diagnosis")"
json_assert "$diagnosis" 'v.hints.length>0' "diagnosis should have hints"

# Verify clean shutdown event
stop_api
assert_contains "$(cat "$tmp/api.log")" '"event":"api.stopped"' "log should contain api.stopped event"

echo "M1 headless API smoke test passed."
