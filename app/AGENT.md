# listen-app Agent Notes

This repository owns the Flutter desktop application, its UI behavior, tests,
packaging, and the embedded `fvp` dependency.

## Boundary

- Design features from the user journey and required information first.
- Propose API changes in `listen-core/contracts/openapi/v1.yaml`.
- Do not copy backend source or reach into a sibling checkout.
- Pin one immutable core release in `backend.lock.json`.
- Install and verify pinned artifacts with `python3 tool/backend_artifacts.py
  install`.
- Treat `lib/generated/` as generated-only if contract generation is adopted
  later. The current handwritten compatibility parsers remain authoritative.

## Validation

```sh
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest tool/test_backend_artifacts.py
```

For a macOS release, install the pinned backend artifacts, run
`tool/build-macos-release.sh`, and verify the resulting archive with
`tool/verify-macos-release.sh`.

Every commit-worthy change must add an exact-to-the-minute entry to
`CHANGELOG.md`. Work on a branch and submit a PR; do not push changes directly
to `main`.
