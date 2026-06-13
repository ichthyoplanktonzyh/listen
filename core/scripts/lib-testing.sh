#!/usr/bin/env bash
# Shared utilities for LLPlayerNext verification and test scripts.
#
# Usage: source "$(dirname "$0")/lib-testing.sh"
#
# Provides:
#   - Project root and tool resolution
#   - Temporary directory lifecycle
#   - API server lifecycle (start/stop/wait-for-ready)
#   - curl and assertion helpers
#   - JSON construction/parsing via node

set -euo pipefail

# ── project root ──────────────────────────────────────────────────────────

lib_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── tool resolution ───────────────────────────────────────────────────────

resolve_cargo() {
  cargo_bin="${CARGO:-/opt/homebrew/opt/rustup/bin/cargo}"
  export PATH="$(dirname "$cargo_bin"):$PATH"
}

resolve_flutter() {
  flutter_bin="${FLUTTER:-$HOME/.local/share/flutter/bin/flutter}"
}

# ── temporary directory ───────────────────────────────────────────────────

setup_test_dir() {
  tmp="$(mktemp -d)"
}

cleanup() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" 2>/dev/null || true
  fi
  if [[ -n "${mock_pid:-}" ]]; then
    kill "$mock_pid" 2>/dev/null || true
  fi
  if [[ -n "${tmp:-}" ]]; then
    rm -rf "$tmp"
  fi
}

# ── API server ────────────────────────────────────────────────────────────

# start_api <db_path> <log_path> <token> [extra_env_vars...]
#
# Sets globals: api_pid, address, base, auth
start_api() {
  local db="$1";  shift
  local log="$1"; shift
  local token="$1"; shift

  # shellcheck disable=SC2068
  LLPLAYERNEXT_DB="$db" LLPLAYERNEXT_API_TOKEN="$token" $@ \
    "$cargo_bin" run --quiet -p api-http >"$log" 2>&1 &
  api_pid=$!

  # Wait for "api.started" event in the JSON log.
  local waited_ms=0
  while [[ $waited_ms -lt 30000 ]]; do
    address="$(node -e '
const fs=require("fs");
if(!fs.existsSync(process.argv[1]))process.exit(1);
for(const line of fs.readFileSync(process.argv[1],"utf8").split("\n")){
  try{const v=JSON.parse(line);if(v.event==="api.started"){process.stdout.write(v.address);process.exit(0)}}catch{}
}
process.exit(1)
' "$log" 2>/dev/null || true)"
    [[ -n "${address:-}" ]] && break
    sleep 0.1
    waited_ms=$((waited_ms + 100))
  done

  if [[ -z "${address:-}" ]]; then
    echo "ERROR: api-http did not emit api.started within 30s" >&2
    exit 1
  fi

  base="http://$address"
  auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")
}

# stop_api
#
# Gracefully stops the running API server (if any) and resets the globals.
stop_api() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" 2>/dev/null || true
    wait "$api_pid" 2>/dev/null || true
    api_pid=""
  fi
}

# ── curl helper ───────────────────────────────────────────────────────────

# api_curl [curl_flags...] -- <relative_url> [extra_curl_args...]
#
# Wraps curl -fsS with the auth array and base URL already set.
api_curl() {
  curl -fsS "${auth[@]}" "$@"
}

# api_curl_raw <relative_url>
#
# Gets the raw response body for a relative URL (no auth headers).
api_curl_raw() {
  curl -fsS "$base$1"
}

# ── JSON helpers (node.js) ────────────────────────────────────────────────

# json_make <json_string> — writes JSON to stdout (identity, but documents intent)
json_make() {
  node -e 'process.stdout.write(JSON.stringify('"$1"'))'
}

# json_get <json_string> <path> — extracts a value from JSON
json_get() {
  node -e 'process.stdout.write(JSON.parse(process.argv[1])'"$2"')' "$1"
}

# json_assert <json_string> <predicate_js> <message>
json_assert() {
  node -e '
const v=JSON.parse(process.argv[1]);
if(!('"$2"')){process.stderr.write(process.argv[2]+"\n");process.exit(1)}
' "$1" "$3" || exit 1
}

# ── assertion helpers ─────────────────────────────────────────────────────

# assert_eq <actual> <expected> <description>
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$3" "$2" "$1" >&2
    exit 1
  fi
}

# assert_contains <haystack> <needle> <description>
assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    printf 'FAIL: %s\n  needle "%s" not found in output\n' "$3" "$2" >&2
    exit 1
  fi
}

# assert_not_empty <value> <description>
assert_not_empty() {
  if [[ -z "$1" ]]; then
    printf 'FAIL: %s is empty\n' "$2" >&2
    exit 1
  fi
}
