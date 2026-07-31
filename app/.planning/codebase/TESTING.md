# Testing

## Required Local Gates

```sh
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest tool/test_backend_artifacts.py
```

`analysis_options.yaml` enables `strict-casts`, `strict-inference` and
`strict-raw-types` on top of `flutter_lints`, so an implicit downcast, an
uninferable collection literal or a raw generic is a build-blocking
diagnostic rather than a silent `dynamic`.

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

## Source-Level Discipline Gates

Seven `*_discipline_test.dart` files scan `lib/` for a shape rather than
exercising behavior, all sharing `test/support/dart_source.dart`:

| Gate | Forbids |
| --- | --- |
| `theme_palette_discipline_test` | a colour literal outside the palette |
| `radius_discipline_test` | a corner radius outside `ListenRadii` |
| `spacing_discipline_test` | a gap outside the `ListenSpacing` ladder |
| `loading_discipline_test` | a wait state that is not `ListenLoading` |
| `icon_size_discipline_test` | an icon size outside `ListenIconSize` |
| `typography_slot_discipline_test` | an unmapped Material type slot |
| `column_width_discipline_test` | a hardcoded content `maxWidth` |
| `error_leak_discipline_test` | a caught exception inside user-visible text |
| `cjk_literal_discipline_test` | Chinese copy welded into `lib/` (#7) |

The last two carry a `knownOffenders` allowlist plus a companion test asserting
the list **only shrinks**: a file that stops offending must leave it, so the
count stays an honest measure of the remaining debt and the list cannot be
padded to force green. Never add an entry; the way past one of these gates is to
fix the file.

Each gate's own library doc states its known limits — they are textual scans,
not proofs of absence. `docs/development/ui-terminology.md` records which terms
are allowed to stay English, so the CJK gate's exemptions have a reason on file
rather than being argued again per key.

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
