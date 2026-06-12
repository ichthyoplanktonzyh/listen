#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$PATH"
tmp="$(mktemp -d)"
token="m19-token"
api_pid=""

cleanup() {
  [[ -z "$api_pid" ]] || kill "$api_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/m19.srt" <<'SRT'
1
00:00:00,100 --> 00:00:02,100
Did you want to go?

2
00:00:02,100 --> 00:00:04,100
Hello world.
SRT

LLPLAYERNEXT_DB="$tmp/m19.sqlite" LLPLAYERNEXT_API_TOKEN="$token" \
  "$cargo_bin" run --quiet -p api-http >"$tmp/api.log" 2>&1 &
api_pid=$!
for _ in $(seq 1 100); do
  address="$(node -e 'const fs=require("fs");if(!fs.existsSync(process.argv[1]))process.exit(1);for(const line of fs.readFileSync(process.argv[1],"utf8").split("\n")){try{const v=JSON.parse(line);if(v.event==="api.started"){process.stdout.write(v.address);process.exit(0)}}catch{}}process.exit(1)' "$tmp/api.log" 2>/dev/null || true)"
  [[ -n "${address:-}" ]] && break
  sleep 0.1
done
base="http://$address"
auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")

media="$(curl -fsS "${auth[@]}" -d '{"path":"/tmp/m19.mp4","fingerprint":"m19","title":"M19","kind":"video"}' "$base/v1/media")"
media_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$media")"
request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$tmp/m19.srt")"
track="$(curl -fsS "${auth[@]}" -d "$request" "$base/v1/media/$media_id/subtitles")"
track_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$track")"
sentence_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sentences[0].id)' "$track")"

providers="$(curl -fsS "${auth[@]}" "$base/v1/pronunciation/providers")"
node -e 'const v=JSON.parse(process.argv[1]);if(v[0].id!=="cmudict-deterministic"||v[0].phoneme_sets[0]!=="arpabet")process.exit(1)' "$providers"
lookup="$(curl -fsS "${auth[@]}" "$base/v1/pronunciation/lookup?word=hello")"
node -e 'const v=JSON.parse(process.argv[1]);if(!v.variants[0].display_ipa.includes("oʊ"))process.exit(1)' "$lookup"
analysis="$(curl -fsS "${auth[@]}" -d "{\"sentence_id\":\"$sentence_id\"}" "$base/v1/pronunciation/analyze-sentence")"
node -e 'const v=JSON.parse(process.argv[1]);if(!v.rules.some(x=>x.rule_id==="assimilation-did-you")||v.rules.some(x=>x.evidence_source==="detected_in_audio"))process.exit(1)' "$analysis"
timings="$(curl -fsS "${auth[@]}" -d '{"timings":[]}' "$base/v1/subtitles/$track_id/word-timings")"
node -e 'const v=JSON.parse(process.argv[1]);if(!v.length||v.some(x=>x.timing_source!=="estimated")||v.some((x,i)=>i&&x.start_ms<v[i-1].end_ms))process.exit(1)' "$timings"
reported="$(node -e 'const v=JSON.parse(process.argv[1]);for(const x of v){x.timing_source="asr_reported";x.provider_id="test-asr";x.provider_version="v1";x.confidence=.9}process.stdout.write(JSON.stringify({timings:v}))' "$timings")"
accepted="$(curl -fsS "${auth[@]}" -X POST -d "$reported" "$base/v1/subtitles/$track_id/word-timings")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.some(x=>x.timing_source!=="asr_reported"))process.exit(1)' "$accepted"
preserved="$(curl -fsS "${auth[@]}" "$base/v1/subtitles/$track_id/word-timings")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.some(x=>x.timing_source!=="asr_reported"))process.exit(1)' "$preserved"
[[ "$(sqlite3 "$tmp/m19.sqlite" 'PRAGMA user_version;')" == "8" ]]

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
