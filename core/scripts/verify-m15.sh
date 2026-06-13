#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m15-token"

# ── First API instance: source database ──
start_api "$tmp/source.sqlite" "$tmp/source.log" "$token"
base="http://$address"

media="$(api_curl -d '{"path":"/tmp/source.mp4","fingerprint":"m15-media","title":"M15 Source","kind":"video"}' "$base/v1/media")"
media_id="$(json_get "$media" '.id')"

subtitle_request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$root/testdata/subtitles/timeline.srt")"
track="$(api_curl -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
sentence_id="$(json_get "$track" '.sentences[0].id')"

# Build source context
source="$(node -e '
  const media=JSON.parse(process.argv[1]), track=JSON.parse(process.argv[2]), s=track.sentences[0];
  process.stdout.write(JSON.stringify({language:"en",normalized_lemma:"hello",media_id:media.id,
    sentence_id:s.id,original_form:"Hello",sentence_text:s.display_text,media_title:media.title,
    media_fingerprint:media.fingerprint,start_ms:s.start,end_ms:s.end}))
' "$media" "$track")"

# Update word profile with source
update="$(node -e 'process.stdout.write(JSON.stringify({language:"en",lemma:"hello",display_form:"Hello",status:"unknown_meaning",source:JSON.parse(process.argv[1])}))' "$source")"
profile="$(api_curl -X PUT -d "$update" "$base/v1/word-profiles")"
profile_id="$(json_get "$profile" '.id')"

# Idempotent re-import
api_curl -X PUT -d "$update" "$base/v1/word-profiles" >/dev/null

details="$(api_curl "$base/v1/word-profiles/$profile_id/details")"
json_assert "$details" 'v.history.length===1&&v.occurrences[0].encounter_count===2' "history should deduplicate, encounter count should be 2"

# Word observation
observation="$(node -e 'process.stdout.write(JSON.stringify({word_profile_id:process.argv[1],sentence_id:process.argv[2],original_form:"Hello",result:"recognized_in_context",source:JSON.parse(process.argv[3])}))' "$profile_id" "$sentence_id" "$source")"
api_curl -d "$observation" "$base/v1/word-observations" >/dev/null

# Vocabulary book
book="$(api_curl "$base/v1/vocabulary?status=unknown_meaning&language=en")"
json_assert "$book" 'v.length===1' "vocabulary book should have 1 entry"

# Export bundle
bundle="$(api_curl "$base/v1/vocabulary/export")"

# Archive media and verify occurrence nullification
api_curl -X PUT -d '{"availability":"archived"}' "$base/v1/media/$media_id/availability" >/dev/null
details="$(api_curl "$base/v1/word-profiles/$profile_id/details")"
json_assert "$details" 'v.occurrences[0].media_id===null' "archived media should nullify media_id in occurrence"

# Move media and verify re-link
api_curl -d '{"path":"/tmp/moved-source.mp4","fingerprint":"m15-media","title":"M15 Source moved","kind":"video"}' "$base/v1/media" >/dev/null
details="$(api_curl "$base/v1/word-profiles/$profile_id/details")"
json_assert "$details" 'v.occurrences[0].media_id!==null&&v.occurrences[0].sentence_id!==null' "moved media should re-link occurrences"

stop_api

# ── Second API instance: restore from export ──
start_api "$tmp/restored.sqlite" "$tmp/restored.log" "$token"
base="http://$address"

for _ in 1 2; do
  api_curl -d "$bundle" "$base/v1/vocabulary/import" >/dev/null
done

restored="$(api_curl "$base/v1/vocabulary/export")"
json_assert "$restored" 'v.profiles.length===1&&v.history.length===2&&v.occurrences.length===1&&v.observations.length===1&&v.history.some(h=>h.change_source==="import")' "restored bundle should preserve all data with import history"

stop_api

echo "Milestone 1.5 vocabulary asset verification passed."
