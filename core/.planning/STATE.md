# State

> Updated: 2026-07-31 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.1.0` (unreleased)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The internal recommended-foundation preparation module now owns exact source
selection, fixed typed preparation slots, durable single-flight, revision CAS,
cancellation/retry/recovery, and local-runtime execution through the three fast
required analyses: WordTimeline, ChunkTimeline, and SenseGroup. Citation and
predicted audible structures (views A/B) are derived from WordTimeline rather
than persisted as preparation jobs. SoundLine is independent best-effort
enrichment; observed phone evidence (view C) remains a separately confirmed
Phoneme Analysis. The module remains internal until the media-level one-click
journey in issue #103 supplies or creates the exact Subtitle Text Track.

## Established Boundaries

- Core owns canonical OpenAPI, Rust/Python backend, schemas, and runtime artifacts.
- App owns Flutter, client compatibility, lock file, and final product assembly.
- Cross-repo synchronization uses immutable releases and explicit lock updates.
- Imported monorepo planning is frozen under `archive/monorepo-baseline/`.
- Root `CHANGELOG.md` is updated only by a release owner from merged PRs.

## Known Operational Constraint

GitHub-hosted Actions cannot currently start because of account billing/spending
state. Local validation is required and CI red-with-zero-steps is infrastructure,
not code evidence.

## Next

1. Implement issue #103 as the media-level one-click entry: reuse an exact
   Subtitle Text Track or run ASR, then enter foundation preparation.
2. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
3. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
4. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
5. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
