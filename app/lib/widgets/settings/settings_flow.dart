import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/provider_settings_view_models.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../theme/listen_theme.dart';
import 'settings_dialog.dart';

/// Opens the app settings dialog and applies each change to the owning
/// controllers. Pure wiring extracted from the composition root; parameter
/// names intentionally mirror the host's controller fields so the dialog
/// callbacks read identically at both sites.
Future<void> showAppSettings({
  required BuildContext context,
  required SettingsController settingsController,
  required SubtitleController subtitleController,
  required PlayerController playerController,
  required LearningController learningController,
  required Future<void> Function() saveSettings,
  LearnerSettingsViewModel? learnerViewModel,
  LlmProviderSettingsViewModel? llmViewModel,
  RealtimeProviderSettingsViewModel? realtimeViewModel,
  SyntaxCapabilitySettingsViewModel? syntaxViewModel,
}) async {
  // The L1 setting is a backend asset (Phase 3.9), not a local file setting.
  // Best-effort read: with no sidecar the field shows unset and stays inert.
  await learnerViewModel?.load();
  final l1Language = learnerViewModel?.state.l1Language ?? '';
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(
      llmViewModel: llmViewModel,
      realtimeViewModel: realtimeViewModel,
      syntaxViewModel: syntaxViewModel,
      language: settingsController.language,
      themeMode: settingsController.themeMode,
      subtitlePreset: subtitleController.preset,
      primaryFontSize: subtitleController.primaryFontSize,
      primaryFontFamily: subtitleController.primaryFontFamily,
      secondaryFontSize: subtitleController.secondaryFontSize,
      secondaryFontFamily: subtitleController.secondaryFontFamily,
      subtitlePositionX: subtitleController.positionX,
      subtitlePositionY: subtitleController.positionY,
      subtitleBackgroundOpacity: subtitleController.backgroundOpacity,
      transcriptWidth: settingsController.transcriptWidth,
      primaryColor: settingsController.primaryColor,
      secondaryColor: settingsController.secondaryColor,
      transcriptionQuality: settingsController.transcriptionQuality,
      transcriptionLanguage: settingsController.transcriptionLanguage,
      transcriptionDestination: settingsController.transcriptionDestination,
      ffmpegPath: settingsController.ffmpegPath,
      ffprobePath: settingsController.ffprobePath,
      ytDlpPath: settingsController.ytDlpPath,
      openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
      wordSyncVisible: settingsController.wordSyncVisible,
      markKeysEnabled: settingsController.markKeysEnabled,
      groupingMode: settingsController.groupingMode,
      senseGroupsAvailable: subtitleController.senseGroupsBySentence.isNotEmpty,
      chunkDisplayStyle: settingsController.chunkDisplayStyle,
      highlightCurrentChunk: settingsController.highlightCurrentChunk,
      chunkHighlightStyle: settingsController.chunkHighlightStyle,
      wordHighlightStyle: settingsController.wordHighlightStyle,
      wordAnimationIntensity: settingsController.wordAnimationIntensity,
      ruleHintsLevel: settingsController.ruleHintsLevel,
      phoneticAnalysisPreference: settingsController.phoneticAnalysisPreference,
      phonemeRibbonVisible: settingsController.phonemeRibbonVisible,
      soundPatternRibbonVisible: settingsController.soundPatternRibbonVisible,
      soundPatternDisplayMode: settingsController.soundPatternDisplayMode,
      phonemeRibbonStyle: settingsController.phonemeRibbonStyle,
      learningLanguage: settingsController.learningLanguage,
      availableLanguages: learningController.availableLanguages,
      l1Language: l1Language,
      onL1LanguageChanged: (v) {
        if (learnerViewModel == null) return;
        unawaited(
          learnerViewModel.updateL1Language(
            v,
            uiLanguage: settingsController.language,
          ),
        );
      },
      onLearningLanguageChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(learningLanguage: v),
        );
      },
      onLanguageChanged: (v) {
        appLanguage.value = v;
        settingsController.update(
          settingsController.settings.copyWith(language: v),
        );
      },
      onThemeModeChanged: (v) {
        appThemeMode.value = themeModeFromSetting(v);
        settingsController.update(
          settingsController.settings.copyWith(themeMode: v),
        );
      },
      onSubtitlePresetChanged: (v) {
        subtitleController.setPreset(v);
        unawaited(saveSettings());
      },
      onPrimaryFontSizeChanged: (v) {
        subtitleController.setPrimaryFontSize(v);
        unawaited(saveSettings());
      },
      onPrimaryFontFamilyChanged: (v) {
        subtitleController.setPrimaryFontFamily(v);
        unawaited(saveSettings());
      },
      onSecondaryFontSizeChanged: (v) {
        subtitleController.setSecondaryFontSize(v);
        unawaited(saveSettings());
      },
      onSecondaryFontFamilyChanged: (v) {
        subtitleController.setSecondaryFontFamily(v);
        unawaited(saveSettings());
      },
      onSubtitlePositionXChanged: (v) {
        subtitleController.setPositionX(v);
        unawaited(saveSettings());
      },
      onSubtitlePositionYChanged: (v) {
        subtitleController.setPositionY(v);
        unawaited(saveSettings());
      },
      onSubtitlePositionReset: () {
        subtitleController.setPositionX(0.5);
        subtitleController.setPositionY(0.82);
        unawaited(saveSettings());
      },
      onBackgroundOpacityChanged: (v) {
        subtitleController.setBackgroundOpacity(v);
        unawaited(saveSettings());
      },
      onTranscriptWidthChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(transcriptWidth: v),
        );
      },
      onPrimaryColorChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(primaryColor: v.toARGB32()),
        );
      },
      onSecondaryColorChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(secondaryColor: v.toARGB32()),
        );
      },
      onTranscriptionQualityChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(transcriptionQuality: v),
        );
      },
      onTranscriptionLanguageChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(transcriptionLanguage: v),
        );
      },
      onTranscriptionDestinationChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(transcriptionDestination: v),
        );
      },
      onMarkKeysEnabledChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(markKeysEnabled: v),
        );
      },
      onWordSyncVisibleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(wordSyncVisible: v),
        );
        subtitleController.updateCurrentWord(
          playerController.position,
          enabled: v,
          chunkEnabled: settingsController.chunkHighlightActive,
        );
      },
      onGroupingModeChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(groupingMode: v),
        );
        subtitleController.updateCurrentWord(
          playerController.position,
          enabled: settingsController.wordSyncVisible,
          chunkEnabled: settingsController.chunkHighlightActive,
        );
      },
      onChunkDisplayStyleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(chunkDisplayStyle: v),
        );
      },
      onHighlightCurrentChunkChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(highlightCurrentChunk: v),
        );
        subtitleController.updateCurrentWord(
          playerController.position,
          enabled: settingsController.wordSyncVisible,
          chunkEnabled: settingsController.chunkHighlightActive,
        );
      },
      onChunkHighlightStyleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(chunkHighlightStyle: v),
        );
      },
      onWordHighlightStyleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(wordHighlightStyle: v),
        );
      },
      onWordAnimationIntensityChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(wordAnimationIntensity: v),
        );
      },
      onRuleHintsLevelChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(ruleHintsLevel: v),
        );
      },
      onPhoneticAnalysisPreferenceChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(phoneticAnalysisPreference: v),
        );
      },
      onPhonemeRibbonStyleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(phonemeRibbonStyle: v),
        );
      },
      onPhonemeRibbonVisibleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(
            phonemeRibbonVisible: v,
            phonemeHighlightVisible:
                v || settingsController.settings.soundPatternRibbonVisible,
          ),
        );
        subtitleController.updateCurrentDetectedPhone(
          playerController.position,
          enabled: v || settingsController.settings.soundPatternRibbonVisible,
        );
      },
      onSoundPatternRibbonVisibleChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(
            soundPatternRibbonVisible: v,
            phonemeHighlightVisible:
                v || settingsController.settings.phonemeRibbonVisible,
          ),
        );
        subtitleController.updateCurrentDetectedPhone(
          playerController.position,
          enabled: v || settingsController.settings.phonemeRibbonVisible,
        );
      },
      onSoundPatternDisplayModeChanged: (v) {
        settingsController.update(
          settingsController.settings.copyWith(soundPatternDisplayMode: v),
        );
      },
      onSave:
          ({
            required String ffmpegPath,
            required String ffprobePath,
            required String ytDlpPath,
            required String openSubtitlesApiKey,
          }) async {
            await settingsController.update(
              settingsController.settings.copyWith(
                ffmpegPath: ffmpegPath,
                ffprobePath: ffprobePath,
                ytDlpPath: ytDlpPath,
                openSubtitlesApiKey: openSubtitlesApiKey,
              ),
            );
          },
    ),
  );
}
