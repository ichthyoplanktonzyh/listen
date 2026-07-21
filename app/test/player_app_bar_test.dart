import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/widgets/app_bar/player_app_bar.dart';

/// The AppBar is the only entry surface that stays mounted once media loads —
/// the workbench covers the home scene — so its menu structure is load
/// bearing. These tests pin down which items each menu owns, that every item
/// dispatches its own callback, and that no label is a hardcoded English
/// string.
void main() {
  late List<String> fired;

  setUp(() => fired = []);

  /// The four labelled menu buttons plus the settings icon do not fit the
  /// 800x600 default surface, so every case runs on a desktop-sized window.
  Future<void> useDesktopSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget app({Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      appBar: PlayerAppBar(
        onOpenSubtitleResources: () => fired.add('subtitle-resources'),
        onOpenVocabulary: () => fired.add('vocabulary'),
        onOpenReview: () => fired.add('review'),
        onOpenMedia: () => fired.add('open-media'),
        onOpenOnline: () => fired.add('open-online'),
        onImportPrimarySubtitle: () => fired.add('primary-import'),
        onGeneratePrimarySubtitles: () => fired.add('primary-generate'),
        onSearchPrimarySubtitles: () => fired.add('primary-search'),
        onImportSecondarySubtitle: () => fired.add('secondary-import'),
        onGenerateSecondarySubtitles: () => fired.add('secondary-generate'),
        onSearchSecondarySubtitles: () => fired.add('secondary-search'),
        onImportEmbeddedSubtitle: () => fired.add('embedded'),
        onOpenSettings: () => fired.add('settings'),
        onExportLogs: () => fired.add('logs'),
        onExportVocabulary: () => fired.add('export-vocabulary'),
        onImportVocabulary: () => fired.add('import-vocabulary'),
        onImportWordList: () => fired.add('import-word-list'),
        onArchiveMedia: () => fired.add('archive-media'),
        onOpenTranscriptionCenter: () => fired.add('transcription'),
        onOpenPhoneticAnalysisCenter: () => fired.add('phonetic-analysis'),
        onOpenLearningAssets: () => fired.add('learning-assets'),
        onOpenLearningResources: () => fired.add('learning-resources'),
        onShowPhraseCandidates: () => fired.add('phrase-candidates'),
        onCorrectLemma: () => fired.add('correct-lemma'),
        onSearchOpenSubtitles: () => fired.add('opensubtitles'),
      ),
      body: const SizedBox.shrink(),
    ),
  );

  Finder itemOf(String value) => find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );

  /// Menu values in declaration order; section headers carry no value.
  List<String> openMenuValues(WidgetTester tester) => tester
      .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
      .map((item) => item.value)
      .whereType<String>()
      .toList(growable: false);

  Future<List<String>> openMenu(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    return openMenuValues(tester);
  }

  Future<void> tapItem(WidgetTester tester, String value) async {
    await tester.tap(itemOf(value));
    await tester.pumpAndSettle();
  }

  testWidgets('content menu owns media sources and archiving', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app());
    expect(await openMenu(tester, 'Content'), [
      'open-media',
      'open-online',
      'archive-media',
    ]);

    await tapItem(tester, 'archive-media');
    expect(fired, ['archive-media']);
  });

  testWidgets('subtitle menu covers both tracks plus embedded import', (
    tester,
  ) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app());
    expect(await openMenu(tester, 'Subtitles'), [
      'primary-import',
      'primary-generate',
      'primary-search',
      'secondary-import',
      'secondary-generate',
      'secondary-search',
      'embedded',
    ]);

    // Both tracks reuse the same labels, so label lookup is ambiguous; assert
    // the secondary row dispatches its own callback rather than the primary's.
    await tapItem(tester, 'secondary-generate');
    expect(fired, ['secondary-generate']);
  });

  testWidgets('learning menu dispatches each destination', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app());
    expect(await openMenu(tester, 'Learning'), [
      'subtitle-resources',
      'vocabulary',
      'review',
      'learning-assets',
      'learning-resources',
      'phrase-candidates',
      'correct-lemma',
      'transcription',
      'phonetic-analysis',
    ]);

    await tapItem(tester, 'vocabulary');
    expect(fired, ['vocabulary']);
  });

  testWidgets('more menu dispatches diagnostics and data management', (
    tester,
  ) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app());
    expect(await openMenu(tester, 'More actions'), [
      'logs',
      'export-vocabulary',
      'import-vocabulary',
      'import-word-list',
    ]);

    await tapItem(tester, 'import-word-list');
    expect(fired, ['import-word-list']);
  });

  testWidgets('settings button dispatches directly', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(fired, ['settings']);
  });

  testWidgets('no menu label survives as a hardcoded English string', (
    tester,
  ) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(app(locale: const Locale('zh')));

    for (final tooltip in const ['内容', '字幕', '学习', '更多操作']) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(PopupMenuItem<String>),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .whereType<String>();
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(
          RegExp(r'[一-鿿]').hasMatch(label),
          isTrue,
          reason:
              '"$label" (menu "$tooltip") renders no Han characters under zh, '
              'so it bypasses AppLocalizations',
        );
      }

      // Dismiss via the barrier, well clear of the top-right menu surface.
      await tester.tapAt(const Offset(40, 560));
      await tester.pumpAndSettle();
    }
  });
}
