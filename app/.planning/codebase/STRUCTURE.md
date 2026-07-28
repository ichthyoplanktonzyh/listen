# Structure

| Path | Current responsibility |
|---|---|
| `lib/main.dart` | composition root and desktop shell |
| `lib/models` | typed client/domain views and wire-compatible parsing |
| `lib/controllers` | state machines, coordinators and lifecycle |
| `lib/services/api_service.dart` | LocalApi transport/process boundary |
| `lib/services/api` | endpoint groups as Dart part files |
| `lib/state` | shared store/builder composition |
| `lib/screens` | route/screen surfaces |
| `lib/widgets` | reusable UI organized by journey/surface |
| `lib/theme` | breakpoints, colors, type, spacing, radii and motion |
| `lib/utils` | pure presentation/parsing helpers |
| `macos` | native runner, permissions and platform integration |
| `third_party/fvp` | embedded player adapter dependency |
| `tool` | core artifact install/verify and macOS assembly/smoke |
| `test` | controller, widget, contract and regression tests |
| `test/fixtures` | pinned frontend-owned contract/smoke fixtures |
| `backend.lock.json` | immutable core baseline |
| `.planning` | current frontend project memory |
