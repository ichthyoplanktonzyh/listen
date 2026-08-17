import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/media_workbench.dart';

/// P0-b: the session header stopped being an anonymous menu cluster. It now
/// carries a media breadcrumb (where the learner is) and a labelled, tooltipped
/// tool band whose unwired take-away entries are honestly disabled rather than
/// hidden or offered as clickable promises.
void main() {
  Widget localized(Widget child) => MaterialApp(
    theme: ListenTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  Widget workbench({
    String mediaTitle = 'CNN 10.mp4',
    VoidCallback? onShadow,
    bool canShadow = false,
    Widget? learningEditionAction,
  }) => MediaWorkbench(
    mediaTitle: mediaTitle,
    playerStage: const ColoredBox(color: Colors.black),
    learningPanel: const ColoredBox(color: Colors.white),
    mediaFraction: 0.42,
    onMediaFractionChanged: _noopFraction,
    onShadow: onShadow,
    canShadow: canShadow,
    learningEditionAction: learningEditionAction,
  );

  Tooltip tooltipFor(WidgetTester tester, Key key) => tester.widget<Tooltip>(
    find.ancestor(of: find.byKey(key), matching: find.byType(Tooltip)),
  );

  IconButton buttonFor(WidgetTester tester, Key key) =>
      tester.widget<IconButton>(find.byKey(key));

  testWidgets('the header leads with the unified library breadcrumb', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(localized(workbench()));

    // Library root + the clean title (not the file name), never a fabricated
    // channel name.
    expect(find.text('资料库'), findsOneWidget);
    final crumb = tester.widget<Text>(
      find.byKey(const Key('workbench-breadcrumb-title')),
    );
    expect(crumb.data, 'CNN 10');
    // The raw file name stays one hover away.
    expect(
      tooltipFor(tester, const Key('workbench-breadcrumb-title')).message,
      'CNN 10.mp4',
    );
  });

  testWidgets('the current material owns one learning-package entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = 0;
    await tester.pumpWidget(
      localized(
        workbench(
          learningEditionAction: IconButton(
            key: const Key('learning-edition-action'),
            tooltip: '学习包',
            onPressed: () => opened++,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('learning-edition-action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('learning-edition-action')));
    expect(opened, 1);
  });

  testWidgets('shadow entry is disabled with a reason until a sentence plays', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var shadowed = 0;
    await tester.pumpWidget(
      localized(workbench(onShadow: () => shadowed += 1, canShadow: false)),
    );

    const key = Key('workbench-shadow');
    final button = buttonFor(tester, key);
    expect(button.onPressed, isNull);
    expect(button.tooltip, '播放到某句后即可跟读');
    await tester.tap(find.byKey(key));
    expect(shadowed, 0);
  });

  testWidgets('shadow entry fires on the current sentence when one plays', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var shadowed = 0;
    await tester.pumpWidget(
      localized(workbench(onShadow: () => shadowed += 1, canShadow: true)),
    );

    const key = Key('workbench-shadow');
    final button = buttonFor(tester, key);
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, '跟读当前句');
    await tester.tap(find.byKey(key));
    expect(shadowed, 1);
  });

  testWidgets('unwired take-away entries are shown disabled, with the reason', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(localized(workbench()));

    final export = buttonFor(tester, const Key('workbench-export'));
    final share = buttonFor(tester, const Key('workbench-share'));
    // Present, so the capability is legible — but disabled and honest about
    // why, never a "coming soon" that fakes success.
    expect(export.onPressed, isNull);
    expect(export.tooltip, '导出与打印暂不可用');
    expect(share.onPressed, isNull);
    expect(share.tooltip, '分享暂不可用');
  });

  testWidgets('the header does not overflow in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      localized(
        workbench(
          mediaTitle: 'A very long media title that must ellipsize.mp4',
          learningEditionAction: IconButton(
            onPressed: _noop,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

void _noopFraction(double value) {}

void _noop() {}
