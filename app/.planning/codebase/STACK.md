# Stack

- Flutter/Dart, SDK constraint `^3.12.1`
- App package `0.7.0+8`
- macOS desktop runner
- `video_player` plus embedded `third_party/fvp`/libmdk
- `dart:io` loopback HTTP/process integration
- ChangeNotifier/controllers plus explicit store/builder composition
- Flutter widget/controller/unit/contract tests
- Python standard-library artifact installer tests
- macOS shell tooling for Release assembly, signing preparation and smoke

Runtime backend is not a Dart dependency. It is an installed, checksummed
artifact pinned in `backend.lock.json`.
