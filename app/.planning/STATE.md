# State

> Updated: 2026-08-07 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-app`
- Default implementation owner: Claude
- Backend authority: `ichthyoplanktonzyh/listen-core`
- Flutter package version: `0.7.0+8`
- Contract pin: `1.1.0`
- Runtime pin: `0.7.0`
- Core commit pin: `b980a20666f746685db1fd06bfa425d762d7a678`
- Gen source pin: `41a53336fd893522abf7ef168fd2ace9fa6ac678`
- Gen tool version: `0.1.0`
- Split release: `v0.7.0-split.1`

## Current Work

App now consumes the pinned `listen-gen` release bundle and completes the local
three-repository round trip: a fixture provider produces a `.listenpkg`, which
the pinned Core imports as a candidate-only receipt. The App trusts only the
bundle whose bytes match the committed `listen_gen.lock.json` (manifest hash +
artifact size/hash), and machine events must carry the verified tool version.
No arbitrary `listen-gen` executable is honored anymore.

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

1. Observe the additive package path in the running app end to end.
2. Only afterward, migrate the old whole-media production path onto Gen; do not
   delete the existing implementation yet.
3. Handle formal release/installer delivery of the bundle in a separate PR (the
   `.pyz` is not yet packed into the shipped macOS app bundle).
