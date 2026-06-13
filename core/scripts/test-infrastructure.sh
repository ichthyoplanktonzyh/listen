#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

progress() {
  echo "[test-infrastructure] $1"
}

# Shared verification helpers must clean temporary files on normal exit.
progress "checking cleanup traps"
cat >"$tmp/cleanup-check.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$root/scripts/lib-testing.sh"
setup_test_dir
printf '%s' "\$tmp" >"$tmp/managed-path"
touch "\$tmp/probe"
EOF
bash "$tmp/cleanup-check.sh"
managed_path="$(cat "$tmp/managed-path")"
[[ ! -e "$managed_path" ]] || fail "setup_test_dir cleanup trap left $managed_path behind"

# The same trap must terminate a running API process.
progress "checking API process cleanup"
cat >"$tmp/fake-api.js" <<'EOF'
process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));
require("fs").writeFileSync(process.argv[2], "ready");
setInterval(() => {}, 1000);
EOF
cat >"$tmp/api-cleanup-check.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$root/scripts/lib-testing.sh"
setup_test_dir
(
  trap - INT TERM
  exec node "$tmp/fake-api.js" "$tmp/api-ready"
) &
api_pid=\$!
printf '%s' "\$api_pid" >"$tmp/api-pid"
for _ in \$(seq 1 50); do
  [[ -s "$tmp/api-ready" ]] && break
  sleep 0.1
done
[[ -s "$tmp/api-ready" ]]
EOF
bash "$tmp/api-cleanup-check.sh"
api_pid="$(cat "$tmp/api-pid")"
if kill -0 "$api_pid" 2>/dev/null; then
  kill -9 "$api_pid" 2>/dev/null || true
  fail "cleanup trap left API process $api_pid running"
fi

# Exercise runner mode selection with fake tools so the self-test stays fast.
progress "checking runner modes and flags"
cat >"$tmp/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cargo %s\n' "$*" >>"$TEST_INFRA_COMMAND_LOG"
if [[ "${1:-}" == "test" ]]; then
  echo "test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out"
fi
EOF
cat >"$tmp/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter %s\n' "$*" >>"$TEST_INFRA_COMMAND_LOG"
EOF
chmod +x "$tmp/cargo" "$tmp/flutter"

export CARGO="$tmp/cargo"
export FLUTTER="$tmp/flutter"
export TEST_INFRA_COMMAND_LOG="$tmp/commands.log"

bash "$root/scripts/test.sh" --quick --strict --json >"$tmp/quick.json"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$tmp/quick.json"
grep -Fq 'cargo test --workspace --lib --locked' "$TEST_INFRA_COMMAND_LOG" ||
  fail "quick mode did not run the locked Rust lib-test subset"
grep -Fq 'flutter analyze --fatal-infos --fatal-warnings' "$TEST_INFRA_COMMAND_LOG" ||
  fail "strict mode did not make Flutter analysis warnings fatal"
if grep -Fxq 'cargo test --workspace --locked' "$TEST_INFRA_COMMAND_LOG"; then
  fail "quick mode ran the full Rust test suite"
fi

: >"$TEST_INFRA_COMMAND_LOG"
bash "$root/scripts/test.sh" --rust --strict --json >"$tmp/rust.json"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$tmp/rust.json"
grep -Fxq 'cargo test --workspace --locked' "$TEST_INFRA_COMMAND_LOG" ||
  fail "rust mode did not run the locked full Rust test suite"
if grep -Fq 'cargo test --workspace --lib' "$TEST_INFRA_COMMAND_LOG"; then
  fail "rust mode duplicated the Rust lib-test subset"
fi

: >"$TEST_INFRA_COMMAND_LOG"
bash "$root/scripts/test.sh" --full --low-memory --json >"$tmp/low-memory.json"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$tmp/low-memory.json"
grep -Fxq 'flutter test --concurrency=1 --no-pub' "$TEST_INFRA_COMMAND_LOG" ||
  fail "low-memory mode did not limit Flutter test concurrency and reuse dependencies"

: >"$TEST_INFRA_COMMAND_LOG"
bash "$root/scripts/test.sh" --rust -- --nocapture --test-threads=1 >"$tmp/passthrough.out"
grep -Fxq 'cargo test --workspace -- --nocapture --test-threads=1' "$TEST_INFRA_COMMAND_LOG" ||
  fail "Rust test pass-through arguments were not separated for the test harness"

# Failed checks must leave their referenced logs available.
progress "checking retained failure logs"
cat >"$tmp/failing-cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "intentional infrastructure self-test failure" >&2
exit 7
EOF
chmod +x "$tmp/failing-cargo"
set +e
CARGO="$tmp/failing-cargo" bash "$root/scripts/test.sh" --rust --json \
  >"$tmp/failure.json" 2>"$tmp/failure.err"
failure_rc=$?
set -e
[[ $failure_rc -ne 0 ]] || fail "runner returned success for a failed check"
failure_log="$(
  sed $'s/\033\\[[0-9;]*m//g' "$tmp/failure.err" |
    sed -nE 's/.*Full log: ([^[:space:]]+).*/\1/p' |
    head -1
)"
[[ -n "$failure_log" && -f "$failure_log" ]] ||
  fail "runner removed the failure log it reported"
rm -rf "$(dirname "$failure_log")"

# Exit 137 must be identified as SIGKILL/resource enforcement.
progress "checking exit 137 diagnosis"
cat >"$tmp/killed-cargo" <<'EOF'
#!/usr/bin/env bash
exit 137
EOF
chmod +x "$tmp/killed-cargo"
set +e
CARGO="$tmp/killed-cargo" bash "$root/scripts/test.sh" --rust --json \
  >"$tmp/killed.json" 2>"$tmp/killed.err"
killed_rc=$?
set -e
[[ $killed_rc -ne 0 ]] || fail "runner returned success for a SIGKILL-style exit"
grep -Fq 'process exited 137 (SIGKILL)' "$tmp/killed.err" ||
  fail "runner did not diagnose exit 137 as SIGKILL"
killed_log="$(
  sed $'s/\033\\[[0-9;]*m//g' "$tmp/killed.err" |
    sed -nE 's/.*Full log: ([^[:space:]]+).*/\1/p' |
    head -1
)"
[[ -n "$killed_log" ]] && rm -rf "$(dirname "$killed_log")"

echo "Testing infrastructure self-test passed."
