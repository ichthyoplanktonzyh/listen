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
    ValueChanged<String>? onPlayMedia,
    DiscoveryRepository? repository,
    TestMediaLibraryRepository? libraryRepository,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = DiscoveryViewModel(
      repository ?? FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      TestContentPackageRepository(),
      libraryRepository ?? TestMediaLibraryRepository(),
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
            onPlayMedia: onPlayMedia,
          ),
        ),
      ),
    );
    // wait for mock package checking delayed calls
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('renders sources, first channel lessons, and lesson detail', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    expect(find.text('媒体源'), findsOneWidget);
    expect(find.text('BBC Learning English'), findsWidgets);
    expect(find.text('TED-Ed'), findsOneWidget);
    expect(find.text('英语兔'), findsOneWidget);
    expect(find.text('SciShow'), findsOneWidget);

    expect(find.text('6 Minute English: Why do we forget?'), findsNWidgets(2));
    expect(find.text('The English We Speak: on the same page'), findsOneWidget);
    expect(find.text('3 个视频'), findsOneWidget);

    expect(find.text('暂无配套学习包'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '下载媒体'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '查看配套学习包'), findsNothing);
  });

  testWidgets('switching channel swaps the lesson shelf', (tester) async {
    await pumpDiscovery(tester);

    await tester.tap(find.text('TED-Ed'));
    // wait for package checking delay
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
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
    final played = <String>[];
    await pumpDiscovery(
      tester,
      onOpenMedia: () => openedMedia++,
      onPlayMedia: played.add,
    );

    await tester.tap(find.widgetWithText(FilledButton, '下载媒体'));
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, '取消下载'), findsOneWidget);
    expect(find.textContaining('下载媒体中'), findsWidgets);

    await tester.pump(const Duration(seconds: 2));
    expect(find.widgetWithText(FilledButton, '开始学习'), findsOneWidget);
    expect(find.text('媒体已下载'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '开始学习'));
    // The button opens *this* entry's file, never the generic file picker.
    expect(played, ['/path/to/downloaded/[i-bbc-1].mp4']);
    expect(openedMedia, 0);
  });

  testWidgets('the player action stays disabled without a local file', (
    tester,
  ) async {
    var openedMedia = 0;
    // No `onPlayMedia`: nothing in this app can play the entry, so the
    // affordance must not pretend otherwise by falling back to a file picker.
    await pumpDiscovery(tester, onOpenMedia: () => openedMedia++);

    await tester.tap(find.widgetWithText(FilledButton, '下载媒体'));
    await tester.pump(const Duration(seconds: 2));

    final player = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始学习'),
    );
    expect(player.onPressed, isNull);
    expect(openedMedia, 0);
  });

  testWidgets('a failed feed reads as failed, not as an empty channel', (
    tester,
  ) async {
    final repository = TestDiscoveryRepository(
      sources: [testMediaSource('c-one', name: 'One')],
      entries: {
        'c-one': [testMediaEntry('e-one', 'c-one')],
      },
    )..failingSources.add('c-one');

    await pumpDiscovery(tester, repository: repository);

    expect(find.text('这个媒体源加载失败。'), findsOneWidget);
    expect(find.text('这个媒体源还没有视频。'), findsNothing);
    expect(find.text('3 个视频'), findsNothing);

    repository.failingSources.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个媒体源加载失败。'), findsNothing);
    expect(find.text('Entry e-one'), findsWidgets);
  });

  testWidgets('a disconnected core reports an unchecked package, not none', (
    tester,
  ) async {
    await pumpDiscovery(
      tester,
      libraryRepository: TestMediaLibraryRepository(available: false),
    );

    expect(find.text('无法确认学习包状态'), findsWidgets);
    expect(find.text('暂无配套学习包'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '重新查询'), findsOneWidget);
    // Nothing may be generated on an answer nobody has.
    expect(find.widgetWithText(FilledButton, '生成学习资源包'), findsNothing);
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

    expect(find.text('媒体源'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('6 Minute English: Why do we forget?'), findsOneWidget);
    expect(find.text('时长'), findsNothing);
  });
}
