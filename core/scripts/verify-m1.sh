#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
log="$tmp/api.log"
token="m1-smoke-token"
pid=""
cargo_bin="${CARGO:-$(command -v cargo || true)}"
if [[ -z "$cargo_bin" ]] && [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  cargo_bin="$HOME/.cargo/bin/cargo"
fi
if [[ -z "$cargo_bin" ]] && [[ -x "/opt/homebrew/opt/rustup/bin/cargo" ]]; then
  cargo_bin="/opt/homebrew/opt/rustup/bin/cargo"
fi
if [[ -z "$cargo_bin" ]]; then
  echo "cargo is required" >&2
  exit 1
fi
export PATH="$(dirname "$cargo_bin"):$PATH"

cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid"
    wait "$pid" || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cd "$root"
LLPLAYERNEXT_DB="$tmp/m1.sqlite" LLPLAYERNEXT_API_TOKEN="$token" \
  "$cargo_bin" run --quiet -p api-http >"$log" 2>&1 &
pid=$!

for _ in $(seq 1 100); do
  if [[ -s "$log" ]]; then
    address="$(node -e '
      const fs = require("fs");
      for (const line of fs.readFileSync(process.argv[1], "utf8").split("\n")) {
        try {
          const value = JSON.parse(line);
          if (value.event === "api.started") {
            process.stdout.write(value.address);
            process.exit(0);
          }
        } catch {}
      }
      process.exit(1);
    ' "$log" 2>/dev/null || true)"
    if [[ -n "$address" ]]; then
      break
    fi
  fi
  sleep 0.1
done

if [[ -z "${address:-}" ]]; then
  cat "$log"
  echo "M1 API failed to start" >&2
  exit 1
fi

base="http://$address"
auth="Authorization: Bearer $token"
curl --fail --silent "$base/v1/health" >/dev/null
unauthorized="$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST "$base/v1/media")"
[[ "$unauthorized" == "401" ]]

media='{"path":"/tmp/m1.mp4","fingerprint":"m1-fixture","title":"M1","kind":"video","duration_ms":5000}'
first="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' -d "$media" "$base/v1/media")"
second="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' -d "$media" "$base/v1/media")"
media_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$first")"
second_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$second")"
[[ "$media_id" == "$second_id" ]]

subtitle_path="$root/testdata/subtitles/timeline.srt"
subtitle_request="$(node -e 'process.stdout.write(JSON.stringify({path: process.argv[1], language: "en"}))' "$subtitle_path")"
track="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
track_again="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d "$subtitle_request" "$base/v1/media/$media_id/subtitles")"
track_id="$(node -e 'const v=JSON.parse(process.argv[1]); if(v.sentences.length!==4) process.exit(1); process.stdout.write(v.id)' "$track")"
sentence_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sentences[0].id)' "$track")"
track_again_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$track_again")"
[[ "$track_id" == "$track_again_id" ]]
curl --fail --silent -H "$auth" "$base/v1/subtitles/$track_id" >/dev/null

curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d '{"position_ms":1234}' "$base/v1/media/$media_id/progress" >/dev/null
progress="$(curl --fail --silent -H "$auth" "$base/v1/media/$media_id/progress")"
node -e 'if (JSON.parse(process.argv[1]).position_ms !== 1234) process.exit(1)' "$progress"

word='{"language":"en","lemma":"Hello","display_form":"Hello","status":"known_recognized"}'
updated_profile="$(curl --fail --silent -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d "$word" "$base/v1/word-profiles")"
profile_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$updated_profile")"
profile="$(curl --fail --silent -H "$auth" "$base/v1/word-profiles?language=en&lemma=hello")"
node -e 'if (JSON.parse(process.argv[1]).status !== "known_recognized") process.exit(1)' "$profile"
batch="$(curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d '{"language":"en","lemmas":["hello","missing"]}' "$base/v1/word-profiles/batch")"
node -e 'if (JSON.parse(process.argv[1]).length !== 1) process.exit(1)' "$batch"
observation="$(node -e 'process.stdout.write(JSON.stringify({word_profile_id:process.argv[1],sentence_id:process.argv[2],original_form:"Hello",result:"recognized_in_context"}))' "$profile_id" "$sentence_id")"
curl --fail --silent -H "$auth" -H 'Content-Type: application/json' \
  -d "$observation" "$base/v1/word-observations" >/dev/null
diagnosis="$(curl --fail --silent -H "$auth" "$base/v1/sentences/$sentence_id/diagnosis")"
node -e 'if (!JSON.parse(process.argv[1]).hints.length) process.exit(1)' "$diagnosis"

kill -INT "$pid"
wait "$pid"
pid=""
grep -q '"event":"api.stopped"' "$log"
echo "M1 headless API smoke test passed."
