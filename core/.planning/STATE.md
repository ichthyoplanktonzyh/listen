# State

> Updated: 2026-08-01 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.1.0` (unreleased)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The content-package v1 boundary now has bounded inspection, typed projection,
and a dedicated candidate-only atomic import seam. An external-producer
prototype has passed local fixture and Core-inspector validation but has no
published repository handoff yet; LLTimeline conversion remains migration
compatibility. Existing Core whole-media generation stays temporarily available
until the new path is published, cut over, and observed.

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

1. Connect the media-level one-click journey to external package generation and
   candidate import, then verify cutover before removing legacy whole-media
   generation responsibility.
2. Split Core whole-media and learner-recording transcription responsibilities
   before deleting any legacy coordinator code; realtime and learner-dependent
   capabilities remain in Core.
3. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
4. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
5. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
6. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
