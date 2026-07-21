import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';

void main() {
  Widget app({
    required VoidCallback onOpenMedia,
    VoidCallback? onOpenOnline,
    VoidCallback? onContinue,
    VoidCallback? onOpenPersonalExpressions,
    String? recentMediaTitle,
    Duration recentPosition = Duration.zero,
    Duration recentDuration = Duration.zero,
  }) => MaterialApp(
    theme: ListenTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ListeningHome(
        onOpenMedia: onOpenMedia,
        onOpenOnline: onOpenOnline ?? () {},
        onContinue: onContinue ?? () {},
        onOpenSubtitleResources: () {},
        onOpenVocabulary: () {},
        onOpenPersonalExpressions: onOpenPersonalExpressions ?? () {},
        onOpenReview: () {},
        onOpenCoach: () {},
        onOpenSettings: () {},
        recentMediaTitle: recentMediaTitle,
        recentPosition: recentPosition,
        recentDuration: recentDuration,
      ),
    ),
  );

  testWidgets('wide home shows navigation and opens local media', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openMediaCalls = 0;

    await tester.pumpWidget(app(onOpenMedia: () => openMediaCalls += 1));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('学习首页'), findsOneWidget);
    expect(find.text('继续当前内容会话'), findsOneWidget);
    expect(find.text('添加内容来源'), findsOneWidget);
    expect(find.text('到期任务与学习资产'), findsOneWidget);

    await tester.tap(find.text('打开视频或音频'));
    expect(openMediaCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact home stacks source actions without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openOnlineCalls = 0;

    await tester.pumpWidget(
      app(onOpenMedia: () {}, onOpenOnline: () => openOnlineCalls += 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsNothing);
    await tester.tap(find.text('打开网址'));
    expect(openOnlineCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide home exposes my-expressions entries in sidebar and assets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openCalls = 0;

    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        onOpenPersonalExpressions: () => openCalls += 1,
      ),
    );
    await tester.pumpAndSettle();

    // One entry in the "my learning" sidebar, one card in the asset area.
    final entries = find.text('我的表达');
    expect(entries, findsNWidgets(2));

    await tester.tap(entries.first);
    await tester.ensureVisible(entries.last);
    await tester.tap(entries.last, warnIfMissed: false);
    expect(openCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact home stacks my-expressions card without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openCalls = 0;

    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        onOpenPersonalExpressions: () => openCalls += 1,
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.text('我的表达');
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry, warnIfMissed: false);
    expect(openCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent media surfaces a continue entry that resumes playback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var continueCalls = 0;
    var openMediaCalls = 0;

    await tester.pumpWidget(
      app(
        onOpenMedia: () => openMediaCalls += 1,
        onContinue: () => continueCalls += 1,
        recentMediaTitle: 'BBC News Review.mp4',
        recentPosition: const Duration(minutes: 3, seconds: 20),
        recentDuration: const Duration(minutes: 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BBC News Review.mp4'), findsOneWidget);

    await tester.tap(find.text('继续播放'));
    expect(continueCalls, 1);
    expect(openMediaCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
