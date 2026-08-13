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
    String locale = 'zh',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = DiscoveryViewModel(
      repository ?? FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      libraryRepository ?? TestMediaLibraryRepository(),
    );
    addTearDown(viewModel.dispose);
    await tester.runAsync(() => viewModel.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.light(),
        locale: Locale(locale),
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

    // A remote entry's detail offers the single start-learning intent.
    expect(find.text('媒体尚未在本机'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始学习'), findsOneWidget);
    expect(find.text('暂无配套学习包'), findsNothing);
    expect(find.text('查看配套学习包'), findsNothing);
  });

  testWidgets('switching channel swaps the lesson shelf', (tester) async {
    await pumpDiscovery(tester);

    await tester.tap(find.text('TED-Ed'));
    await tester.pumpAndSettle();

    expect(find.text('How does your brain learn languages?'), findsNWidgets(2));
    expect(find.text('The mysterious science of sleep'), findsOneWidget);
    expect(find.text('6 Minute English: Why do we forget?'), findsNothing);
  });

  testWidgets('selecting another lesson updates the detail panel', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    await tester.tap(find.text('The English We Speak: on the same page'));
    await tester.pumpAndSettle();

    expect(
      find.text('The English We Speak: on the same page'),
      findsNWidgets(2),
    );
    expect(find.widgetWithText(FilledButton, '开始学习'), findsOneWidget);
  });

  testWidgets(
    'start learning on a remote entry acquires the media and opens the workbench automatically',
    (tester) async {
      final played = <String>[];
      await pumpDiscovery(tester, onPlayMedia: played.add);

      await tester.tap(find.widgetWithText(FilledButton, '开始学习'));
      await tester.pump();

      // The acquisition progress stays visible on the detail panel.
      expect(find.text('正在获取媒体…'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '取消下载'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // One intent, one open: no second tap after the download finishes.
      expect(played, ['/path/to/downloaded/[i-bbc-1].mp4']);
    },
  );

  testWidgets('the start-learning action stays disabled with no player', (
    tester,
  ) async {
    // No `onPlayMedia`: nothing in this app can play the entry, so the
    // affordance must not pretend otherwise by falling back to a file picker.
    await pumpDiscovery(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始学习'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a failed feed reads as failed, not as an empty channel', (
    tester,
  ) async {
    final repository = TestDiscoveryRepository(
      sources: [testContentSource('c-one', name: 'One')],
      entries: {
        'c-one': [testDiscoveryItem('e-one', 'c-one')],
      },
    )..failingSources.add('c-one');

    await pumpDiscovery(tester, repository: repository);

    expect(find.text('这个媒体源加载失败。'), findsOneWidget);
    expect(find.text('这个媒体源还没有视频。'), findsNothing);
    expect(find.text('3 个视频'), findsNothing);

    repository.failingSources.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
    await tester.pumpAndSettle();

    expect(find.text('这个媒体源加载失败。'), findsNothing);
    expect(find.text('Entry e-one'), findsWidgets);
  });

  testWidgets(
    'a disconnected core reports an undetermined answer, not remote and not a dead CTA',
    (tester) async {
      await pumpDiscovery(
        tester,
        libraryRepository: TestMediaLibraryRepository(available: false),
      );

      expect(find.text('暂时无法确认本地媒体'), findsWidgets);
      expect(find.widgetWithText(OutlinedButton, '重新检查'), findsOneWidget);
      // Nothing may be started on an answer nobody has.
      expect(find.widgetWithText(FilledButton, '开始学习'), findsNothing);
      expect(find.text('媒体尚未在本机'), findsNothing);
    },
  );

  testWidgets('local media shows "已在本机" and opens without downloading', (
    tester,
  ) async {
    final played = <String>[];
    await pumpDiscovery(
      tester,
      onPlayMedia: played.add,
      libraryRepository: TestMediaLibraryRepository(
        seed: [
          TestMediaLibraryRepository.entry(
            id: 'media-i-bbc-1',
            path: '/library/[i-bbc-1].mp4',
          ),
        ],
      ),
    );

    expect(find.text('已在本机'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '开始学习'));
    await tester.pumpAndSettle();

    expect(played, ['/library/[i-bbc-1].mp4']);
  });

  testWidgets(
    'the narrow bottom sheet stays open through acquisition and closes on success',
    (tester) async {
      final played = <String>[];
      await pumpDiscovery(
        tester,
        size: const Size(600, 800),
        onPlayMedia: played.add,
      );

      await tester.tap(find.text('6 Minute English: Why do we forget?'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '开始学习'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '开始学习'));
      await tester.pump();

      // The sheet must not close on press: the progress needs a surface.
      expect(find.text('正在获取媒体…'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '取消下载'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(played, ['/path/to/downloaded/[i-bbc-1].mp4']);
      // The sheet closed itself after the path was ready.
      expect(find.text('正在获取媒体…'), findsNothing);
    },
  );

  testWidgets('an unacquirable entry explains itself instead of a dead CTA', (
    tester,
  ) async {
    final repository = TestDiscoveryRepository(
      sources: [testContentSource('c-notes', name: 'Notes')],
      entries: {
        'c-notes': [testUnacquirableItem('i-notes', 'c-notes')],
      },
    );
    await pumpDiscovery(tester, repository: repository);

    expect(find.text('当前无法自动获取此内容'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始学习'), findsNothing);
    expect(find.widgetWithText(FilledButton, '下载媒体'), findsNothing);
  });

  testWidgets('discovery surfaces carry no package or generator vocabulary', (
    tester,
  ) async {
    await pumpDiscovery(tester);

    for (final forbidden in ['学习包', '资源包', '生成']) {
      expect(
        find.textContaining(forbidden, findRichText: true),
        findsNothing,
        reason: 'Discovery must not speak package/generation language',
      );
    }
  });

  testWidgets('english discovery surfaces carry no package vocabulary', (
    tester,
  ) async {
    await pumpDiscovery(tester, locale: 'en');

    for (final forbidden in ['Package', 'Generate', 'listen-gen']) {
      expect(
        find.textContaining(forbidden, findRichText: true),
        findsNothing,
        reason: 'Discovery must not speak package/generation language',
      );
    }
  });
}
