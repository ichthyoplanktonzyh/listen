# State

> Updated: 2026-07-30 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.1.0` (unreleased)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The language-learning model, LLTimeline contract/import corrections, runtime
dictionary reload, and SoundLine provenance fixes are merged. Core issue #91
now establishes the internal recommended-foundation preparation module before
any learner-facing contract: exact source selection, fixed typed preparation
slots, durable single-flight, revision CAS, cancellation/retry/recovery, and
honest four-state readiness.

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

1. Complete issue #91's local-runtime adapters against the internal typed
   preparation module; do not add routes or OpenAPI until an app-owned journey
   request exists.
2. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
3. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
4. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
5. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
