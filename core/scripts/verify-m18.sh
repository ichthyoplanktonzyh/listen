#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
export PATH="$(dirname "$cargo_bin"):$PATH"
tmp="$(mktemp -d)"
token="m18-token"
api_pid=""
mock_pid=""

cleanup() {
  [[ -z "$api_pid" ]] || kill "$api_pid" 2>/dev/null || true
  [[ -z "$mock_pid" ]] || kill "$mock_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/mock.py" <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path.startswith("/subtitles"):
            if self.headers.get("Api-Key") == "invalid":
                self.send_response(401); self.end_headers(); return
            if self.headers.get("Api-Key") == "limited":
                self.send_response(429); self.end_headers(); return
            body={"data":[{"id":"mock-subtitle","attributes":{"language":"en","release":"Mock release","ratings":9.0,"download_count":12,"files":[{"file_id":42}]}}]}
            self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(json.dumps(body).encode())
        elif self.path == "/file":
            self.send_response(200); self.end_headers(); self.wfile.write(b"1\n00:00:00,000 --> 00:00:01,000\nDownloaded\n")
    def do_POST(self):
        if self.path == "/download":
            body={"link":f"http://127.0.0.1:{self.server.server_port}/file"}
            self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(json.dumps(body).encode())
server=HTTPServer(("127.0.0.1",0),Handler)
print(server.server_port, flush=True)
server.serve_forever()
PY
/usr/bin/python3 "$tmp/mock.py" >"$tmp/mock.port" &
mock_pid=$!
for _ in $(seq 1 50); do [[ -s "$tmp/mock.port" ]] && break; sleep 0.1; done
mock_port="$(cat "$tmp/mock.port")"

cat >"$tmp/phrase.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
Never give up.

2
00:00:02,000 --> 00:00:04,000
That test was a piece of cake.
SRT

LLPLAYERNEXT_DB="$tmp/m18.sqlite" \
LLPLAYERNEXT_RESOURCES_DIR="$tmp/resources" \
LLPLAYERNEXT_API_TOKEN="$token" \
LLPLAYERNEXT_OPENSUBTITLES_BASE_URL="http://127.0.0.1:$mock_port" \
  "$cargo_bin" run --quiet -p api-http >"$tmp/api.log" 2>&1 &
api_pid=$!
for _ in $(seq 1 100); do
  address="$(node -e 'const fs=require("fs");if(!fs.existsSync(process.argv[1]))process.exit(1);for(const line of fs.readFileSync(process.argv[1],"utf8").split("\n")){try{const v=JSON.parse(line);if(v.event==="api.started"){process.stdout.write(v.address);process.exit(0)}}catch{}}process.exit(1)' "$tmp/api.log" 2>/dev/null || true)"
  [[ -n "${address:-}" ]] && break
  sleep 0.1
done
base="http://$address"
auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")

media="$(curl -fsS "${auth[@]}" -d '{"path":"/tmp/m18.mp4","fingerprint":"m18","title":"M18","kind":"video"}' "$base/v1/media")"
media_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id)' "$media")"
request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$tmp/phrase.srt")"
track="$(curl -fsS "${auth[@]}" -d "$request" "$base/v1/media/$media_id/subtitles")"
sentence_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sentences[0].id)' "$track")"
ecdict_sentence_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).sentences[1].id)' "$track")"
candidates="$(curl -fsS "${auth[@]}" "$base/v1/sentences/$sentence_id/phrase-candidates")"
node -e 'const v=JSON.parse(process.argv[1]);if(v[0].canonical_form!=="give up")process.exit(1)' "$candidates"

source="$(node -e 'process.stdout.write(JSON.stringify({language:"en",kind:"phrase",canonical_form:"give up",display_form:"give up",status:"known_not_recognized",source:{sentence_id:process.argv[1],original_form:"give up",sentence_text:"Never give up.",media_title:"M18",media_fingerprint:"m18",start_ms:0,end_ms:2000,token_start:1,token_end:2}}))' "$sentence_id")"
phrase="$(curl -fsS -X PUT "${auth[@]}" -d "$source" "$base/v1/lexical-entries")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.entry.kind!=="phrase"||v.occurrences.length!==1)process.exit(1)' "$phrase"
resources="$(curl -fsS "${auth[@]}" "$base/v1/learning-resources")"
node -e 'if(JSON.parse(process.argv[1]).length!==2)process.exit(1)' "$resources"
ecdict_id="$(node -e 'const v=JSON.parse(process.argv[1]);process.stdout.write(v.find(x=>x.display_name==="ECDICT").id)' "$resources")"
mkdir -p "$tmp/resources"
cat >"$tmp/resources/$ecdict_id.data" <<'CSV'
word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio
go,go,move,,,,,,,,"p:went/gone i:going 3:goes",,
piece of cake,,easy task,,,,,,,,,,
CSV
normalized="$(curl -fsS "${auth[@]}" -d '{"language":"en","value":"went"}' "$base/v1/lexical-normalization")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.normalized!=="go"||v.provider!=="ecdict")process.exit(1)' "$normalized"
ecdict_candidates="$(curl -fsS "${auth[@]}" "$base/v1/sentences/$ecdict_sentence_id/phrase-candidates")"
node -e 'const v=JSON.parse(process.argv[1]);if(!v.some(x=>x.canonical_form==="piece of cake"&&x.reason==="ECDICT phrase entry"))process.exit(1)' "$ecdict_candidates"
curl -fsS "${auth[@]}" -d '{"language":"en","original":"went","corrected":"walk"}' "$base/v1/lexical-normalization/correct" >/dev/null
curl -fsS -X PUT "${auth[@]}" -d '{"language":"en","kind":"word","canonical_form":"run","display_form":"run","status":"known_recognized"}' "$base/v1/lexical-entries" >/dev/null
curl -fsS -X PUT "${auth[@]}" -d '{"language":"en","kind":"word","canonical_form":"jog","display_form":"jog","status":"unknown_meaning"}' "$base/v1/lexical-entries" >/dev/null
conflict_status="$(curl -sS -o "$tmp/conflict.json" -w '%{http_code}' "${auth[@]}" -d '{"language":"en","original":"run","corrected":"jog"}' "$base/v1/lexical-normalization/correct")"
[[ "$conflict_status" == "409" ]]
node -e 'if(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).code!=="asset_conflict")process.exit(1)' "$tmp/conflict.json"

subtitle_key="m18-secret-api-key"
results="$(curl -fsS "${auth[@]}" -d "{\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"query\":\"M18\"}" "$base/v1/subtitle-search")"
node -e 'if(JSON.parse(process.argv[1])[0].file_id!==42)process.exit(1)' "$results"
hash_results="$(curl -fsS "${auth[@]}" -d "{\"provider\":\"opensubtitles\",\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"moviehash\":\"0123456789abcdef\"}" "$base/v1/subtitle-search")"
node -e 'if(JSON.parse(process.argv[1])[0].source!=="OpenSubtitles")process.exit(1)' "$hash_results"
auth_status="$(curl -sS -o "$tmp/auth.json" -w '%{http_code}' "${auth[@]}" -d '{"api_key":"invalid","language":"en","query":"M18"}' "$base/v1/subtitle-search")"
[[ "$auth_status" == "401" ]]
node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(v.code!=="subtitle_authentication_failed"||v.retryable)process.exit(1)' "$tmp/auth.json"
limit_status="$(curl -sS -o "$tmp/limit.json" -w '%{http_code}' "${auth[@]}" -d '{"api_key":"limited","language":"en","query":"M18"}' "$base/v1/subtitle-search")"
[[ "$limit_status" == "429" ]]
node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(v.code!=="subtitle_rate_limited"||!v.retryable)process.exit(1)' "$tmp/limit.json"
provider_status="$(curl -sS -o /dev/null -w '%{http_code}' "${auth[@]}" -d "{\"provider\":\"missing\",\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"query\":\"M18\"}" "$base/v1/subtitle-search")"
[[ "$provider_status" == "404" ]]
curl -fsS "${auth[@]}" -d "{\"api_key\":\"$subtitle_key\",\"file_id\":42}" "$base/v1/subtitle-search/download" | grep -q Downloaded

bundle="$(curl -fsS "${auth[@]}" "$base/v1/vocabulary/export")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.version!==3||v.lexical_entries.length<1)process.exit(1)' "$bundle"
! grep -Fq "$subtitle_key" "$tmp/api.log"
[[ "$bundle" != *"$subtitle_key"* ]]
[[ "$(sqlite3 "$tmp/m18.sqlite" 'PRAGMA user_version;')" == "7" ]]

echo "Milestone 1.8 lexical assets and subtitle-provider verification passed."

if [[ "${LLPLAYERNEXT_M18_SKIP_HISTORY:-0}" != "1" ]]; then
  "$cargo_bin" fmt --check
  "$cargo_bin" test --workspace
  "$cargo_bin" clippy --workspace --all-targets -- -D warnings
  (
    cd "$root/apps/desktop"
    "${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}" analyze
    "${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}" test
  )
  "$root/scripts/validate-contracts.sh"
  "$root/scripts/verify-m1.sh"
  "$root/scripts/verify-m15.sh"
  "$root/scripts/verify-m16.sh"
  "$root/scripts/verify-m17.sh"
  echo "Milestone 1.8 full headless regression passed."
fi
