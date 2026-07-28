# State

> Updated: 2026-07-28 17:16 CST

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

Independent frontend governance is merged. The current maintenance slice makes
this repository authoritative for frontend design assets, adopts release-only
changelog maintenance, and documents complete local app startup.

## Established Boundaries

- App owns user journey, UI/UX, client state, compatibility parsing and assembly.
- Core owns canonical contract, backend behavior and release artifacts.
- App consumes only immutable artifacts pinned by `backend.lock.json`.
- Normal app work does not require the old monorepo or a sibling core checkout.
- `design-notes/` owns the frontend charter, audits, and approved explorations.
- Root `CHANGELOG.md` is updated only by a release owner from merged PRs.

## Known Operational Constraint

GitHub-hosted Actions cannot currently start because of account billing/spending
state. Strict local validation is the merge evidence unless the owner changes
that constraint.

## Next

1. Run the pinned complete app and perform owner smoke testing.
2. Let Claude perform the next frontend journey/UX fact audit.
3. Use `CROSS_REPO.md` for the next backend-dependent feature.
