# Durable Learning Material Closeout

## Outcome

Core now persists a path-free Learning Material aggregate for text, media and
mixed compositions. Immutable revisions carry exact document text or references
to registered media identities. Create retries converge deterministically;
revision append advances the current pointer atomically; media renditions
resolve back to their material; and Personal Library membership is material
authority while the legacy retained-media projection stays transactionally
synchronized.

SQLite v59 backfills one equivalent material/revision graph for every existing
media row without changing its membership, timestamps or availability.
Membership mutation never deletes revisions, bindings, resources or
learner-owned state.

## Compatibility And Release

- API generation: `1`
- Contract: `3.2.0` (backward-compatible additive minor)
- Runtime: `0.7.0`
- SQLite schema: `v59`
- Source merge: `70c94adbacb38f88c0f616cd41374131a24e2f65`
- Tagged release commit: `5a65b2735325aac18f1eacb736b8d9676adf59a9`
- Immutable release: `v0.7.0-phase1.2`
- Release URL:
  `https://github.com/ichthyoplanktonzyh/listen-core/releases/tag/v0.7.0-phase1.2`
- Contract archive SHA-256:
  `43e3aaf69b2182f0b434d022d7620f26c8b97eaef4b9c40e4d74a910483b0491`
- macOS arm64 runtime archive SHA-256:
  `8130e336d73da0590c68393a379941a42788abdb178e8a3bfd6d15787ce4a7d5`

Existing media routes remain compatible. Creation omission/null uses the
retained default; explicit false creates a Temporary Material. Material DTOs
never expose a local file path.

## Validation

- `./scripts/test.sh --rust --strict`: format, clippy and 1,109 Rust tests pass.
- `./scripts/validate-contracts.sh`: OpenAPI/router/generated-client parity and
  architecture guards pass.
- `python3 -m unittest scripts/test_release_artifacts.py`: release unit tests
  pass.
- Contract and runtime archives verify against their embedded manifests and
  exact tagged commit.
- The extracted macOS arm64 runtime starts outside the source tree, reports
  contract `3.2.0` / runtime `0.7.0` in handshake and health, then shuts down
  gracefully.

All validation is credential-free and uses no paid/live model call. GitHub
Actions had no runnable checks under the documented account billing constraint;
the exact local gates are the release evidence.

## Deferred

Consumer Personal Library projection, raw-text reading UI, Package
Installation, Learning Edition Adoption, Source Identity, subscriptions and
RSS/Atom convergence remain later App or cross-repository Phase 1 slices.
