import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/discovery_home_screen.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'discovery_test_helpers.dart';

void main() {
  Future<DiscoveryViewModel> pumpDiscovery(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    VoidCallback? onOpenMedia,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenClassicHome,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      TestTranscriptionRepository(),
      TestMediaLibraryRepository(),
    );
    addTearDown(viewModel.dispose);
    await tester.runAsync(() => viewModel.load());
    await tester.pumpWidget(
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
          body: DiscoveryHome(
            viewModel: viewModel,
            onOpenMedia: onOpenMedia ?? () {},
            onOpenSettings: onOpenSettings ?? () {},
            onOpenClassicHome: onOpenClassicHome ?? () {},
          ),
        ),
      ),
    );
    // wait for mock package checking delayed calls
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('renders rail, first channel lessons, and lesson detail', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    expect(find.text('BBC Learning English'), findsWidgets);
    expect(find.text('TED-Ed'), findsOneWidget);
    expect(find.text('英语兔'), findsOneWidget);
    expect(find.text('SciShow'), findsOneWidget);
    expect(find.text('我的学习'), findsOneWidget);

    expect(find.text('6 Minute English: Why do we forget?'), findsNWidgets(2));
    expect(find.text('The English We Speak: on the same page'), findsOneWidget);
    expect(find.text('3 videos'), findsOneWidget);

    expect(find.text('暂无配套学习包'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '下载媒体'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '查看配套学习包'), findsNothing);
  });

  testWidgets('switching channel swaps the lesson shelf', (tester) async {
    await pumpDiscovery(tester);

    await tester.tap(find.text('TED-Ed'));
    // wait for package checking delay
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();

    expect(find.text('How does your brain learn languages?'), findsNWidgets(2));
    expect(find.text('The mysterious science of sleep'), findsOneWidget);
    expect(find.text('6 Minute English: Why do we forget?'), findsNothing);
  });

  testWidgets('selecting a lesson without a package updates the detail', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    await tester.tap(find.text('The English We Speak: on the same page'));
    // wait for package checking delay
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();

    expect(find.text('暂无配套学习包'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, '查看配套学习包'), findsNothing);
    expect(
      find.text('The English We Speak: on the same page'),
      findsNWidgets(2),
    );
  });

  testWidgets('download completes and unlocks the player action', (
    tester,
  ) async {
    var openedMedia = 0;
    await pumpDiscovery(tester, onOpenMedia: () => openedMedia++);

    await tester.tap(find.widgetWithText(FilledButton, '下载媒体'));
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, '取消下载'), findsOneWidget);
    expect(find.textContaining('下载媒体中'), findsWidgets);

    await tester.pump(const Duration(seconds: 2));
    expect(find.widgetWithText(FilledButton, '开始学习'), findsOneWidget);
    expect(find.text('媒体已下载'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '开始学习'));
    expect(openedMedia, 1);
  });

  testWidgets('package dialog lists the package contents and closes', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    // Download first to unlock view package button
    await tester.tap(find.widgetWithText(FilledButton, '下载媒体'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '查看配套学习包'));
    await tester.pumpAndSettle();

    expect(find.text('配套学习包'), findsOneWidget);
    expect(find.text('字幕轨道'), findsOneWidget);
    expect(find.text('词时间轴'), findsOneWidget);
    expect(find.text('发音标注'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('配套学习包'), findsNothing);
  });

  testWidgets('narrow window degrades to channel chips and hides detail', (
    tester,
  ) async {
    await pumpDiscovery(tester, size: const Size(600, 800));

    expect(find.text('我的学习'), findsNothing);
    expect(find.text('媒体源'), findsNothing);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('6 Minute English: Why do we forget?'), findsOneWidget);
    expect(find.text('时长'), findsNothing);
  });

  testWidgets('rail actions reach their callbacks', (tester) async {
    var settings = 0;
    var classicHome = 0;
    await pumpDiscovery(
      tester,
      onOpenSettings: () => settings++,
      onOpenClassicHome: () => classicHome++,
    );

    await tester.tap(find.text('设置'));
    expect(settings, 1);
    await tester.tap(find.text('我的学习'));
    expect(classicHome, 1);
  });
}
