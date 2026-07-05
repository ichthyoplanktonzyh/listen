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
    String? recentMediaTitle,
    Duration recentPosition = Duration.zero,
    Duration recentDuration = Duration.zero,
  }) =>
      MaterialApp(
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
    expect(find.text('内容库'), findsOneWidget);
    expect(find.text('开始聆听'), findsOneWidget);
    expect(find.text('学习资料'), findsOneWidget);

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
