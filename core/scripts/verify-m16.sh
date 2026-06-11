#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
token="m16-token"
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$PATH"
pid=""

cleanup() {
  [[ -z "$pid" ]] || kill -INT "$pid" 2>/dev/null || true
  [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

LLPLAYERNEXT_DB="$tmp/m16.sqlite" LLPLAYERNEXT_API_TOKEN="$token" \
  "$cargo_bin" run --quiet -p api-http >"$tmp/api.log" 2>&1 &
pid=$!
for _ in $(seq 1 100); do
  address="$(node -e '
    const fs=require("fs"); if(!fs.existsSync(process.argv[1]))process.exit(1);
    for(const line of fs.readFileSync(process.argv[1],"utf8").split("\n")){
      try{const v=JSON.parse(line);if(v.event==="api.started"){process.stdout.write(v.address);process.exit(0)}}catch{}
    } process.exit(1)' "$tmp/api.log" 2>/dev/null || true)"
  [[ -n "${address:-}" ]] && break
  sleep 0.1
done
base="http://$address"
auth="Authorization: Bearer $token"

summary="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d '{"language":"en","entries":[{"word":"hello","status":null},{"word":"world","status":"unknown_meaning"}],"default_status":"known_recognized","overwrite_existing":false}' \
  "$base/v1/vocabulary/import-external")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.created!==2||v.invalid!==0)process.exit(1)' "$summary"

book="$(curl --fail --silent -H "$auth" "$base/v1/vocabulary?language=en&status=known_recognized")"
profile_id="$(node -e 'const v=JSON.parse(process.argv[1]);if(v.length!==1)process.exit(1);process.stdout.write(v[0].profile.id)' "$book")"
details="$(curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d '{"user_definition":"a greeting","personal_note":"learned before"}' \
  "$base/v1/word-profiles/$profile_id/learning-content")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.profile.user_definition!=="a greeting"||v.profile.personal_note!=="learned before")process.exit(1)' "$details"

bundle="$(curl --fail --silent -H "$auth" "$base/v1/vocabulary/export")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.version!==3||v.profiles.length!==2)process.exit(1)' "$bundle"

dictionary="$(curl --silent -H "$auth" "$base/v1/dictionary?language=en&lemma=hello")"
node -e 'const v=JSON.parse(process.argv[1]);if(!Array.isArray(v.results)||!v.results[0].provider.id)process.exit(1)' "$dictionary"

echo "Milestone 1.6 learning experience verification passed."
