# LLPlayerNext Project Handoff: 2026-06-13 ASR Word Timestamps

## Repository State

- Workspace: `/Users/shadow/LLPlayerNext`
- Branch: `feature/asr-word-timestamps`
- Baseline implementation commit:
  `1874071373659c4badac9ad1467437e3b0d31155`
- This handoff records the review and completion fixes applied after that
  baseline.

Preserve this user-owned, untracked design discussion without committing or
modifying it:

- `docs/discuss/chunk-based-listening-comprehension.md`

## Completed ASR Timing Behavior

Whisper.cpp JSON-full DTW output is converted into provider-neutral
`asr_reported` word timings when it can be mapped safely to subtitle words.

The completed extraction path:

- ignores whisper special tokens such as `[_BEG_]` and `[_TT_*]`;
- excludes punctuation and unavailable `t_dtw` tokens from lexical timing;
- validates merged whisper text against subtitle lexical words;
- converts DTW points into monotonic, non-empty `[start, end)` intervals;
- splits repeated DTW points deterministically with one-millisecond spacing;
- falls back to the deterministic estimator for unusable sentence mappings.

Storage rejects zero-duration word timings. Existing cached zero-duration
timings are treated as unusable and replaced through estimator fallback.
Extraction and storage failures are surfaced instead of being silently
discarded.

## Test Runner Completion

The unified runner now supports:

```bash
bash ./scripts/test.sh --full --strict --low-memory
```

`--low-memory` limits Cargo build jobs, Rust test threads, Rayon threads, and
Flutter test concurrency to one. Human-readable runs print a progress line
before each check, and child exit code 137 is diagnosed as `SIGKILL` or
external resource enforcement.

In the current Codex execution environment, launching the executable directly
as `./scripts/test.sh` or `./scripts/test-infrastructure.sh` can be killed with
exit 137 before the script's first line runs. Invoking the same files through
`bash` is stable. This is an outer execution-channel limitation, not a test
failure.

## Verification Baseline

The following passed on 2026-06-13:

- `bash -n scripts/test.sh scripts/test-infrastructure.sh`
- `bash ./scripts/test-infrastructure.sh`
- `bash ./scripts/test.sh --full --strict --low-memory`
- Rust workspace tests: 137 passed
- Flutter tests: 39 passed
- Flutter analysis and API contract validation
- strict Rust clippy
- benchmark compilation
- bundled whisper.cpp v1.7.6 base-model JFK transcription validation
- Milestone 1.7 and Milestone 1.9 headless regressions
- `git diff --check`

## Follow-Up Boundaries

- Do not store or serve zero-duration word timings.
- Do not treat whisper special tokens or punctuation as lexical words.
- Preserve sentence-level estimator fallback when DTW output cannot be mapped
  safely.
- Do not interpret exit 137 alone as an application out-of-memory defect;
  first determine whether the child process or its outer executor was killed.
