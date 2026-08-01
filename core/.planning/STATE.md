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

The owner has accepted the shared open Resource Package ecosystem context for
`listen-core`, `listen-app`, and `listen-gen`. Content-package v1 has bounded
inspection, typed projection, and a candidate-only atomic import seam. The
local `listen-gen` prototype natively produces Subtitle Text Track plus Word
Timeline packages but has no remote or published handoff. Existing Core
whole-media generation stays temporarily available until the new path is
published, cut over, and observed.

The additive local package-import HTTP contract exposes the bounded, atomic
candidate-only application seam with a typed receipt and stable redacted
failure codes. It remains unreleased until an owner-approved immutable
contract/runtime artifact exists.

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

1. Complete the App-led local exact-media package round trip against this
   unreleased import contract, then publish an owner-approved immutable Core
   contract/runtime artifact and pin it in the App.
2. Cut whole-media production over to `listen-gen` and observe it before
   deleting legacy behavior.
3. Define Content Edition, Media Rendition, Timeline Compatibility, and the
   Package Listing/Release interface before a hosted catalog journey.
4. Split Core whole-media and learner-recording transcription responsibilities
   before deleting any legacy coordinator code; realtime and learner-dependent
   capabilities remain in Core.
5. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
6. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
7. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
8. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
