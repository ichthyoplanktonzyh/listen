# Unified Testing Workflow

> **Release:** 0.7.1  
> **Branch:** `feature/asr-word-timestamps`  
> **Status:** implemented

## Overview

Before this feature, every quality check during development required running
5–6 separate commands manually:

```
cargo fmt --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
flutter analyze
flutter test
./scripts/validate-contracts.sh
```

Each command produces hundreds of lines of raw compiler/test output. In
AI-assisted development, this output was parsed repeatedly at a per-verification
cost of ~8,000 tokens. A typical feature implementation runs this loop 3–5
times, totaling 24,000–40,000 tokens just for verification.

The unified test runner (`scripts/test.sh`) consolidates all checks into a
single command with structured pass/fail summary output. Successful-run logs
are deleted automatically. If any check fails, the complete logs remain at
the printed temporary path while the terminal shows a concise error summary.
Human-readable runs print one progress heartbeat before each check so external
executors do not mistake a quiet compiler/test process for a stalled command.
This reduces per-verification token consumption to ~500 (94% less).

## Quick Start

```bash
# Full verification (default)
./scripts/test.sh

# Fast pre-commit check (fmt + clippy + Rust lib tests + analyze)
./scripts/test.sh --quick

# Rust-only checks
./scripts/test.sh --rust

# Flutter-only checks
./scripts/test.sh --flutter

# Machine-readable output for CI / AI consumption
./scripts/test.sh --full --json

# Stream raw output for debugging
./scripts/test.sh --verbose

# Treat warnings as errors and require the committed Cargo.lock
./scripts/test.sh --strict

# Reduce peak memory and avoid repeated Flutter dependency resolution
./scripts/test.sh --full --strict --low-memory

# Verify cleanup, mode selection, strict flags, JSON output, and log retention
./scripts/test-infrastructure.sh

# Pass-through arguments to underlying test runners
./scripts/test.sh --rust -- --nocapture --test-threads=1
```

## Architecture

### `scripts/test.sh` — Core Test Runner

The test runner follows a simple pipeline per check:

```
run_check("cargo test", "rust", "test")
  │
  ├─ build command array
  ├─ set +e  (disable exit-on-error)
  ├─ (cd $run_dir && cmd > $log 2>&1)  ← subshell isolates CWD
  ├─ rc = $?
  ├─ set -e  (re-enable exit-on-error)
  ├─ extract_summary() or extract_errors() from $log
  └─ return rc
```

Key design decisions:

| Decision | Rationale |
|---|---|
| Subshell `(cd && cmd)` per check | Each check runs in its own CWD (Rust at repo root, Flutter at `apps/desktop`). No state leaks between checks |
| `set +e` / `set -e` around command execution | Allows capturing the exit code without `set -e` aborting the script |
| `||` protection at call site | `run_check ... \|\| rc=$?` prevents `set -e` from triggering on test failures |
| Failure log retention | Successful-run logs are deleted; failed-run logs remain at the path printed by the runner |
| Progress heartbeat | Human-readable runs print the current check before executing it; JSON output stays silent |
| `--strict` | CI requires `Cargo.lock`, denies Rust warnings, and makes Flutter infos/warnings fatal |
| `--low-memory` | Sets Cargo/Rust/Rayon concurrency to 1 and runs `flutter test --concurrency=1 --no-pub` after analyze |
| Mode-specific unit subset | `cargo test --workspace --lib` runs only in `--quick`; Rust/full modes run the complete suite once |

### Check Registry

Checks are defined as a simple data table:

```
CHECKS=(
  "cargo fmt|rust|fmt"
  "cargo clippy|rust|clippy"
  "cargo test (lib)|rust|quick_test"
  "cargo test|rust|test"
  "flutter analyze|flutter|analyze"
  "flutter test|flutter|flutter_test"
  "contracts|contracts|contracts"
)
```

Each entry specifies: `display_name | category | check_type`. The category
determines which mode (`--rust`, `--flutter`, `--full`) includes the check.

### Error Extraction

Each check type has a dedicated `extract_errors()` pattern that parses the
raw log for the most actionable lines:

| Type | Extraction Pattern |
|---|---|
| `fmt` | `grep '^Diff in'` — files with formatting diffs |
| `clippy` | `grep '^error\|^warning'` — file:line:col diagnostics |
| `test` | `grep 'FAILED$'` + `grep '^test result: FAILED'` — failing tests only |
| `analyze` | `grep 'error •\|warning •'` — Flutter analyzer issues |
| `flutter_test` | `grep 'FAILED\|✗\|Expected:\|Actual:'` — test assertion failures |
| `contracts` | `grep 'Error\|missing\|throw'` — contract validation errors |

If no structured errors are extracted, the last 20 lines of the log are shown
as a fallback. This ensures that unexpected error formats (link errors, ICE,
segfault) are never silently hidden.

### Output Formats

**Human-readable (default):**

```
  ✓ cargo fmt        PASS
  ✓ cargo clippy     PASS
  ✓ cargo test       PASS  (58 passed, 0 failed)
  ✓ flutter analyze  PASS
  ✓ flutter test     PASS  (00:01 +38: All tests passed!)
  ✓ contracts        PASS
  ─────────────────────────
  Result: 6/6 passed

  Real time: 14s
```

**Human-readable (failure):**

```
  ✓ cargo fmt        PASS
  ✗ cargo test       FAIL
    → test asr_timing::break_test::intentional_failure ... FAILED
    → test result: FAILED. 10 passed; 1 failed
    → Full log: /var/folders/.../tmp.XYZ1234/cargo-test.log
  ✓ flutter analyze  PASS
  ✓ flutter test     PASS
  ─────────────────────────
  Result: 5/6 passed, 1 failed
```

**JSON (for CI / AI):**

```json
{
  "result": "passed",
  "passed": 6,
  "failed": 0,
  "skipped": 0,
  "duration_sec": 14,
  "checks": [
    {"name": "cargo fmt", "status": "pass", "duration_ms": 187},
    {"name": "cargo clippy", "status": "pass", "duration_ms": 283},
    {"name": "cargo test", "status": "pass", "duration_ms": 5164, "details": "58 passed, 0 failed"}
  ]
}
```

### `scripts/lib-testing.sh` — Shared Test Utilities

Extracts common boilerplate from the six `verify-m*.sh` acceptance scripts:

| Function / Variable | Description |
|---|---|
| `resolve_cargo()` | Resolve `cargo` binary with fallback chain |
| `resolve_flutter()` | Resolve `flutter` binary |
| `setup_test_dir()` | Create temp directory + register cleanup trap |
| `start_api(db, log, token, [env...])` | Start `api-http`, wait for `api.started` event, set `base` and `auth` |
| `stop_api()` | Gracefully stop API server |
| `api_curl()` | `curl -fsS` with pre-configured auth headers |
| `json_get(json, path)` | Extract value from JSON via Node.js |
| `json_assert(json, predicate, msg)` | Assert a JSON predicate, fail with message |
| `assert_eq(actual, expected, msg)` | Equality assertion |
| `assert_contains(haystack, needle, msg)` | Substring assertion |
| `assert_not_empty(value, msg)` | Non-empty assertion |

All six `verify-m*.sh` scripts source this library. `setup_test_dir()` installs
an EXIT cleanup trap, and `start_api()` restores signal handling before
launching the server so `stop_api()` can perform a real graceful shutdown.
M1.7 and M1.8 also use `start_api()` with explicit environment overrides rather
than maintaining separate lifecycle implementations.

### Infrastructure Self-Test

`scripts/test-infrastructure.sh` tests the testing tools themselves without
running the product suite. It verifies:

- temporary directories and API processes are cleaned on EXIT;
- quick mode runs the Rust lib-test subset but Rust mode does not duplicate it;
- strict mode adds locked dependency and fatal-warning flags;
- low-memory mode limits concurrency and reuses Flutter dependencies;
- exit code 137 is reported explicitly as `SIGKILL` / external resource enforcement;
- Rust pass-through arguments are separated for the test harness;
- JSON output parses successfully;
- failed-run logs still exist at the path reported by the runner.

CI runs this self-test in the macOS desktop job.

### Test Data: ASR JSON Fixture

`testdata/asr/sample-output.json` is a compact whisper.cpp `-ojf` output
fixture used by the `speech-analysis` integration tests. Its structure mirrors
real bundled-runtime output, including `[_BEG_]` and `[_TT_*]` tokens:

| Segment | Content | Purpose |
|---|---|---|
| 1 | `[_BEG_]`, "Hello", "world", ".", `[_TT_*]` | Real special-token filtering and normal intervals |
| 2 | "I", "was", "play", "ing", "games", ".", `[_TT_*]` | Subword merge and sentence-end boundary |
| 3 | "This" (`t_dtw=-1`), "is", "what", `[_TT_*]` | Unavailable lexical token causes sentence fallback |

### Integration Tests

Two crates now have `tests/` integration test suites:

| Crate | Tests | Coverage |
|---|---|---|
| `speech-analysis` | 3 | ASR word timing extraction, segment/word count mismatch fallback |
| `persistence-sqlite` | 6 | File persistence across reopen, migration backup creation, concurrent access safety, subtitle import/export, media availability lifecycle |

Both use the crate's public API only — testing the crate as an external consumer would.

## Design Decisions

### Why a unified script and not a Makefile?

The project already uses Bash scripts as its orchestration layer (`build-*.sh`,
`verify-*.sh`, `validate-contracts.sh`). Adding a Makefile would introduce a
second orchestration system without adding value — Make variables and phony
targets would just wrap shell commands, adding indirection. Keeping the test
runner in Bash maintains consistency with the rest of the project.

### Why no pre-commit hook?

In AI-assisted development, pre-commit hooks interfere with the workflow. The
AI runs verification explicitly before committing; an automatic hook would
duplicate work and potentially reject commits the AI is about to fix. Manual
execution via `./scripts/test.sh --quick` is more flexible.

### Why `set +e` / `set -e` around each command?

Bash's `set -e` (exit on error) is essential for catching unexpected failures,
but it also aborts the script on the first test failure — which is exactly
what we want to report, not crash on. The `set +e`/`set -e` pair around
command execution, combined with `||` protection at the call site, allows
capturing and reporting failures without aborting.

## Verification

The test runner is self-verifying: running `./scripts/test.sh --full` validates
the entire quality suite. The current results:

| Check | Result | Detail |
|---|---|---|
| cargo fmt | PASS | All Rust files formatted |
| cargo clippy | PASS | No warnings with `-D warnings` |
| cargo test | PASS | ~133 tests (unit + integration) |
| cargo bench --no-run | PASS | All 10 benchmark cases compile in CI |
| cargo llvm-cov | PASS | 50% line-coverage floor |
| flutter analyze | PASS | No issues found |
| flutter test | PASS | 38 tests |
| contracts | PASS | Player, event, and OpenAPI contracts valid |
| infrastructure self-test | PASS | Cleanup, modes, strict flags, JSON, retained failure logs |
| fuzz smoke | PASS | Three targets passed locally; CI runs each for 10 seconds on nightly Rust |

## Known Limitations

1. **CI portability**: `test.sh` has been made CI-portable (cargo/flutter
   resolution falls back to `command -v`), but the Flutter path defaults to
   Linux/macOS conventions. Windows CI uses `shell: bash` via Git Bash.
2. **Flutter `pub get` not included**: `test.sh --flutter` runs `analyze` and
   `test` but does not run `flutter pub get`. CI and local development must
   ensure dependencies are fetched before running the test script.
3. **No parallel execution**: Runner checks execute sequentially. Parallel Rust and
   Flutter checks would save ~5–10 seconds but introduce output interleaving
   issues that would require a more complex runner.
4. **External SIGKILL**: A host or sandbox can still kill the runner itself
   before it can print a summary. Use `--low-memory` to reduce peak pressure;
   child-command exit 137 is diagnosed explicitly.
5. **Benchmark thresholds**: CI compiles benchmarks but does not yet reject
   statistically significant performance regressions.
6. **OpenAPI compatibility**: The current test protects the version, path
   count, selected schema names, and `/v1/` prefix. It is a surface regression
   gate, not a complete semantic breaking-change detector.
7. **UI coverage**: Flutter golden and full desktop E2E tests remain pending.

## Future Work

- Add a `--watch` mode using `cargo watch` / `fswatch` for continuous testing
  during development.
- Consider parallel Rust + Flutter execution in `--full` mode with
  interleaved-but-grouped output.
- Add Flutter golden tests for subtitle overlay and current-word highlight
  rendering.
- Add semantic OpenAPI breaking-change detection against a reviewed baseline.
- Add benchmark baselines and a statistically meaningful regression policy.
- Expand integration tests to `domain` crate.

## References

- [ADR 0007 — Pronunciation and Word Timing Foundations](../decisions/0007-pronunciation-and-word-timing.md)
- [ASR Word-Level Timestamps Feature Doc](./asr-word-timestamps.md)
- [Milestone 1.9 Planning](../planning/milestone-1.9.md)
- [macOS Functional Testing](../development/macos-functional-testing.md)
