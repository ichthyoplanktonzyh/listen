# Structure

| Path | Current responsibility |
|---|---|
| `lib/main.dart` | application composition root and top-level shell wiring |
| `lib/models` | typed client/domain views and wire-compatible parsing |
| `lib/controllers` | immutable presentation state, ViewModels, state machines, coordinators and async lifecycle guards |
| `lib/data/repositories` | injected per-feature data boundaries over `LocalApi` |
| `lib/services/api_service.dart` | LocalApi transport/process boundary, used only by repositories and composition/session infrastructure |
| `lib/services` | platform/API boundaries for files, pickers, environment, bootstrap, transports and diagnostics |
| `lib/services/api` | endpoint groups as Dart part files |
| `lib/state` | shared store/builder composition |
| `lib/screens` | lean route/screen Views; receive injected ViewModels/Controllers |
| `lib/widgets` | reusable UI organized by journey/surface; `widgets/flows` owns route-scoped notifier lifetimes |
| `lib/theme` | breakpoints, colors, type, spacing, radii and motion |
| `lib/utils` | pure presentation/parsing helpers |
| `macos` | native runner, permissions and platform integration |
| `third_party/fvp` | embedded player adapter dependency |
| `tool` | core artifact install/verify and macOS assembly/smoke |
| `test` | controller, widget, contract and regression tests |
| `test/fixtures` | pinned frontend-owned contract/smoke fixtures |
| `.planning/phases/001-local-content-package-journey` | active local package journey, UI spec, and Core/Gen requests |
| `design-notes` | frontend design charter, audits and approved explorations |
| `docs/decisions` | append-only frontend ADRs |
| `backend.lock.json` | immutable core baseline |
| `.planning` | current frontend project memory |
