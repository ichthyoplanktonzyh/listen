#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
token="m15-token"
pid=""
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$PATH"

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" || true
    wait "$pid" || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

start_api() {
  local db="$1"
  local log="$2"
  LLPLAYERNEXT_DB="$db" LLPLAYERNEXT_API_TOKEN="$token" \
    "$cargo_bin" run --quiet -p api-http >"$log" 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do
    address="$(node -e '
      const fs=require("fs");
      if (!fs.existsSync(process.argv[1])) process.exit(1);
      for (const line of fs.readFileSync(process.argv[1],"utf8").split("\n")) {
        try { const v=JSON.parse(line); if(v.event==="api.started"){process.stdout.write(v.address);process.exit(0)}} catch {}
      }
      process.exit(1)
    ' "$log" 2>/dev/null || true)"
    [[ -n "${address:-}" ]] && return
    sleep 0.1
  done
  cat "$log"
  exit 1
}

stop_api() {
  kill -INT "$pid"
  wait "$pid"
  pid=""
}

auth="Authorization: Bearer $token"
start_api "$tmp/source.sqlite" "$tmp/source.log"
base="http://$address"
media="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d '{"path":"/tmp/source.mp4","fingerprint":"m15-media","title":"M15 Source","kind":"video"}' "$base/v1/media")"
media_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$media")"
subtitle_request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$root/testdata/subtitles/timeline.srt")"
track="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
sentence_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sentences[0].id)' "$track")"
source="$(node -e '
  const media=JSON.parse(process.argv[1]), track=JSON.parse(process.argv[2]), s=track.sentences[0];
  process.stdout.write(JSON.stringify({language:"en",normalized_lemma:"hello",media_id:media.id,
    sentence_id:s.id,original_form:"Hello",sentence_text:s.display_text,media_title:media.title,
    media_fingerprint:media.fingerprint,start_ms:s.start,end_ms:s.end}))
' "$media" "$track")"
update="$(node -e 'process.stdout.write(JSON.stringify({language:"en",lemma:"hello",display_form:"Hello",status:"unknown_meaning",source:JSON.parse(process.argv[1])}))' "$source")"
profile="$(curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' -d "$update" "$base/v1/word-profiles")"
profile_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$profile")"
curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' -d "$update" "$base/v1/word-profiles" >/dev/null
details="$(curl --fail --silent -H "$auth" "$base/v1/word-profiles/$profile_id/details")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.history.length!==1||v.occurrences[0].encounter_count!==2)process.exit(1)' "$details"
observation="$(node -e 'process.stdout.write(JSON.stringify({word_profile_id:process.argv[1],sentence_id:process.argv[2],original_form:"Hello",result:"recognized_in_context",source:JSON.parse(process.argv[3])}))' "$profile_id" "$sentence_id" "$source")"
curl --fail --silent -H "$auth" -H 'Content-Type: application/json' -d "$observation" "$base/v1/word-observations" >/dev/null
book="$(curl --fail --silent -H "$auth" "$base/v1/vocabulary?status=unknown_meaning&language=en")"
node -e 'if(JSON.parse(process.argv[1]).length!==1)process.exit(1)' "$book"
bundle="$(curl --fail --silent -H "$auth" "$base/v1/vocabulary/export")"
curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d '{"availability":"archived"}' "$base/v1/media/$media_id/availability" >/dev/null
details="$(curl --fail --silent -H "$auth" "$base/v1/word-profiles/$profile_id/details")"
node -e 'if(JSON.parse(process.argv[1]).occurrences[0].media_id!==null)process.exit(1)' "$details"
curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d '{"path":"/tmp/moved-source.mp4","fingerprint":"m15-media","title":"M15 Source moved","kind":"video"}' "$base/v1/media" >/dev/null
details="$(curl --fail --silent -H "$auth" "$base/v1/word-profiles/$profile_id/details")"
node -e 'const o=JSON.parse(process.argv[1]).occurrences[0];if(o.media_id===null||o.sentence_id===null)process.exit(1)' "$details"
stop_api

start_api "$tmp/restored.sqlite" "$tmp/restored.log"
base="http://$address"
for _ in 1 2; do
  curl --fail --silent -H "$auth" -H 'Content-Type: application/json' -d "$bundle" "$base/v1/vocabulary/import" >/dev/null
done
restored="$(curl --fail --silent -H "$auth" "$base/v1/vocabulary/export")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.profiles.length!==1||v.history.length!==2||v.occurrences.length!==1||v.observations.length!==1||!v.history.some(h=>h.change_source==="import"))process.exit(1)' "$restored"
stop_api

echo "Milestone 1.5 vocabulary asset verification passed."
