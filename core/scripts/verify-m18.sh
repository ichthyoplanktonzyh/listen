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
candidates="$(curl -fsS "${auth[@]}" "$base/v1/sentences/$sentence_id/phrase-candidates")"
node -e 'const v=JSON.parse(process.argv[1]);if(v[0].canonical_form!=="give up")process.exit(1)' "$candidates"

source="$(node -e 'process.stdout.write(JSON.stringify({language:"en",kind:"phrase",canonical_form:"give up",display_form:"give up",status:"known_not_recognized",source:{sentence_id:process.argv[1],original_form:"give up",sentence_text:"Never give up.",media_title:"M18",media_fingerprint:"m18",start_ms:0,end_ms:2000,token_start:1,token_end:2}}))' "$sentence_id")"
phrase="$(curl -fsS -X PUT "${auth[@]}" -d "$source" "$base/v1/lexical-entries")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.entry.kind!=="phrase"||v.occurrences.length!==1)process.exit(1)' "$phrase"
normalized="$(curl -fsS "${auth[@]}" -d '{"language":"en","value":"went"}' "$base/v1/lexical-normalization")"
node -e 'if(JSON.parse(process.argv[1]).normalized!=="go")process.exit(1)' "$normalized"
curl -fsS "${auth[@]}" -d '{"language":"en","original":"went","corrected":"walk"}' "$base/v1/lexical-normalization/correct" >/dev/null

resources="$(curl -fsS "${auth[@]}" "$base/v1/learning-resources")"
node -e 'if(JSON.parse(process.argv[1]).length!==2)process.exit(1)' "$resources"
results="$(curl -fsS "${auth[@]}" -d '{"api_key":"test","language":"en","query":"M18"}' "$base/v1/subtitle-search")"
node -e 'if(JSON.parse(process.argv[1])[0].file_id!==42)process.exit(1)' "$results"
curl -fsS "${auth[@]}" -d '{"api_key":"test","file_id":42}' "$base/v1/subtitle-search/download" | grep -q Downloaded

bundle="$(curl -fsS "${auth[@]}" "$base/v1/vocabulary/export")"
node -e 'const v=JSON.parse(process.argv[1]);if(v.version!==3||v.lexical_entries.length<1)process.exit(1)' "$bundle"
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
