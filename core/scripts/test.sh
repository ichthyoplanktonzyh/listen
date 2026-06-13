#!/usr/bin/env bash
# LLPlayerNext unified test runner
#
# Usage:
#   ./scripts/test.sh                      # --full (default)
#   ./scripts/test.sh --quick              # fmt + clippy + Rust lib tests + analyze
#   ./scripts/test.sh --rust               # Rust checks + tests
#   ./scripts/test.sh --flutter            # Flutter checks + tests
#   ./scripts/test.sh --full               # Everything + contracts
#
# Flags:
#   --json       Machine-readable JSON output
#   --verbose    Stream raw output (no capture)
#   --debug      Print test.sh internal execution steps
#   --strict     Treat warnings as errors and require Cargo.lock
#
# Pass-through:
#   ./scripts/test.sh --rust -- --nocapture --test-threads=1
#   (appends to cargo test and flutter test commands)

set -euo pipefail

# ── preamble ──────────────────────────────────────────────────────────────

root="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve cargo: try env var, then PATH, then common locations
cargo_bin="${CARGO:-$(command -v cargo || true)}"
if [[ -z "$cargo_bin" ]] && [[ -x "/opt/homebrew/opt/rustup/bin/cargo" ]]; then
  cargo_bin="/opt/homebrew/opt/rustup/bin/cargo"
fi
if [[ -z "$cargo_bin" ]] && [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  cargo_bin="$HOME/.cargo/bin/cargo"
fi
if [[ -z "$cargo_bin" ]]; then
  echo "ERROR: cargo not found" >&2; exit 1
fi
export PATH="$(dirname "$cargo_bin"):$PATH"

# Resolve flutter
flutter_bin="${FLUTTER:-$(command -v flutter || true)}"
if [[ -z "$flutter_bin" ]]; then
  flutter_bin="$HOME/.local/share/flutter/bin/flutter"
fi

# ── argument parsing ──────────────────────────────────────────────────────

MODE="full"
JSON_OUTPUT=false
VERBOSE=false
DEBUG=false
STRICT=false
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)   MODE="quick";   shift ;;
    --rust)    MODE="rust";    shift ;;
    --flutter) MODE="flutter"; shift ;;
    --full)    MODE="full";    shift ;;
    --json)    JSON_OUTPUT=true; shift ;;
    --verbose) VERBOSE=true;   shift ;;
    --debug)   DEBUG=true;     shift ;;
    --strict)  STRICT=true;    shift ;;
    --)        shift; PASSTHROUGH=("$@"); break ;;
    *)         echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ── setup ─────────────────────────────────────────────────────────────────

cd "$root"

LOG_DIR="$(mktemp -d)"
FAILED=0

cleanup_logs() {
  if [[ ${FAILED:-0} -eq 0 ]]; then
    rm -rf "$LOG_DIR"
  fi
}
trap cleanup_logs EXIT

if $DEBUG; then
  echo "[test.sh] MODE=$MODE JSON=$JSON_OUTPUT STRICT=$STRICT" >&2
  echo "[test.sh] LOG_DIR=$LOG_DIR" >&2
  echo "[test.sh] PASSTHROUGH=${PASSTHROUGH[*]:-}" >&2
fi

NOW=$(date +%s)

# ── check registry ────────────────────────────────────────────────────────
# Each check: "name|category|command_type"
# category: rust, flutter, contracts (used for mode filtering)
# command_type: fmt, clippy, test, analyze, flutter_test, contracts

CHECKS=(
  "cargo fmt|rust|fmt"
  "cargo clippy|rust|clippy"
  "cargo test (lib)|rust|quick_test"
  "cargo test|rust|test"
  "flutter analyze|flutter|analyze"
  "flutter test|flutter|flutter_test"
  "contracts|contracts|contracts"
)

# ── error extraction ──────────────────────────────────────────────────────

extract_errors() {
  local type="$1"; local log="$2"

  case "$type" in
    fmt)
      # cargo fmt --check writes "Diff in <file>:" lines
      grep -E '^Diff in' "$log" 2>/dev/null | head -20 || true
      ;;
    clippy)
      # Extract lines with file locations: file:line:col
      grep -n -E '^error(\[.*\])?:|warning(\[.*\])?:' "$log" 2>/dev/null | head -20 || true
      ;;
    test|quick_test)
      # Extract failure lines and FAILED result summaries
      grep -E '^test .* \.\.\. FAILED$' "$log" 2>/dev/null || true
      grep -E '^test result: FAILED' "$log" 2>/dev/null || true
      ;;
    analyze)
      # Flutter analyze output: `error •`, `warning •`
      grep -n -E 'error •|warning •' "$log" 2>/dev/null | head -20 || true
      ;;
    flutter_test)
      # Extract test failures
      grep -n -E 'FAILED|✗|Expected:|Actual:' "$log" 2>/dev/null | head -20 || true
      ;;
    contracts)
      # Contract validation errors
      grep -n -E 'Error|missing|throw' "$log" 2>/dev/null | head -20 || true
      ;;
    *)
      # Fallback: last 20 lines
      tail -20 "$log" 2>/dev/null || true
      ;;
  esac
}

# Extract a one-line summary from the log on success
extract_summary() {
  local type="$1"; local log="$2"

  case "$type" in
    test|quick_test)
      # Aggregate test results across all crates
      local passed=0 failed=0
      while IFS= read -r line; do
        local p=0 f=0
        p=$(echo "$line" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')
        f=$(echo "$line" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
        passed=$((passed + ${p:-0}))
        failed=$((failed + ${f:-0}))
      done < <(grep -E '^test result:' "$log" 2>/dev/null || true)
      echo "$passed passed, $failed failed"
      ;;
    flutter_test)
      grep -E '^[0-9]+:[0-9]+ \+[0-9]+: ' "$log" 2>/dev/null | tail -1 || echo "ok"
      ;;
    contracts)
      grep -E '^Validated' "$log" 2>/dev/null | head -1 || echo "ok"
      ;;
    *)
      echo "ok"
      ;;
  esac
}

# ── run one check ─────────────────────────────────────────────────────────
# Returns: sets global RC, DURATION_MS, ERROR_LINES, SUMMARY

run_check() {
  local name="$1"; local category="$2"; local type="$3"
  local log="$LOG_DIR/${name// /-}.log"
  local rc=0

  if $DEBUG; then
    echo "[test.sh] running: $name (type=$type)" >&2
  fi

  # Build command and working directory
  local cmd=()
  local run_dir="$root"
  case "$type" in
    fmt)
      cmd=("$cargo_bin" "fmt" "--check")
      ;;
    clippy)
      cmd=("$cargo_bin" "clippy" "--workspace" "--all-targets")
      $STRICT && cmd+=("--locked" "--" "-D" "warnings")
      ;;
    test)
      cmd=("$cargo_bin" "test" "--workspace")
      $STRICT && cmd+=("--locked")
      [[ ${#PASSTHROUGH[@]} -gt 0 ]] && cmd+=("--" "${PASSTHROUGH[@]}")
      ;;
    quick_test)
      cmd=("$cargo_bin" "test" "--workspace" "--lib")
      $STRICT && cmd+=("--locked")
      [[ ${#PASSTHROUGH[@]} -gt 0 ]] && cmd+=("--" "${PASSTHROUGH[@]}")
      ;;
    analyze)
      cmd=("$flutter_bin" "analyze")
      $STRICT && cmd+=("--fatal-infos" "--fatal-warnings")
      run_dir="$root/apps/desktop"
      ;;
    flutter_test)
      cmd=("$flutter_bin" "test")
      [[ ${#PASSTHROUGH[@]} -gt 0 ]] && cmd+=("${PASSTHROUGH[@]}")
      run_dir="$root/apps/desktop"
      ;;
    contracts)
      cmd=("$root/scripts/validate-contracts.sh")
      ;;
  esac

  if $DEBUG; then
    echo "[test.sh] cmd: ${cmd[*]}" >&2
  fi

  local start_ms
  start_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)

  set +e
  if $VERBOSE; then
    (cd "$run_dir" && "${cmd[@]}" >"$log" 2>&1)
    rc=$?
    cat "$log"
  else
    (cd "$run_dir" && "${cmd[@]}" >"$log" 2>&1)
    rc=$?
  fi
  set -e

  local end_ms
  end_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
  DURATION_MS=$((end_ms - start_ms))

  if [[ $rc -eq 0 ]]; then
    SUMMARY="$(extract_summary "$type" "$log")"
  else
    ERROR_LINES="$(extract_errors "$type" "$log")"
    if [[ -z "$ERROR_LINES" ]]; then
      # Fallback: last 20 lines of the log
      ERROR_LINES="(no structured errors extracted; showing tail of log)
$(tail -20 "$log" 2>/dev/null || true)"
    fi
  fi

  return $rc
}

# ── mode filtering ────────────────────────────────────────────────────────

should_run() {
  local category="$1"
  case "$MODE" in
    quick)   [[ "$category" == "rust" || "$category" == "flutter" ]] && [[ "$category" != "test" ]] || return 1 ;;
    rust)    [[ "$category" == "rust" ]] || return 1 ;;
    flutter) [[ "$category" == "flutter" ]] || return 1 ;;
    full)    return 0 ;;
  esac
}

# Include the quick unit-test subset only in quick mode.
should_run_check() {
  local category="$1"; local type="$2"
  if [[ "$type" == "quick_test" && "$MODE" != "quick" ]]; then
    return 1
  fi
  case "$MODE" in
    quick)
      # Include quick_test (lib unit only), skip full test/flutter_test/contracts
      [[ "$type" == "quick_test" ]] && return 0
      [[ "$type" != "test" && "$type" != "flutter_test" && "$type" != "contracts" ]] || return 1
      ;;
  esac
  return 0
}

# ── main ──────────────────────────────────────────────────────────────────

PASSED=0; SKIPPED=0
declare -a RESULTS=()

for entry in "${CHECKS[@]}"; do
  IFS='|' read -r name category type <<<"$entry"

  if ! should_run "$category"; then
    if $DEBUG; then
      echo "[test.sh] skip $name (category=$category not in mode=$MODE)" >&2
    fi
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if ! should_run_check "$category" "$type"; then
    if $DEBUG; then
      echo "[test.sh] skip $name (type=$type excluded in mode=$MODE)" >&2
    fi
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  ERROR_LINES=""
  SUMMARY=""
  DURATION_MS=0

  # Run check (protected by || for set -e safety)
  rc=0
  run_check "$name" "$category" "$type" || rc=$?

  if [[ $rc -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    RESULTS+=("pass|$name|$SUMMARY|$DURATION_MS")
    if ! $JSON_OUTPUT; then
      printf '  \033[32m✓\033[0m %-20s \033[32mPASS\033[0m' "$name"
      [[ "$SUMMARY" != "ok" ]] && printf '  (%s)' "$SUMMARY"
      printf '\n'
    fi
  else
    FAILED=$((FAILED + 1))
    RESULTS+=("fail|$name|$ERROR_LINES|$DURATION_MS")
    printf '  \033[31m✗\033[0m %-20s \033[31mFAIL\033[0m\n' "$name" >&2
    if [[ -n "$ERROR_LINES" ]]; then
      while IFS= read -r line; do
        printf '    \033[90m→\033[0m %s\n' "$line" >&2
      done <<<"$ERROR_LINES"
    fi
    printf '    \033[90m→ Full log: %s\033[0m\n' "$LOG_DIR/${name// /-}.log" >&2
  fi
done

TOTAL=$((PASSED + FAILED + SKIPPED))
DURATION_SEC=$((($(date +%s) - NOW)))

# ── summary ───────────────────────────────────────────────────────────────

if $JSON_OUTPUT; then
  # Silence: only print JSON to stdout
  echo '{' >&1
  if [[ $FAILED -eq 0 ]]; then
    echo '  "result": "passed",' >&1
  else
    echo '  "result": "failed",' >&1
  fi
  echo "  \"passed\": $PASSED," >&1
  echo "  \"failed\": $FAILED," >&1
  echo "  \"skipped\": $SKIPPED," >&1
  echo "  \"duration_sec\": $DURATION_SEC," >&1
  echo '  "checks": [' >&1
  first=true
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r status name detail dur <<<"$entry"
    $first || printf ',\n' >&1
    first=false
    printf '    {"name":"%s","status":"%s","duration_ms":%d' "$name" "$status" "$dur" >&1
    if [[ "$status" == "fail" ]]; then
      escaped="$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '↵' | head -c 500)"
      printf ',"errors":[{"message":"%s"}]}' "$escaped" >&1
    elif [[ "$detail" != "ok" ]]; then
      printf ',"details":"%s"}' "$detail" >&1
    else
      printf '}' >&1
    fi
  done
  printf '\n  ]\n}\n' >&1
else
  printf '  ───────────────────────────────\n'
  printf '  Result: \033[1m%d/%d passed\033[0m' "$PASSED" "$TOTAL"
  [[ $FAILED -gt 0 ]] && printf ', \033[1;31m%d failed\033[0m' "$FAILED"
  [[ $SKIPPED -gt 0 ]] && printf ', %d skipped' "$SKIPPED"
  printf '\n\n  Real time: %ds\n' "$DURATION_SEC"
fi

# Exit with failure if any check failed
[[ $FAILED -eq 0 ]]
