#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m18-token"

# Mock OpenSubtitles HTTP server
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

# Phrase SRT fixture
cat >"$tmp/phrase.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
Never give up.

2
00:00:02,000 --> 00:00:04,000
That test was a piece of cake.
SRT

start_api "$tmp/m18.sqlite" "$tmp/api.log" "$token" \
  "LLPLAYERNEXT_RESOURCES_DIR=$tmp/resources" \
  "LLPLAYERNEXT_OPENSUBTITLES_BASE_URL=http://127.0.0.1:$mock_port"

media="$(api_curl -d '{"path":"/tmp/m18.mp4","fingerprint":"m18","title":"M18","kind":"video"}' "$base/v1/media")"
media_id="$(json_get "$media" '.id')"

request="$(node -e 'process.stdout.write(JSON.stringify({path:process.argv[1],language:"en"}))' "$tmp/phrase.srt")"
track="$(api_curl -d "$request" "$base/v1/media/$media_id/subtitles")"
sentence_id="$(json_get "$track" '.sentences[0].id')"
ecdict_sentence_id="$(json_get "$track" '.sentences[1].id')"

# Phrase candidates from rule-based detection
candidates="$(api_curl "$base/v1/sentences/$sentence_id/phrase-candidates")"
json_assert "$candidates" 'v[0].canonical_form==="give up"' "phrase candidate should be 'give up'"

# Create phrase entry
source="$(node -e 'process.stdout.write(JSON.stringify({language:"en",kind:"phrase",canonical_form:"give up",display_form:"give up",status:"known_not_recognized",source:{sentence_id:process.argv[1],original_form:"give up",sentence_text:"Never give up.",media_title:"M18",media_fingerprint:"m18",start_ms:0,end_ms:2000,token_start:1,token_end:2}}))' "$sentence_id")"
phrase="$(api_curl -X PUT -d "$source" "$base/v1/lexical-entries")"
json_assert "$phrase" 'v.entry.kind==="phrase"&&v.occurrences.length===1' "lexical entry should be a phrase with 1 occurrence"

# Learning resources
resources="$(api_curl "$base/v1/learning-resources")"
json_assert "$resources" 'v.length===2' "should have 2 learning resources"

# ECDICT resource setup
ecdict_id="$(node -e 'const v=JSON.parse(process.argv[1]);process.stdout.write(v.find(x=>x.display_name==="ECDICT").id)' "$resources")"
mkdir -p "$tmp/resources"
cat >"$tmp/resources/$ecdict_id.data" <<'CSV'
word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio
go,go,move,,,,,,,,"p:went/gone i:going 3:goes",,
piece of cake,,easy task,,,,,,,,,,
CSV

# Lemmatization
normalized="$(api_curl -d '{"language":"en","value":"went"}' "$base/v1/lexical-normalization")"
json_assert "$normalized" 'v.normalized==="go"&&v.provider==="ecdict"' "ECDICT should normalize 'went' to 'go'"

# ECDICT phrase detection
ecdict_candidates="$(api_curl "$base/v1/sentences/$ecdict_sentence_id/phrase-candidates")"
json_assert "$ecdict_candidates" 'v.some(x=>x.canonical_form==="piece of cake"&&x.reason==="ECDICT phrase entry")' "ECDICT should detect 'piece of cake' phrase"

# Correction persistence
api_curl -d '{"language":"en","original":"went","corrected":"walk"}' "$base/v1/lexical-normalization/correct" >/dev/null

# Conflicting correction
api_curl -X PUT -d '{"language":"en","kind":"word","canonical_form":"run","display_form":"run","status":"known_recognized"}' "$base/v1/lexical-entries" >/dev/null
api_curl -X PUT -d '{"language":"en","kind":"word","canonical_form":"jog","display_form":"jog","status":"unknown_meaning"}' "$base/v1/lexical-entries" >/dev/null
conflict_status="$(curl -sS -o "$tmp/conflict.json" -w '%{http_code}' "${auth[@]}" -d '{"language":"en","original":"run","corrected":"jog"}' "$base/v1/lexical-normalization/correct")"
assert_eq "$conflict_status" "409" "conflicting correction should return 409"
json_assert "$(cat "$tmp/conflict.json")" 'v.code==="asset_conflict"' "conflict error should have asset_conflict code"

# Subtitle search
subtitle_key="m18-secret-api-key"
results="$(api_curl -d "{\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"query\":\"M18\"}" "$base/v1/subtitle-search")"
json_assert "$results" 'v[0].file_id===42' "subtitle search should find file_id 42"

hash_results="$(api_curl -d "{\"provider\":\"opensubtitles\",\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"moviehash\":\"0123456789abcdef\"}" "$base/v1/subtitle-search")"
json_assert "$hash_results" 'v[0].source==="OpenSubtitles"' "hash search should return OpenSubtitles source"

# Error responses
auth_status="$(curl -sS -o "$tmp/auth.json" -w '%{http_code}' "${auth[@]}" -d '{"api_key":"invalid","language":"en","query":"M18"}' "$base/v1/subtitle-search")"
assert_eq "$auth_status" "401" "invalid API key should return 401"
json_assert "$(cat "$tmp/auth.json")" 'v.code==="subtitle_authentication_failed"&&!v.retryable' "auth failure should be non-retryable"

limit_status="$(curl -sS -o "$tmp/limit.json" -w '%{http_code}' "${auth[@]}" -d '{"api_key":"limited","language":"en","query":"M18"}' "$base/v1/subtitle-search")"
assert_eq "$limit_status" "429" "rate-limited key should return 429"
json_assert "$(cat "$tmp/limit.json")" 'v.code==="subtitle_rate_limited"&&v.retryable' "rate limit should be retryable"

provider_status="$(curl -sS -o /dev/null -w '%{http_code}' "${auth[@]}" -d "{\"provider\":\"missing\",\"api_key\":\"$subtitle_key\",\"language\":\"en\",\"query\":\"M18\"}" "$base/v1/subtitle-search")"
assert_eq "$provider_status" "404" "unknown provider should return 404"

# Download
api_curl -d "{\"api_key\":\"$subtitle_key\",\"file_id\":42}" "$base/v1/subtitle-search/download" | grep -q Downloaded

# Export and secret hygiene (negative assertions: key MUST NOT appear)
bundle="$(api_curl "$base/v1/vocabulary/export")"
json_assert "$bundle" 'v.version===3&&v.lexical_entries.length>=1' "export should include lexical entries"
! grep -Fq "$subtitle_key" "$tmp/api.log" || { echo "FAIL: API log should not contain secret key" >&2; exit 1; }
[[ "$bundle" != *"$subtitle_key"* ]] || { echo "FAIL: export bundle should not contain secret key" >&2; exit 1; }

assert_eq "$(sqlite3 "$tmp/m18.sqlite" 'PRAGMA user_version;')" "9" "schema version should be 9"

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
  echo "Milestone 1.8 full headless regression passed."
fi
