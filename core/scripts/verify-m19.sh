#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m19-token"

cat >"$tmp/m19.srt" <<'SRT'
1
00:00:00,100 --> 00:00:02,100
Did you want to go?

2
00:00:02,100 --> 00:00:04,100
Hello world.
SRT

start_api "$tmp/m19.sqlite" "$tmp/api.log" "$token"
base="http://$address"

media="$(api_curl -d '{"path":"/tmp/m19.mp4","fingerprint":"m19","title":"M19","kind":"video"}' "$base/v1/media")"
media_id="$(json_get "$media" '.id')"
request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$tmp/m19.srt")"
track="$(api_curl -d "$request" "$base/v1/media/$media_id/subtitles")"
track_id="$(json_get "$track" '.id')"
sentence_id="$(json_get "$track" '.sentences[0].id')"

providers="$(api_curl "$base/v1/pronunciation/providers")"
json_assert "$providers" 'v[0].id==="cmudict-deterministic"&&v[0].phoneme_sets[0]==="arpabet"' "pronunciation providers should include cmudict-deterministic with arpabet"

lookup="$(api_curl "$base/v1/pronunciation/lookup?word=hello")"
assert_contains "$lookup" "oʊ" "hello pronunciation should contain IPA oʊ"

analysis="$(api_curl -d "{\"sentence_id\":\"$sentence_id\"}" "$base/v1/pronunciation/analyze-sentence")"
json_assert "$analysis" 'v.rules.some(x=>x.rule_id==="assimilation-did-you")&&!v.rules.some(x=>x.evidence_source==="detected_in_audio")' "analysis should include assimilation-did-you rule without audio evidence"

rules="$(api_curl "$base/v1/pronunciation/rules")"
json_assert "$rules" 'v.rules.length>=15&&v.rules.length<=25&&!v.rules.some(x=>!x.rule_id||!x.description||!x.condition||!x.example||!x.counterexample)' "rules should have 15-25 entries with required fields"

timings="$(api_curl -d '{"timings":[]}' "$base/v1/subtitles/$track_id/word-timings")"
json_assert "$timings" 'v.length>0&&v.every(x=>x.timing_source==="estimated")&&v.every((x,i)=>i===0||x.start_ms>=v[i-1].end_ms)' "estimated timings should be non-empty and monotonic"

reported="$(node -e 'const v=JSON.parse(process.argv[1]);for(const x of v){x.timing_source="asr_reported";x.provider_id="test-asr";x.provider_version="v1";x.confidence=.9}process.stdout.write(JSON.stringify({timings:v}))' "$timings")"
accepted="$(api_curl -X POST -d "$reported" "$base/v1/subtitles/$track_id/word-timings")"
json_assert "$accepted" 'v.every(x=>x.timing_source==="asr_reported")' "accepted timings should all be asr_reported"

preserved="$(api_curl "$base/v1/subtitles/$track_id/word-timings")"
json_assert "$preserved" 'v.every(x=>x.timing_source==="asr_reported")' "preserved timings should remain asr_reported"

assert_eq "$(sqlite3 "$tmp/m19.sqlite" 'PRAGMA user_version;')" "9" "database schema version should be 9"

echo "Milestone 1.9 pronunciation and word-sync API verification passed."

if [[ "${LLPLAYERNEXT_M19_SKIP_HISTORY:-0}" != "1" ]]; then
  "$cargo_bin" fmt --check
  "$cargo_bin" test --workspace
  "$cargo_bin" clippy --workspace --all-targets -- -D warnings
  (
    cd "$root/apps/desktop"
    "${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}" analyze
    "${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}" test
  )
  "$root/scripts/validate-contracts.sh"
  "$root/scripts/verify-m18.sh"
  echo "Milestone 1.9 full headless regression passed."
fi
