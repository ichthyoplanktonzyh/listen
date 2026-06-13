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
single command with structured pass/fail summary output. Full logs are
persisted to disk; only the summary and key error lines appear on the
terminal. This reduces per-verification token consumption to ~500 (94% less).

## Quick Start

```bash
# Full verification (default)
./scripts/test.sh

# Fast pre-commit check (fmt + clippy + analyze, no tests)
./scripts/test.sh --quick

# Rust-only checks
./scripts/test.sh --rust

# Flutter-only checks
./scripts/test.sh --flutter

# Machine-readable output for CI / AI consumption
./scripts/test.sh --full --json

# Stream raw output for debugging
./scripts/test.sh --verbose

# Treat warnings as errors
./scripts/test.sh --strict

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
| Full log to disk, summary to terminal | Never discards information. Failures show key lines + path to complete log |
| `mktemp -d` + `trap cleanup EXIT` | Auto-cleaned temporary log directory, no `.gitignore` changes needed |

### Check Registry

Checks are defined as a simple data table:

```
CHECKS=(
  "cargo fmt|rust|fmt"
  "cargo clippy|rust|clippy"
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

The `verify-m*.sh` scripts have not yet been migrated to use this library
(deferred to avoid scope creep). The library is ready for incremental adoption
in future milestone verification scripts.

### Test Data: ASR JSON Fixture

`testdata/asr/sample-output.json` is a hand-crafted whisper.cpp `-ojf` output
file used by the `speech-analysis` integration tests. It contains three
segments designed to exercise the extraction pipeline:

| Segment | Content | Purpose |
|---|---|---|
| 1 | "Hello", "world", "." | Normal single-token words; punctuation merge |
| 2 | "I", "was", "play", "ing", "games", "." | Subword merge ("playing" ← "play"+"ing"); punctuation merge |
| 3 | "This" (t_dtw=-1), "is", "what" | `t_dtw=-1` filter; word count mismatch fallback |

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

### Why not migrate all verify-m*.sh scripts to lib-testing.sh now?

The six existing verification scripts are stable and well-tested. Migrating
them to use the shared library is a pure refactor that carries regression
risk. The library is available for new scripts and incremental migration.

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
| cargo test (lib) | PASS | ~107 unit tests (--lib only) |
| cargo test | PASS | ~122 tests (unit + integration) |
| cargo bench | PASS | 10 benchmark cases |
| flutter analyze | PASS | No issues found |
| flutter test | PASS | 38 tests |
| contracts | PASS | Player, event, and OpenAPI contracts valid |

## Known Limitations

1. **CI portability**: `test.sh` has been made CI-portable (cargo/flutter
   resolution falls back to `command -v`), but the Flutter path defaults to
   Linux/macOS conventions. Windows CI uses `shell: bash` via Git Bash.
2. **Flutter `pub get` not included**: `test.sh --flutter` runs `analyze` and
   `test` but does not run `flutter pub get`. CI and local development must
   ensure dependencies are fetched before running the test script.
3. **No parallel execution**: All checks run sequentially. Parallel Rust and
   Flutter checks would save ~5–10 seconds but introduce output interleaving
   issues that would require a more complex runner.

## Future Work

- Add a `--watch` mode using `cargo watch` / `fswatch` for continuous testing
  during development.
- Consider parallel Rust + Flutter execution in `--full` mode with
  interleaved-but-grouped output.
- Add Flutter golden tests for subtitle overlay and current-word highlight
  rendering.
- Add property-based testing (`proptest`) for ASR timing merge algorithms.
- Expand integration tests to `domain` crate.

## References

- [ADR 0007 — Pronunciation and Word Timing Foundations](../decisions/0007-pronunciation-and-word-timing.md)
- [ASR Word-Level Timestamps Feature Doc](./asr-word-timestamps.md)
- [Milestone 1.9 Planning](../planning/milestone-1.9.md)
- [macOS Functional Testing](../development/macos-functional-testing.md)
