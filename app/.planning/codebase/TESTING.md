# Testing

## Required Local Gates

```sh
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest tool/test_backend_artifacts.py
```

## Test Shape

The split baseline contains 130 Dart test files covering:

- models and compatibility parsing;
- controllers/coordinators and async lifecycle;
- widgets, flows, loading/empty/error states and responsive behavior;
- player shortcuts, focus, overlays and native-facing adapters;
- contract fixtures under `test/contract`;
- theme/spacing/radius/motion discipline;
- regression behavior for learning journeys.

## Boundary Validation

Contract-facing changes run focused `test/contract/*` tests. Backend lock or
assembly changes also run:

```sh
python3 tool/backend_artifacts.py verify
tool/build-macos-release.sh
tool/verify-macos-release.sh
```

Normal tests must not require a sibling core checkout. GitHub zero-step failure
from billing is infrastructure; record exact local evidence instead.
