#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

setup_test_dir
resolve_cargo
token="m16-token"

start_api "$tmp/m16.sqlite" "$tmp/api.log" "$token"
base="http://$address"

summary="$(api_curl -d '{"language":"en","entries":[{"word":"hello","status":null},{"word":"world","status":"unknown_meaning"}],"default_status":"known_recognized","overwrite_existing":false}' "$base/v1/vocabulary/import-external")"
json_assert "$summary" 'v.initialized===2&&v.invalid===0' "import-external should initialize 2 entries"

book="$(api_curl "$base/v1/vocabulary?language=en&status=known_recognized")"
entry_id="$(json_get "$book" '[0].entry.id')"
json_assert "$book" 'v.length===1' "should have 1 known_recognized entry"

details="$(api_curl -X PUT -d '{"user_definition":"a greeting","personal_note":"learned before"}' "$base/v1/lexical-entries/$entry_id/learning-content")"
json_assert "$details" 'v.entry.user_definition==="a greeting"&&v.entry.personal_note==="learned before"' "learning content should be persisted"

bundle="$(api_curl "$base/v1/vocabulary/export")"
json_assert "$bundle" 'v.version===5&&v.lexical_entries.length===2' "export should have version 5 with 2 lexical entries"

dictionary="$(api_curl "$base/v1/dictionary?language=en&lemma=hello")"
json_assert "$dictionary" 'Array.isArray(v.results)&&v.results[0].provider.id' "dictionary should return results with provider id"

echo "Milestone 1.6 learning experience verification passed."
