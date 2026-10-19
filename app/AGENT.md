# App implementation guide

Read [the root guide](../AGENT.md) and [DEVELOPMENT.md](../DEVELOPMENT.md).
`app/` is the learner-facing Flutter module of the Listen monorepo. A feature
may change App, Core, Gen and their contracts together in one branch/PR.

## Local constraints

- Facts and executable tests outrank outdated architecture prose. Explain a
  better design when replacing a convention and update affected docs.
- UI language and learning language are separate. Do not hardcode interface
  sentences in `lib/`; use `AppLocalizations.of(context).text('key')` and add
  both `en` and `zh` entries in `lib/localization.dart`.
- Spacing, typography, colors, loading/error behavior, CJK literals and layering
  are enforced by `test/*_discipline_test.dart` and
  `test/architecture_layering_test.dart`. Read those tests for their rationale;
  do not duplicate their rules in prose.
- Add widget previews for new discovery UI states. Existing architecture tests
  take priority over generic external Flutter architecture recipes.
- Keep the local HTTP interface and Core-owned semantics. App adapts typed
  reads and learner intent; it does not interpret provider-native Gen output
  as canonical learning material.
- Preserve sidecar authentication, startup compatibility, process cleanup,
  generation cancellation, and deterministic failure reporting.
- Development may use the explicitly generated current-source Gen lock in
  debug builds. Production loads its embedded generated lock and verifies the
  exact bundled bytes. Do not weaken release verification to simplify dev.
- Do not commit `.backend/`, `.listen-gen/`, build output, credentials, local
  media, or learner data. Historical committed component locks describe the
  pre-migration release baseline, not the current-source development stack.

## Verification

From this directory:

```sh
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
```

From the repository root, `./dev test integration` exercises the fixture-based
Gen → package → Core → App flow. `./dev release` builds and verifies the product
from a clean source commit. See the root development guide for prerequisites,
release runtime inputs and manual smoke checks. Report exact executed results;
there is no checked-in GitHub Actions workflow running these gates.

## Documentation

`CONTEXT.md` adds only App interaction language. Project semantics and active
status/roadmap live at the repository root. Module `.planning/`, old handoffs
and local ADRs are implementation/history evidence; do not execute superseded
plans. Root and module changelogs are release-only.
