import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/settings.dart';

void main() {
  test(
    'resolveLearningLanguage prefers explicit setting, else track, else en',
    () {
      final controller = SettingsController();
      addTearDown(controller.dispose);
      // Default learningLanguage is 'auto' -> resolves to the track language,
      // falling back to English when the track has none.
      expect(controller.resolveLearningLanguage('fr'), 'fr');
      expect(controller.resolveLearningLanguage(null), 'en');
      // An explicit setting wins over the track language.
      controller.setSettings(
        controller.settings.copyWith(learningLanguage: 'ja'),
      );
      expect(controller.resolveLearningLanguage('fr'), 'ja');
    },
  );

  test('defaults theme mode to dark (design charter: 暗色为家)', () {
    // Fresh installs open into the dimmed room — see
    // design-notes/listen-design-charter.md and #29.
    expect(const AppSettings().themeMode, 'dark');
    // A saved file without theme_mode (never persisted one) also gets dark.
    final settings = AppSettings.fromJson({'version': 8});
    expect(settings.themeMode, 'dark');
  });

  test('preserves an explicitly persisted theme mode choice', () {
    // Users who explicitly chose system/light must never be flipped by the
    // dark-by-default change (#29 persistence boundary).
    expect(
      AppSettings.fromJson({'version': 8, 'theme_mode': 'system'}).themeMode,
      'system',
    );
    expect(
      AppSettings.fromJson({'version': 8, 'theme_mode': 'light'}).themeMode,
      'light',
    );
  });

  test('loads versioned settings values', () {
    final settings = AppSettings.fromJson({
      'version': 2,
      'rate': 0.75,
      'volume': 50,
      'primary_subtitle_offset_ms': -200,
      'secondary_subtitle_offset_ms': 350,
      'subtitles_visible': false,
      'secondary_subtitles_visible': false,
      'status_styles_visible': false,
      'primary_font_size': 31,
      'transcript_width': 510,
      'language': 'zh',
      'subtitle_preset': 'compact',
      'transcription_quality': 'accurate',
      'transcription_language': 'en',
      'transcription_destination': 'secondary',
    });
    expect(settings.rate, 0.75);
    expect(settings.volume, 50);
    expect(settings.primarySubtitleOffsetMs, -200);
    expect(settings.secondarySubtitleOffsetMs, 350);
    expect(settings.subtitlesVisible, isFalse);
    expect(settings.secondarySubtitlesVisible, isFalse);
    expect(settings.primaryFontSize, closeTo(31 / 24, 0.001));
    expect(settings.transcriptWidth, 510);
    expect(settings.language, 'zh');
    expect(settings.subtitlePreset, 'compact');
    expect(settings.transcriptionQuality, 'accurate');
    expect(settings.transcriptionLanguage, 'en');
    expect(settings.transcriptionDestination, 'secondary');
  });

  test('migrates version 1 subtitle offset', () {
    final settings = AppSettings.fromJson({
      'version': 1,
      'subtitle_offset_ms': -125,
    });
    expect(settings.version, 8);
    expect(settings.primarySubtitleOffsetMs, -125);
  });

  test('migrates version 3 subtitle placement and supports v4 fonts', () {
    final migrated = AppSettings.fromJson({
      'version': 3,
      'subtitle_bottom_padding': 60,
    });
    expect(migrated.subtitlePositionX, 0.5);
    expect(migrated.subtitlePositionY, 0.9);

    final current = AppSettings.fromJson({
      'version': 4,
      'primary_font_size': 1.8,
      'secondary_font_size': 0.6,
      'primary_font_family': 'serif',
      'secondary_font_family': 'monospace',
      'subtitle_position_x': 0.2,
      'subtitle_position_y': 0.3,
    });
    expect(current.primaryFontSize, 1.8);
    expect(current.secondaryFontSize, 0.6);
    expect(current.primaryFontFamily, 'serif');
    expect(current.secondaryFontFamily, 'monospace');
    expect(current.subtitlePositionX, 0.2);
    expect(current.subtitlePositionY, 0.3);
  });

  test('falls back safely for an unsupported settings version', () {
    final settings = AppSettings.fromJson({'version': 999, 'rate': 4});
    expect(settings.version, 8);
    expect(settings.rate, 1);
  });

  test('migrates v7 chunk animation to static capsules', () {
    final settings = AppSettings.fromJson({
      'version': 7,
      'pronunciation_visible': false,
      'word_sync_visible': false,
      'show_chunk_grouping': false,
      'highlight_current_chunk': true,
      'phoneme_display': 'arpabet',
      'word_highlight_style': 'glow',
      'word_animation_intensity': 0.8,
      'rule_hints_level': 'all',
      'precompute_pronunciation': false,
    });
    expect(settings.pronunciationVisible, isFalse);
    expect(settings.wordSyncVisible, isFalse);
    // Legacy chunk grouping explicitly off, no sense grouping -> unified off.
    expect(settings.groupingMode, 'off');
    expect(settings.chunkDisplayStyle, 'capsule');
    expect(settings.highlightCurrentChunk, isFalse);
    expect(settings.chunkHighlightStyle, 'background');
    expect(settings.phonemeDisplay, 'arpabet');
    expect(settings.wordHighlightStyle, 'glow');
    expect(settings.wordAnimationIntensity, 0.8);
    expect(settings.ruleHintsLevel, 'all');
    expect(settings.precomputePronunciation, isFalse);
  });

  test('migrates v7 settings with conservative phonetic analysis defaults', () {
    final settings = AppSettings.fromJson({
      'version': 7,
      'pronunciation_visible': false,
    });

    expect(settings.version, 8);
    expect(settings.pronunciationVisible, isFalse);
    expect(settings.phoneticProviderId, isEmpty);
    expect(settings.phoneticModelId, isEmpty);
    expect(settings.phoneticAnalysisPreference, 'on_demand');
    expect(settings.showExperimentalPhoneticResults, isFalse);
    expect(settings.phonemeHighlightVisible, isTrue);
    expect(settings.soundPatternRibbonVisible, isFalse);
    expect(settings.phoneticCachePolicy, 'keep_completed');
  });

  test('copyWith preserves and updates pronunciation settings', () {
    const settings = AppSettings(
      pronunciationVisible: false,
      wordSyncVisible: false,
      groupingMode: 'off',
      chunkDisplayStyle: 'spacing',
      highlightCurrentChunk: false,
      chunkHighlightStyle: 'glow',
      phonemeDisplay: 'arpabet',
      wordHighlightStyle: 'bounce',
      wordAnimationIntensity: 0.8,
      ruleHintsLevel: 'all',
      precomputePronunciation: false,
      soundPatternRibbonVisible: false,
    );

    final updated = settings.copyWith(
      wordSyncVisible: true,
      soundPatternRibbonVisible: true,
    );

    expect(updated.pronunciationVisible, isFalse);
    expect(updated.wordSyncVisible, isTrue);
    expect(updated.groupingMode, 'off');
    expect(updated.chunkDisplayStyle, 'spacing');
    expect(updated.highlightCurrentChunk, isFalse);
    expect(updated.chunkHighlightStyle, 'glow');
    expect(updated.phonemeDisplay, 'arpabet');
    expect(updated.wordHighlightStyle, 'bounce');
    expect(updated.wordAnimationIntensity, 0.8);
    expect(updated.ruleHintsLevel, 'all');
    expect(updated.precomputePronunciation, isFalse);
    expect(updated.soundPatternRibbonVisible, isTrue);
  });

  test('falls back from an unsupported word highlight style', () {
    final settings = AppSettings.fromJson({
      'version': 7,
      'word_highlight_style': 'underline',
    });

    expect(settings.wordHighlightStyle, 'background');
  });

  test('loads independently configured chunk presentation settings v8', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'chunk_display_style': 'spacing',
      'highlight_current_chunk': true,
      'chunk_highlight_style': 'bounce',
    });

    expect(settings.chunkDisplayStyle, 'spacing');
    expect(settings.highlightCurrentChunk, isTrue);
    expect(settings.chunkHighlightStyle, 'bounce');
  });

  test('migrates legacy chunk grouping toggle to prosodic mode', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'show_chunk_grouping': true,
    });

    expect(settings.groupingMode, 'prosodic');
    expect(settings.chunkHighlightActive, isFalse);
  });

  test('legacy sense grouping wins over chunk grouping on migration', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'show_chunk_grouping': true,
      'show_sense_grouping': true,
    });

    expect(settings.groupingMode, 'semantic');
  });

  test('legacy files with no grouping flags keep prosodic default', () {
    final settings = AppSettings.fromJson({'version': 8});

    expect(settings.groupingMode, 'prosodic');
  });

  test('explicit grouping mode is honored and drives chunk highlight', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'grouping_mode': 'compare',
      'highlight_current_chunk': true,
    });

    expect(settings.groupingMode, 'compare');
    // Compare keeps the prosodic base, so the live current-group highlight
    // still tracks chunks.
    expect(settings.chunkHighlightActive, isTrue);
  });

  test('unknown grouping mode falls back through legacy toggles', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'grouping_mode': 'bogus',
      'show_sense_grouping': true,
    });

    expect(settings.groupingMode, 'semantic');
  });

  test('semantic mode does not enable chunk-based current highlight', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'grouping_mode': 'semantic',
      'highlight_current_chunk': true,
    });

    expect(settings.chunkHighlightActive, isFalse);
  });

  test('fresh default settings start with grouping off', () {
    expect(const AppSettings().groupingMode, 'off');
  });

  test('loads workbench media split v8 with safe bounds', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'workbench_media_fraction': 0.58,
    });
    final clamped = AppSettings.fromJson({
      'version': 8,
      'workbench_media_fraction': 0.9,
    });

    expect(settings.workbenchMediaFraction, 0.58);
    expect(clamped.workbenchMediaFraction, 0.62);
    expect(
      settings.copyWith(workbenchMediaFraction: 0.36).workbenchMediaFraction,
      0.36,
    );
  });

  test('loads independent sound pattern ribbon visibility v8', () {
    final settings = AppSettings.fromJson({
      'version': 8,
      'phoneme_ribbon_visible': false,
      'sound_pattern_ribbon_visible': true,
      'sound_pattern_display_mode': 'phones',
    });

    expect(settings.phonemeRibbonVisible, isFalse);
    expect(settings.soundPatternRibbonVisible, isTrue);
    expect(settings.soundPatternDisplayMode, 'actual');
  });

  test('defaults Rhythm reference to actual and validates A/B/C modes', () {
    final defaults = AppSettings.fromJson({
      'version': 8,
      'sound_pattern_display_mode': 'unexpected',
    });
    final connected = defaults.copyWith(soundPatternDisplayMode: 'connected');

    expect(defaults.soundPatternDisplayMode, 'actual');
    expect(connected.soundPatternDisplayMode, 'connected');
  });
}
