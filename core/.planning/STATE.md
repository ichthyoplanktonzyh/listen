# State

> Updated: 2026-07-29 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.0.0`
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The backend hardening slice is implemented on
`codex/backend-review-refactor`. It restores backend-only quality gates,
introduces durable background-job state, makes transcription cancellation and
subtitle projection updates atomic, and moves LLM, realtime, and forced-align
protocol construction behind application-owned interfaces. Migration backups
are source-versioned and crash-safe; provider credential cleanup uses a durable
outbox; forced-align cancellation terminates the sidecar before any later
persistent side effect.

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

1. Review and merge the fully validated backend hardening branch.
2. Design durable storage for recording transcription only after transcript,
   provenance, and recording-fact ownership is explicit.
3. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
4. Publish new contract/runtime artifacts only after review and owner approval.
