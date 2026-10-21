# App UI checks

Run commands below from `app/`. Shared setup and release checks are in
[DEVELOPMENT.md](../../DEVELOPMENT.md).

## UI and localization

Interface strings live in [localization.dart](../../app/lib/localization.dart).
Add matching English and Chinese entries and use the localization API from
widgets. Product/vendor names, formats, identifiers, and language endonyms
are handled by the actual allowlists and assertions in
[cjk_literal_discipline_test.dart](../../app/test/cjk_literal_discipline_test.dart).
Read that test when changing terminology; do not infer an exemption from a
word's technical appearance.

Layout tokens, theme roles, loading states, error text, and layer boundaries
are checked by `test/*_discipline_test.dart` and
[architecture_layering_test.dart](../../app/test/architecture_layering_test.dart).
Use those tests and the current theme implementation as the authority for
exact values. Present unavailable/error/cancelled states honestly; provider
exceptions and internal enum values are not interface copy.

## Golden tests

The current harness is [test/support/golden.dart](../../app/test/support/golden.dart).
Scenes live in `test/golden_*_test.dart`, committed images in `test/goldens/`,
and failure images in ignored `test/failures/`.

```sh
flutter test test/golden_tokens_test.dart test/golden_states_test.dart
```

Golden images depend on the OS, Flutter/rendering toolchain, fonts, locale,
geometry, and animation state. Use the harness's fixed fixtures and record the
actual comparison environment. A platform/toolchain mismatch is not evidence
that the UI should be changed. Keep toolchain-induced baseline updates
separate from intentional UI changes.

For an intentional visual change, review the generated master/test/diff images
before updating only the affected baselines:

```sh
flutter test --update-goldens test/golden_states_test.dart
flutter test test/golden_states_test.dart
```

Run new scenes through the existing `goldenScene` helper and deterministic
fixtures. Confirm the intended light/dark states and relevant widths. Tests
must settle animations without live clocks, providers, or learner data.
A passing widget test alone does not establish that a composition is readable;
review the resulting image.
