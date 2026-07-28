# Conventions

- Models are typed and widget-free.
- Public API service methods return typed models, not raw maps/lists.
- Controllers own state transitions and disposal; coordinators own cross-feature
  orchestration; widgets own rendering and user input.
- Async state protects against stale completion/generation races.
- All meaningful states are explicit and honestly labeled.
- Design uses `lib/theme` tokens; avoid scattered literals.
- Reusable UI is constructor-injected and testable.
- High-frequency playback presentation remains local.
- New visible behavior adds controller/widget tests and considers accessibility,
  responsiveness and reduced motion.
- Vendored/generated files are not casually edited; provenance is preserved.
- Conventional Commits and one coherent PR per task. Changelog updates are
  release-only.
