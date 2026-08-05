import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/session_subtitle_menu.dart';
import 'package:llplayer_next/widgets/navigation/shell_tools_menu.dart';

/// What is left of the shell app bar, and where it went.
///
/// That bar was a fourth navigation. Its content and learning menus repeated
/// the native macOS menu bar, the rail, and the pages themselves; its
/// settings button repeated the rail's footer; its wordmark repeated the
/// rail's header forty pixels below it. Its one honest menu — subtitles — was
/// media-scoped, so on every standing destination it rendered as a row of
/// items disabled with a reason: truthful, and useless.
///
/// So the bar is gone and its two real jobs moved to where each applies:
/// media actions to the workbench's session header (which only exists while
/// there *is* media, so nothing there can be dead), and the homeless tools to
/// the foot of the rail beside settings.
///
/// These cases pin what each menu owns, that every item dispatches its own
/// callback, and that no label bypasses [AppLocalizations].
void main() {
  late List<String> fired;

  setUp(() => fired = []);

  Widget wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: ListenTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
  );

  Widget toolsMenu() => ShellToolsMenu(
    onOpenSubtitleResources: () => fired.add('subtitle-resources'),
    onOpenLearningAssets: () => fired.add('learning-assets'),
    onOpenLearningResources: () => fired.add('learning-resources'),
    onOpenTranscriptionCenter: () => fired.add('transcription'),
    onOpenPhoneticAnalysisCenter: () => fired.add('phonetic-analysis'),
    onExportLogs: () => fired.add('logs'),
    onExportVocabulary: () => fired.add('export-vocabulary'),
    onImportVocabulary: () => fired.add('import-vocabulary'),
    onImportWordList: () => fired.add('import-word-list'),
  );

  Widget subtitleMenu() => SessionSubtitleMenu(
    onImportPrimarySubtitle: () => fired.add('import-primary'),
    onGeneratePrimarySubtitles: () => fired.add('generate-primary'),
    onSearchPrimarySubtitles: () => fired.add('search-primary'),
    onImportSecondarySubtitle: () => fired.add('import-secondary'),
    onGenerateSecondarySubtitles: () => fired.add('generate-secondary'),
    onSearchSecondarySubtitles: () => fired.add('search-secondary'),
    onImportEmbeddedSubtitle: () => fired.add('import-embedded'),
    onArchiveMedia: () => fired.add('archive-media'),
  );

  Finder itemOf(String value) => find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );

  /// Menu values in declaration order; section headers carry no value.
  Future<List<String>> openMenu(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    return tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .map((item) => item.value)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<void> tapItem(WidgetTester tester, String value) async {
    await tester.tap(itemOf(value));
    await tester.pumpAndSettle();
  }

  group('the rail\'s tools menu', () {
    testWidgets('owns exactly the things nothing else owns', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(toolsMenu()));

      expect(await openMenu(tester, 'Tools'), [
        'subtitle-resources',
        'learning-assets',
        'learning-resources',
        'transcription',
        'phonetic-analysis',
        'export-vocabulary',
        'import-vocabulary',
        'import-word-list',
        'logs',
      ]);
    });

    testWidgets('never re-offers a destination the rail already carries', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(toolsMenu()));

      final values = await openMenu(tester, 'Tools');
      // Vocabulary and review are segments of "my language"; open-media and
      // open-online are the listen page's own primary cards and the native
      // File menu. The old bar offered all four a second time.
      for (final owned in const [
        'vocabulary',
        'review',
        'open-media',
        'open-online',
        'settings',
      ]) {
        expect(
          values,
          isNot(contains(owned)),
          reason: '"$owned" already has an owner; a copy here is the bug the '
              'app bar was deleted for',
        );
      }
    });

    testWidgets('every item dispatches its own callback', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final value in const [
        'subtitle-resources',
        'learning-assets',
        'learning-resources',
        'transcription',
        'phonetic-analysis',
        'export-vocabulary',
        'import-vocabulary',
        'import-word-list',
        'logs',
      ]) {
        fired = [];
        await tester.pumpWidget(wrap(toolsMenu()));
        await openMenu(tester, 'Tools');
        await tapItem(tester, value);
        expect(fired, [value]);
      }
    });
  });

  group('the workbench\'s subtitle menu', () {
    testWidgets('covers both tracks, embedded import and archiving', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(subtitleMenu()));

      expect(await openMenu(tester, 'Subtitles'), [
        'import-primary',
        'generate-primary',
        'search-primary',
        'import-secondary',
        'generate-secondary',
        'search-secondary',
        'import-embedded',
        'archive-media',
      ]);
    });

    testWidgets('no item is disabled: the header only exists with media', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(subtitleMenu()));
      await openMenu(tester, 'Subtitles');

      // On the app bar every one of these was `mediaGatedItem`, so on the
      // home screen the whole menu was dead. Living on the session header
      // makes the gate structural instead of conditional.
      final selectable = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .where((item) => item.value != null);
      expect(selectable, isNotEmpty);
      for (final item in selectable) {
        expect(item.enabled, isTrue, reason: '${item.value} renders disabled');
      }
    });

    testWidgets('every item dispatches its own callback', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final value in const [
        'import-primary',
        'generate-primary',
        'search-primary',
        'import-secondary',
        'generate-secondary',
        'search-secondary',
        'import-embedded',
        'archive-media',
      ]) {
        fired = [];
        await tester.pumpWidget(wrap(subtitleMenu()));
        await openMenu(tester, 'Subtitles');
        await tapItem(tester, value);
        expect(fired, [value]);
      }
    });
  });

  testWidgets('no menu label survives as a hardcoded English string', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final menu in [
      (widget: toolsMenu(), tooltip: '工具'),
      (widget: subtitleMenu(), tooltip: '字幕'),
    ]) {
      await tester.pumpWidget(wrap(menu.widget, locale: const Locale('zh')));
      await tester.tap(find.byTooltip(menu.tooltip));
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
              '"$label" (menu "${menu.tooltip}") renders no Han characters '
              'under zh, so it bypasses AppLocalizations',
        );
      }

      // Dismiss via the barrier, clear of the menu surface.
      await tester.tapAt(const Offset(900, 850));
      await tester.pumpAndSettle();
    }
  });
}
