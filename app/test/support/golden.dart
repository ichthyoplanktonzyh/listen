import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

/// The visual regression net (#12 · S10).
///
/// The token-discipline gates (`theme_palette_discipline_test.dart`,
/// `icon_size_discipline_test.dart`, …) catch a *value* that left the ladder.
/// They cannot catch what those values compose into: the coach echo bars had
/// already decayed into two grey blocks, every literal in them still legal,
/// and nobody noticed. A golden is the only test that reads the composition.
///
/// Adding a scene should cost three lines, so everything that has to be true
/// for a pixel comparison to mean anything is settled here once.
///
/// ## What this harness pins
///
/// **Real fonts.** `flutter test` renders every glyph as an Ahem block by
/// default, which would make a typography regression invisible — exactly the
/// class of drift #26/#32 introduced the bundled families to stop. Every
/// family in `FontManifest.json` is loaded before the first frame, driven off
/// the manifest rather than a hand-kept list so a family added to
/// `pubspec.yaml` is covered without touching this file. That includes
/// `MaterialIcons`, without which every icon renders as a hollow box.
///
/// **One surface geometry.** Size and device pixel ratio come from
/// [GoldenSurface] / [goldenScene], never from the ambient test view, and are
/// restored afterwards. Device pixel ratio is pinned at 1 rather than the
/// Retina 2 the app actually runs at: the regressions this net exists to catch
/// are compositional (a block where a gauge should be, a column that stopped
/// being capped), and 1× costs a quarter of the bytes in the repository.
///
/// **Stillness.** A golden of a moving widget is a coin flip. Every scene is
/// pumped with `disableAnimations` set, which is not a blunt "freeze
/// everything" hack but the same reduce-motion signal the app already honours:
/// `AmbientBreath` stops its breath, `ConversationEchoSurface` freezes its
/// drift phase at 0, `ConversationStageShell`'s `AnimatedSwitcher` drops to
/// zero duration, and `ListenMotion` transitions land on their end state. So
/// the frame captured is the app's own reduce-motion frame, and a widget that
/// ignores reduce motion fails loudly here — [pumpGoldenFrame] settles, and a
/// never-ending animation makes that time out instead of quietly sampling a
/// random phase.
///
/// The corollary is a real limit, stated rather than hidden: **this net does
/// not cover motion.** It pins the resting frame of an animated widget, not
/// its curve or duration; those stay the business of the widget tests that
/// already assert `ListenMotion` durations directly.
///
/// **No clock, no locale drift.** Scenes are built from explicit fixtures;
/// nothing here may read `DateTime.now()`. The locale is pinned per scene
/// (default `en`) because a mixed 中英 line changes metrics, so an
/// unspecified locale would make the image depend on test ordering.
///
/// ## Platform honesty
///
/// Golden images are rasteriser output. The baselines committed here were
/// generated on **macOS (arm64, Apple Silicon), Flutter 3.44.1 / Impeller**;
/// they are the reference for a macOS-first desktop app and are *not* expected
/// to match a Linux CI runner byte for byte. Do not "fix" a foreign-platform
/// diff by re-recording. See `docs/development/golden-visual-regression.md`.

/// Fixed surfaces for golden scenes.
///
/// Component sizes are snug boxes — a golden should frame the widget, not a
/// field of empty scaffold, because empty pixels are pixels that can never
/// fail. Window sizes are tied to [ListenBreakpoints] so a scene stays on the
/// side of a fold it was chosen for even if the fold moves.
abstract final class GoldenSurface {
  /// A single control or state widget.
  static const component = Size(520, 260);

  /// A panel-sized surface: a column of controls, a single screen's content.
  static const panel = Size(720, 560);

  /// A specimen sheet (the type ladder, the control gallery).
  static const sheet = Size(720, 620);

  /// A wide, short strip — one graphic that spans its container.
  static const strip = Size(720, 320);

  /// The narrowest window the app supports
  /// ([ListenBreakpoints.minWindowWidth] × [ListenBreakpoints.minWindowHeight]),
  /// enforced by the macOS shell. Anything that breaks here breaks in the
  /// product.
  static const minWindow = Size(
    ListenBreakpoints.minWindowWidth,
    ListenBreakpoints.minWindowHeight,
  );

  /// Just under [ListenBreakpoints.capabilityPortraitSideBySide] (640): the
  /// capability portrait stacks the compass over the bars.
  static const belowPortraitFold = Size(600, 560);

  /// Comfortably over that fold: compass beside the bars.
  static const abovePortraitFold = Size(900, 340);

  /// A full screen at a comfortable desktop width — over every layout fold the
  /// app defines. Wide enough to show a centred column actually centred, and
  /// no wider: empty pixels are pixels that can never fail, and each one is
  /// bytes in the repository forever.
  static const window = Size(880, 620);
}

/// The device pixel ratio every baseline is recorded at. See the library doc
/// for why it is 1 and not the Retina 2 the app ships on.
const goldenDevicePixelRatio = 1.0;

/// Loads every font family declared in `FontManifest.json` — the bundled
/// families plus `MaterialIcons` — into the test font collection.
///
/// Idempotent and safe to await from every scene: the work happens once and
/// later calls join the same future.
Future<void> loadBundledFonts() => _fontsLoaded ??= _loadBundledFonts();

Future<void>? _fontsLoaded;

Future<void> _loadBundledFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Pumps [child] as a full app frame under the golden conditions, and leaves
/// the tester on a settled frame ready to be captured.
///
/// Exposed on its own for the rare scene that has to drive the widget (tap,
/// scroll) before capturing; [goldenScene] is the usual entry point.
///
/// `settle` should stay true. Turning it off means capturing a frame mid-flight
/// and is only defensible for a widget that legitimately never settles — in
/// which case the reduce-motion contract is what wants fixing.
Future<void> pumpGoldenFrame(
  WidgetTester tester, {
  required Widget child,
  required Brightness brightness,
  Size size = GoldenSurface.panel,
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  // `runAsync`, not a bare await. Font loading is real I/O, and the cached
  // future is created inside the first scene's fake-async zone — awaiting it
  // directly from the second scene hangs forever, silently, with no error to
  // read. Escaping to the real zone is what makes the cache safe to share.
  await tester.runAsync(loadBundledFonts);

  tester.view.devicePixelRatio = goldenDevicePixelRatio;
  tester.view.physicalSize = size * goldenDevicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // `MediaQuery.fromView` inside `WidgetsApp` takes the platform-level
    // fields — reduce motion, text scale, bold text — from an ambient
    // MediaQuery when there is one, which is why these are set out here while
    // size and DPR are set on the view above.
    MediaQuery(
      data: const MediaQueryData(
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ListenTheme.light(),
        darkTheme: ListenTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Captures the current frame as `test/goldens/<name>.<brightness>.png`.
Future<void> expectGoldenFrame(
  WidgetTester tester,
  String name,
  Brightness brightness,
) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.${brightness.name}.png'),
);

/// Registers one golden test per brightness for one scene.
///
/// Both brightnesses by default: the charter makes dark the home theme, but
/// light is the one that exposes a hue picked by eye against a dark surface.
/// Pass a single brightness only when the widget itself pins one — the
/// conversation stage forces `ListenTheme.dark()` on its subtree, so a light
/// baseline for it would be a duplicate file pretending to be coverage.
void goldenScene(
  String name, {
  required WidgetBuilder builder,
  Size size = GoldenSurface.panel,
  List<Brightness> brightnesses = const [Brightness.dark, Brightness.light],
  Locale locale = const Locale('en'),
}) {
  for (final brightness in brightnesses) {
    testWidgets('$name · ${brightness.name}', (tester) async {
      await pumpGoldenFrame(
        tester,
        child: Builder(builder: builder),
        brightness: brightness,
        size: size,
        locale: locale,
      );
      await expectGoldenFrame(tester, name, brightness);
    });
  }
}
