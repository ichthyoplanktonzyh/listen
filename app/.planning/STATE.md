# State

> Updated: 2026-08-01 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-app`
- Default implementation owner: Claude
- Backend authority: `ichthyoplanktonzyh/listen-core`
- Flutter package version: `0.7.0+8`
- Contract pin: `1.0.0`
- Runtime pin: `0.7.0`
- Core commit pin: `4f4bad8b97a651e1cb731bfccb8fd7e1c4645e0a`
- Split release: `v0.7.0-split.1`

## Current Work

Phase 001 implements the additive local content-package journey against typed
App fixtures: existing package selection, strict external `listen-gen`
orchestration, Core import receipt, honest provenance, cancellation/retry, and
explicit subtitle/word-timeline selection. The pinned Core artifact is still
unchanged, so immutable-release and packaged end-to-end validation remain open.

## Established Boundaries

- App owns user journey, UI/UX, client state, compatibility parsing and assembly.
- App owns lawful media-acquisition UX, `listen-gen` process lifecycle, and the
  presentation of package trust, review, license, compatibility, and selection.
- Core owns canonical contract, backend behavior and release artifacts.
- Gen owns open offline production and provider adapters; App does not import
  its implementation.
- Hosted Catalog/Registry service ownership remains undecided.
- App consumes only immutable artifacts pinned by `backend.lock.json`.
- Normal app work does not require the old monorepo or a sibling core checkout.
- `design-notes/` owns the frontend charter, audits, and approved explorations.
- Root `CHANGELOG.md` is updated only by a release owner from merged PRs.

## Known Operational Constraint

GitHub-hosted Actions cannot currently start because of account billing/spending
state. Strict local validation is the merge evidence unless the owner changes
that constraint.

## Next

1. Receive immutable Core and versioned Gen handoffs for the Phase 001 requests.
2. Sync the final fixtures, update `backend.lock.json` only for the immutable
   Core release, and run the three-repository fixture E2E plus packaged smoke.
3. Keep the existing whole-media flow until the additive package path has been
   integrated and observed end to end.
