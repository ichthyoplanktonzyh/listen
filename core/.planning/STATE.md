# State

> Updated: 2026-07-29 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `1.1.0` (unreleased)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The first local realtime cascade slice is implemented. Core can persist a
credential-free, loopback-only `local_cascade_realtime` profile, normalize the
pinned Hugging Face speech-to-speech protocol behind the existing application
port, and optionally supervise an explicitly configured sidecar. The runtime
waits for an available `/v1/pool` pipeline and owns process-group shutdown.
Model installation and live inference remain intentionally outside normal
tests.

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

1. Review and merge the local realtime cascade slice.
2. Publish immutable `1.1.0` contract/runtime artifacts only after owner
   approval, then complete the `listen-app` lock and DTO handoff.
3. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
4. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
