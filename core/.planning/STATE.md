# State

> Updated: 2026-08-08 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.1.0` (unreleased)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The owner has accepted the whole-media producer cutover roadmap. Content-package
v1 has bounded inspection, typed projection, and a candidate-only atomic import
seam. `listen-gen` now has a remote, a deterministic release bundle and native
Subtitle Text Track production with optional provider-supplied Word Timeline.
`listen-app` pins Gen commit `41a53336`, verifies the artifact before launch and
owns the package-generation journey.

The additive local package-import HTTP contract exposes the bounded, atomic
candidate-only application seam with a typed receipt and stable redacted
failure codes. A real pinned Gen -> package -> Core fixture round trip passes.
Core's whole-media transcription/jobs and legacy production tree remain
reachable duplication and are now explicit deletion targets, not fallback
surfaces to extend.

Execution is synchronized by Core #111, Gen #4 and App #100. Core #103 was
closed as superseded because it kept whole-media ASR orchestration in Core.

## Established Boundaries

- Core owns canonical OpenAPI, Rust/Python backend, schemas, and runtime artifacts.
- App owns Flutter, client compatibility, lock file, and final product assembly.
- Cross-repo synchronization uses immutable releases and explicit lock updates.
- Imported monorepo planning is frozen under `archive/monorepo-baseline/`.
- Root `CHANGELOG.md` is updated only by a release owner from merged PRs.
- `ECOSYSTEM.md` records shared product decisions; repository planning remains
  limited to Core-owned facts and work.

## Known Operational Constraint

GitHub-hosted Actions cannot currently start because of account billing/spending
state. Local validation is required and CI red-with-zero-steps is infrastructure,
not code evidence.

## Next

1. Fix the three-repository round-trip false-positive path and worktree/Gen-lock
   status reporting so cutover evidence cannot succeed without executing.
2. Split Core whole-media from learner-recording transcription, cut the App's
   remaining media transcription consumers to Gen and delete the old job surface.
3. Add native aligned Word Timeline production in Gen.
4. Resolve Core ChunkTimeline versus package Prosody semantics, then migrate
   Sense Group, Word Acoustics, Prosody and optional Phone Timeline producers.
5. Delete `scripts/timeline-production` and runtime/release inputs exclusive to
   the retired Core production path.
6. Define Content Edition, Media Rendition, Timeline Compatibility, and the
   Package Listing/Release interface before a hosted catalog journey.
7. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
8. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
9. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
10. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
