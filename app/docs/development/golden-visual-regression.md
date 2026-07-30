# Golden Visual Regression

Reference for `test/support/golden.dart`, `test/golden_*_test.dart` and the
baseline images in `test/goldens/`. Issue [#12].

## Why this exists

The token-discipline gates (`theme_palette_discipline_test.dart`,
`icon_size_discipline_test.dart`, `spacing_discipline_test.dart`,
`radius_discipline_test.dart`, `typography_slot_discipline_test.dart`,
`column_width_discipline_test.dart`) can only see a *value* that left the
ladder. They cannot see what the legal values compose into.

The coach's echo bars are the proof. They had decayed into two flat grey
blocks — the scale included the `unassessed` count, so the bar's entire visual
mass was drawing *what we do not know* — and every colour, radius and spacing
literal in them was still perfectly legal. Every test passed. It was found by a
human reading a screenshot, months later.

A golden is the only test in this repository that reads the composition.

## What is on the net today

| Baseline | Covers |
| --- | --- |
| `tokens_type_and_color` | `ListenType` ladder (incl. mono/IPA), scheme roles with their on-colours, `ListenSchemeShades`, the charter's brightness-independent lights, `ListenRadii` tiers, `ListenIconSize` steps beside their text band |
| `tokens_controls` | Every component family `ListenTheme` styles, resting + disabled: buttons, icon buttons, chips, switch, checkbox, slider, progress, input, divider, card |
| `wordmark` | `ListenWordmark` lockup + bare mark; the brand constants must not flip with the theme |
| `state_empty` / `state_error` / `state_loading` | The shared state language (#46), including `ListenLoading`'s breathing mark — the thing `loading_discipline_test.dart` cannot see |
| `coach_capability_portrait_{wide,narrow,unassessed}` | The repaired capability portrait (S3), on both sides of the `capabilityPortraitSideBySide` fold |
| `conversation_echo_{inactive,listening,learnerSpeaking,thinking,assistantSpeaking}` | The 回声水面's five rooms — the design claims they are told apart without a label |
| `conversation_stage`, `conversation_stage_min_window` | The stage composition and「唯一光源」, at a comfortable window and at the shell's minimum |
| `conversation_lobby`, `conversation_lobby_first_run` | The rebuilt lobby (S4): one heading, one 56pt action, everything else folded |

Each baseline exists once per brightness (`<name>.dark.png` /
`<name>.light.png`) except the stage scenes, which pin dark only — the stage
forces `ListenTheme.dark()` on its subtree under both themes, so a light file
would be a byte-identical duplicate pretending to be coverage.

## What is deliberately *not* on the net

**Screens under active rebuild.** A baseline recorded for a screen that is
being redesigned expires the day it lands, and a stale baseline trains
reviewers to re-record without looking — which is how a visual regression net
becomes a rubber stamp. Left empty on purpose:

| Screen | Slice | Add baselines after |
| --- | --- | --- |
| 我的表达 (`personal_expression_screen`) | S9 | PR [#63] merges |
| 词汇本 (`vocabulary_screen`, entry detail) | S7 | that slice merges |
| 播放器主屏 (`player_stage`, `playback_bar`, `transcript_panel`) | S8 | that slice merges |
| Everything, re-checked | S6 i18n, S2 token migration | both merge — S6 changes strings (and therefore line breaks) on almost every surface, S2 changes padding and icon sizes app-wide |

The exact follow-up is one scene registration plus one record command; see
[Adding a scene](#adding-a-scene) and [Updating baselines](#updating-baselines).

**Motion.** These images pin the *resting* frame of an animated widget, never
its curve or duration. Durations stay the business of the widget tests that
assert `ListenMotion` values directly.

**Anything that needs a `lib/` change to become deterministic.** Currently one
known case: the conversation lobby's history rows render
`DateTime.fromMillisecondsSinceEpoch` in the machine's local zone, so the same
fixture reads `14:43` in UTC and `22:43` in UTC+8. They stay off the net until
the panel accepts an injectable clock/zone. Their wording is pinned directly in
`realtime_conversation_panel_test.dart`.

## What the net has caught so far

One defect, on its first day, and it is the argument for the whole approach.

`conversation_lobby.light.png` was recorded showing an unreadable screen.
`ConversationStageShell` applied `ListenTheme.dark()` to its *child*, but the
panel **built** the lobby with its own outer `BuildContext` — so under the light
app theme the lobby's ink resolved against the light scheme while the ground
behind it stayed `ListenColors.stageGround`. `titleLarge` landed at `#1d2623` on
`#141d1a`: the heading and the "Recent conversations" label were effectively
invisible.

Every widget was present, every colour literal legal, every widget test green.
Only the picture showed it.

Fixed in S6 (#7): the shell takes a `WidgetBuilder` instead of a `Widget`, so
the room is built from a context below the dark `Theme` and the light-theme
path is no longer representable. The baseline was re-recorded in the same
commit, and `conversation_stage_shell_test.dart` now also asserts the cheap
version of the claim — the context the lobby's ink comes from is a dark one.

The general rule this leaves behind: **do not commit a baseline of a screen you
know to be wrong.** Recording the defect was defensible only because the fix
was out of that slice's scope and the note was carried in three places at once;
a red picture that survives review teaches reviewers to stop looking, which
costs more than the bug.

## Determinism

Everything a pixel comparison depends on is settled once in
`test/support/golden.dart`; read its library doc before changing it. In short:

- **Real fonts.** `flutter test` renders Ahem blocks by default, which would
  make every typography regression invisible. Every family in
  `FontManifest.json` is loaded — driven off the manifest, so a family added to
  `pubspec.yaml` is covered without editing the harness — including
  `MaterialIcons`, without which icons draw as hollow boxes.
- **Fixed geometry.** Size and device pixel ratio come from `GoldenSurface`,
  never from the ambient test view. DPR is pinned at 1, not the Retina 2 the
  app ships on: the regressions this net catches are compositional, and 1×
  costs a quarter of the bytes.
- **Stillness via reduce motion.** Scenes are pumped with `disableAnimations`
  set — the same signal the app already honours, not a freeze hack — then
  settled. `AmbientBreath` holds its breath, `ConversationEchoSurface` freezes
  its drift phase, `AnimatedSwitcher` drops to zero duration. A widget that
  *ignores* reduce motion makes `pumpAndSettle` time out, which is the correct
  outcome: fix the widget, do not disable the settle.
- **No clock.** Scenes are built from explicit fixtures. Nothing under
  `test/golden_*_test.dart` may read `DateTime.now()`.
- **Pinned locale**, because a mixed 中英 line changes metrics.

If a baseline flickers between two runs on one machine, that is a bug in the
scene, not a tolerance to configure. `matchesGoldenFile` compares exactly, and
this repository keeps it that way.

## Platform honesty

**The committed baselines were recorded on macOS 15 (arm64, Apple Silicon),
Flutter 3.44.1 / Dart 3.12.1, Impeller.**

Golden images are rasteriser output. A different OS, CPU architecture, Flutter
version or rendering backend will produce different bytes for identical widget
code. This is a macOS-first desktop product, so macOS is the reference and the
only platform whose diffs mean anything.

Consequences, stated rather than papered over:

- **Do not treat a foreign-platform diff as a design regression**, and never
  "fix" one by re-recording on that platform — that silently replaces the
  reference.
- **CI cannot arbitrate these.** GitHub Actions is intermittently unavailable
  here for account-billing reasons (AGENT.md), and even when it runs, a Linux
  runner is not a valid comparator for macOS baselines. Until a macOS runner
  exists, golden verification is a **local gate**: the PR records the exact
  local run, exactly as the repository already does for every other gate.
- **A Flutter upgrade will churn every baseline.** That is expected. Re-record
  in a commit that does nothing else, so the diff is reviewable as "toolchain
  moved" rather than hiding a design change inside it.

## Updating baselines

Verify (part of the normal `flutter test` run):

```sh
flutter test
```

Re-record every baseline:

```sh
flutter test --update-goldens test/golden_tokens_test.dart \
  test/golden_states_test.dart test/golden_coach_test.dart \
  test/golden_conversation_test.dart
```

Re-record one file, or one scene:

```sh
flutter test --update-goldens test/golden_coach_test.dart
flutter test --update-goldens test/golden_coach_test.dart \
  --plain-name 'coach_capability_portrait_wide · dark'
```

Then confirm the recording is stable before pushing — run the suite twice and
expect a clean tree both times:

```sh
flutter test && flutter test && git status --short test/goldens
```

### When to update

Only when the change to the picture *is* the change you are shipping.

- Intentional visual change → re-record, and the diff images are the review
  artefact.
- Unintentional diff → do not re-record. The net just did its job.
- Toolchain/platform change → re-record alone, in its own commit.

### What a reviewer looks at

When a golden fails, `flutter test` writes four PNGs to **`test/failures/`**
(next to the test file, not next to the baseline — the directory is
gitignored):

| File | Use |
| --- | --- |
| `<name>_isolatedDiff.png` | Start here. Only the changed pixels, in colour, over a washed-out copy of the frame — it reads as "what moved". |
| `<name>_maskedDiff.png` | The changed pixels over the master image. |
| `<name>_masterImage.png` / `<name>_testImage.png` | Before and after, for flipping between. |

A golden diff is a picture, so review it as one:

1. **Is every changed baseline explained by the PR's stated intent?** A slice
   that says "vocabulary chip overflow" has no business changing
   `tokens_controls`.
2. **Did anything change that the author did not mention?** That is the whole
   point of the net — the second, unnoticed screen.
3. **Are the light and dark baselines both still honest?** A hue picked by eye
   against the dark stage is the classic way light regresses unseen.
4. **Did a baseline get deleted?** Deleting a scene removes coverage; it needs
   the same justification as deleting a test.

## Adding a scene

Three lines in a `test/golden_*_test.dart` file:

```dart
goldenScene(
  'coach_capability_portrait_wide',
  size: GoldenSurface.abovePortraitFold,
  builder: (context) => _portrait(_portraitChannels),
);
```

Then record it with the command above. Notes:

- Scene files live directly under `test/` so `matchesGoldenFile` resolves to
  `test/goldens/`.
- Pick a `GoldenSurface` that frames the widget. Empty pixels are pixels that
  can never fail, and they are bytes in the repository forever.
- Pass a single `brightnesses` entry only when the widget itself pins one.
- Build the scene from fixtures the test owns. If a widget cannot be made
  deterministic without changing `lib/`, leave it off the net and say so —
  here, in "What is deliberately not on the net".

[#12]: https://github.com/ichthyoplanktonzyh/listen-app/issues/12
[#63]: https://github.com/ichthyoplanktonzyh/listen-app/pull/63
