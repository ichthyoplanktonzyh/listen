# Project Handoff — Phase 2.2 Start

更新时间：2026-06-19 16:20:39 CST

## Current Status

- Branch: `feature/forced-alignment-research`
- Current phase: Phase 2.1 closed, Phase 2.2 ready to start
- Next phase docs:
  - `.planning/phases/2.2-app-timeline-resource-ui/2.2-CONTEXT.md`
  - `.planning/phases/2.2-app-timeline-resource-ui/2.2-PLAN.md`

Phase 2.1 is complete for the current product path. The project should not
start by splitting the large `application` / `persistence-sqlite` files in the
next session. That refactor remains a known architecture debt, but it is no
longer blocking app-side LLTimeline resource UI work.

## What Was Closed In Phase 2.1

- Fixed the forced-alignment `word_index` placeholder contract.
- Unified Python tokenizer / normalization helpers.
- Added evaluation text mismatch guardrails.
- Added production post-aligner fallback strategy:
  `none | auto | mfa | mms-fa`.
- Moved transcription word-timeline refinement orchestration into
  `AppServices::refine_transcription_word_timelines`.
- Moved phonetic research fixture alignment/finding construction into
  `AppServices::build_research_fixture_phonetic_analysis`.
- Removed direct `speech_analysis` references from `crates/api-http/src`.
- Optimized `scripts/evaluate-word-timelines.py` to avoid repeated `stats()`
  calculations.

## Verified

```sh
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH" cargo test -p application
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH" cargo test -p api-http transcription
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH" cargo test -p api-http phonetic
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH" cargo test -p speech-analysis forced_align
scripts/validate-contracts.sh
```

All passed. A full `cargo test -p api-http` was also attempted earlier, but
M1.8 learning-resource tests failed in the sandbox with `PermissionDenied /
Operation not permitted`; the targeted transcription/phonetic/API contract
surfaces passed.

## Phase 2.2 Entry

Start with audit, not UI implementation:

1. Inspect existing LLTimeline import/export API routes and local client methods.
2. Inspect WordTimeline summary / activate / export endpoints.
3. Inspect Flutter state/controllers that currently drive word highlighting.
4. Identify the smallest UI surface for Timeline Resource Summary.
5. Verify no-resource fallback remains current behavior.

Recommended first implementation target:

```text
Timeline Resource Summary
  - imported LLTimeline present or absent
  - active WordTimeline provider/version/status
  - candidate WordTimeline list
  - production-report readiness when available
  - post_alignment / post_alignment_failure artifacts
```

Manual correction and ChunkTimeline editing should remain later phases.
