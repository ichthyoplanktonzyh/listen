import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/settings/settings_dialog.dart';

void main() {
  testWidgets('semantic options show available sense-group data', (
    tester,
  ) async {
    await _pumpSettingsDialog(
      tester,
      senseGroupsAvailable: true,
      groupingMode: 'semantic',
    );

    expect(find.text('Semantic · Available'), findsOneWidget);
    await tester.tap(find.text('Semantic · Available'));
    await tester.pumpAndSettle();
    expect(find.text('Compare · Available'), findsOneWidget);
  });

  testWidgets('semantic options explain missing data and remain selectable', (
    tester,
  ) async {
    String? selectedMode;
    await _pumpSettingsDialog(
      tester,
      senseGroupsAvailable: false,
      groupingMode: 'off',
      onGroupingModeChanged: (value) => selectedMode = value,
    );

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(find.text('Semantic · Data not ready'), findsOneWidget);
    expect(find.text('Compare · Data not ready'), findsOneWidget);

    await tester.tap(find.text('Semantic · Data not ready'));
    await tester.pumpAndSettle();
    expect(selectedMode, 'semantic');
    expect(find.text('Semantic · Data not ready'), findsOneWidget);
    expect(
      find.text(
        'Semantic grouping data is not ready; '
        'subtitles fall back to word display',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an app-wide rebuild while the dialog is open does not tear it '
      'down', (tester) async {
    final host = GlobalKey<_LiveSettingsHostState>();
    await _pumpSettingsDialog(
      tester,
      senseGroupsAvailable: true,
      groupingMode: 'semantic',
      hostKey: host,
    );

    // Picking an appearance flips the theme above the MaterialApp, so the whole
    // app — including this dialog — rebuilds. Regression: the dialog's
    // didUpdateWidget used to re-run its full initializer, re-assigning
    // `late final` text controllers and throwing LateInitializationError, which
    // then cascaded into deactivated-ancestor and duplicate-GlobalKey errors.
    host.currentState!.setThemeMode('dark');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(SettingsDialog))).brightness,
      Brightness.dark,
    );

    // The dialog adopted the host's new value rather than keeping a stale one.
    final state = tester.state<State<SettingsDialog>>(
      find.byType(SettingsDialog),
    );
    expect((state.widget).themeMode, 'dark');

    // A second rebuild must be just as safe.
    host.currentState!.setThemeMode('light');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.byType(SettingsDialog))).brightness,
      Brightness.light,
    );
  });

  testWidgets('the shortcut cheat-sheet button sizes its icon from the ladder', (
    tester,
  ) async {
    await _pumpSettingsDialog(
      tester,
      senseGroupsAvailable: true,
      groupingMode: 'semantic',
    );

    // The dialog body is a lazy `ListView` and this button is its last row, so
    // it has to be scrolled into existence before it can be read.
    final button = find.widgetWithText(
      OutlinedButton,
      'View keyboard shortcuts',
    );
    // `scrollable:` is explicit because the body's text fields each own a
    // horizontal `Scrollable`; the vertical list is the first one.
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Was 16 — one point off the `control` step used by every other icon in
    // this dialog, so the keyboard glyph read a shade lighter than its row.
    // Scoped to the button because the category rail carries the same glyph,
    // sized by `IconTheme` rather than by a literal — that one was never an
    // offender and must stay untouched.
    final icon = tester.widget<Icon>(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.keyboard_outlined),
      ),
    );
    expect(icon.size, ListenIconSize.control);
  });
}

Future<void> _pumpSettingsDialog(
  WidgetTester tester, {
  required bool senseGroupsAvailable,
  required String groupingMode,
  ValueChanged<String>? onGroupingModeChanged,
  GlobalKey<_LiveSettingsHostState>? hostKey,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _LiveSettingsHost(
      key: hostKey,
      builder: (themeMode, onThemeModeChanged) => SettingsDialog(
        language: 'en',
        themeMode: themeMode,
        subtitlePreset: 'learning',
        primaryFontSize: 24,
        primaryFontFamily: 'system',
        secondaryFontSize: 18,
        secondaryFontFamily: 'system',
        subtitlePositionX: 0.5,
        subtitlePositionY: 0.8,
        subtitleBackgroundOpacity: 0.5,
        markKeysEnabled: true,
        onMarkKeysEnabledChanged: (_) {},
        transcriptWidth: 360,
        primaryColor: Colors.white,
        secondaryColor: Colors.grey,
        transcriptionQuality: 'balanced',
        transcriptionLanguage: 'auto',
        transcriptionDestination: 'primary',
        ffmpegPath: '',
        ffprobePath: '',
        ytDlpPath: '',
        openSubtitlesApiKey: '',
        wordSyncVisible: true,
        groupingMode: groupingMode,
        senseGroupsAvailable: senseGroupsAvailable,
        chunkDisplayStyle: 'capsule',
        highlightCurrentChunk: true,
        chunkHighlightStyle: 'background',
        wordHighlightStyle: 'background',
        wordAnimationIntensity: 0.5,
        ruleHintsLevel: 'likely',
        phonemeRibbonVisible: false,
        soundPatternRibbonVisible: false,
        soundPatternDisplayMode: 'citation',
        phonemeRibbonStyle: 'window',
        phoneticAnalysisPreference: 'on_demand',
        learningLanguage: 'auto',
        availableLanguages: const ['en', 'zh'],
        l1Language: '',
        onLearningLanguageChanged: (_) {},
        onL1LanguageChanged: (_) {},
        onLanguageChanged: (_) {},
        onThemeModeChanged: onThemeModeChanged,
        onSubtitlePresetChanged: (_) {},
        onPrimaryFontSizeChanged: (_) {},
        onPrimaryFontFamilyChanged: (_) {},
        onSecondaryFontSizeChanged: (_) {},
        onSecondaryFontFamilyChanged: (_) {},
        onSubtitlePositionXChanged: (_) {},
        onSubtitlePositionYChanged: (_) {},
        onSubtitlePositionReset: () {},
        onBackgroundOpacityChanged: (_) {},
        onTranscriptWidthChanged: (_) {},
        onPrimaryColorChanged: (_) {},
        onSecondaryColorChanged: (_) {},
        onTranscriptionQualityChanged: (_) {},
        onTranscriptionLanguageChanged: (_) {},
        onTranscriptionDestinationChanged: (_) {},
        onWordSyncVisibleChanged: (_) {},
        onGroupingModeChanged: onGroupingModeChanged ?? (_) {},
        onChunkDisplayStyleChanged: (_) {},
        onHighlightCurrentChunkChanged: (_) {},
        onChunkHighlightStyleChanged: (_) {},
        onWordHighlightStyleChanged: (_) {},
        onWordAnimationIntensityChanged: (_) {},
        onRuleHintsLevelChanged: (_) {},
        onPhonemeRibbonVisibleChanged: (_) {},
        onSoundPatternRibbonVisibleChanged: (_) {},
        onSoundPatternDisplayModeChanged: (_) {},
        onPhonemeRibbonStyleChanged: (_) {},
        onPhoneticAnalysisPreferenceChanged: (_) {},
        onSave:
            ({
              required ffmpegPath,
              required ffprobePath,
              required ytDlpPath,
              required openSubtitlesApiKey,
            }) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mirrors the composition root: the appearance choice lives above the
/// `MaterialApp`, so picking one rebuilds the whole app — and the open dialog
/// with it. Reproduces #12/#13 field report: that rebuild used to throw
/// `LateInitializationError` from the dialog's `didUpdateWidget`.
class _LiveSettingsHost extends StatefulWidget {
  const _LiveSettingsHost({super.key, required this.builder});

  final Widget Function(String themeMode, ValueChanged<String> onChanged)
  builder;

  @override
  State<_LiveSettingsHost> createState() => _LiveSettingsHostState();
}

class _LiveSettingsHostState extends State<_LiveSettingsHost> {
  String _themeMode = 'system';

  void setThemeMode(String value) => setState(() => _themeMode = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    themeMode: themeModeFromSetting(_themeMode),
    home: Scaffold(
      body: widget.builder(
        _themeMode,
        (value) => setState(() => _themeMode = value),
      ),
    ),
  );
}
