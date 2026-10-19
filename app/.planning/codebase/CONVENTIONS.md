# Conventions

- Models are typed and widget-free.
- Public API service methods return typed models, not raw maps/lists.
- Controllers own state transitions and disposal; coordinators own cross-feature
  orchestration; widgets own rendering and user input.
- A screen that needs more than a controller gets a view model in
  `lib/controllers` plus a repository in `lib/data/repositories`; the widget
  keeps no business state and calls no endpoint. Localized text, dialogs and
  SnackBars stay in the widget — a view model returns outcomes instead.
- Dependencies are constructor-injected and wired by hand; no service locator
  and no ambient injection framework.
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
