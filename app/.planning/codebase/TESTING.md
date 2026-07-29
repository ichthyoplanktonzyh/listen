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
- golden visual regression baselines under `test/goldens`;
- regression behavior for learning journeys.

## Golden Visual Regression

`test/golden_*_test.dart` compare rendered frames against the PNG baselines in
`test/goldens`, using the harness in `test/support/golden.dart`. They cover what
the token-discipline gates cannot: the composition legal values add up to. They
run as part of `flutter test`; no separate command is needed to verify them.

Re-record after an intentional visual change:

```sh
flutter test --update-goldens test/golden_tokens_test.dart \
  test/golden_states_test.dart test/golden_coach_test.dart \
  test/golden_conversation_test.dart
flutter test && flutter test && git status --short test/goldens
```

Baselines are rasteriser output and are recorded on **macOS (arm64), Flutter
3.44.1, Impeller**. A diff produced on another OS, architecture or Flutter
version is not evidence of a design regression, and re-recording there replaces
the reference — do not. Until a macOS runner exists, golden verification is a
local gate whose exact run belongs in the PR.

Scope, update policy, review checklist and the screens deliberately left
uncovered are in `docs/development/golden-visual-regression.md`.

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
