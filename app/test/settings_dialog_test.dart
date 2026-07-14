import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
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
}

Future<void> _pumpSettingsDialog(
  WidgetTester tester, {
  required bool senseGroupsAvailable,
  required String groupingMode,
  ValueChanged<String>? onGroupingModeChanged,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsDialog(
          language: 'en',
          subtitlePreset: 'learning',
          primaryFontSize: 24,
          primaryFontFamily: 'system',
          secondaryFontSize: 18,
          secondaryFontFamily: 'system',
          subtitlePositionX: 0.5,
          subtitlePositionY: 0.8,
          subtitleBackgroundOpacity: 0.5,
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
    ),
  );
  await tester.pumpAndSettle();
}
