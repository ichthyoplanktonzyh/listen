# State

> Updated: 2026-07-28 17:16 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.0.0`
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

Independent backend governance is merged. The current maintenance slice moves
frontend design assets to `listen-app`, preserves the local runtime interface as
a core ADR, and adopts release-only changelog maintenance.

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

1. Audit remaining core scripts/docs that still assume the old monorepo.
2. Use `.planning/CROSS_REPO.md` for the next app-driven contract request.
3. Publish new contract/runtime artifacts only when backend behavior changes.
