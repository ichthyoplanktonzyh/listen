import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/settings.dart';

void main() {
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
    expect(settings.version, 7);
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
    expect(settings.version, 7);
    expect(settings.rate, 1);
  });

  test('loads pronunciation and word sync settings v7', () {
    final settings = AppSettings.fromJson({
      'version': 7,
      'pronunciation_visible': false,
      'word_sync_visible': false,
      'phoneme_display': 'arpabet',
      'word_highlight_style': 'glow',
      'word_animation_intensity': 0.8,
      'rule_hints_level': 'all',
      'precompute_pronunciation': false,
    });
    expect(settings.pronunciationVisible, isFalse);
    expect(settings.wordSyncVisible, isFalse);
    expect(settings.phonemeDisplay, 'arpabet');
    expect(settings.wordHighlightStyle, 'glow');
    expect(settings.wordAnimationIntensity, 0.8);
    expect(settings.ruleHintsLevel, 'all');
    expect(settings.precomputePronunciation, isFalse);
  });

  test('copyWith preserves and updates pronunciation settings', () {
    const settings = AppSettings(
      pronunciationVisible: false,
      wordSyncVisible: false,
      phonemeDisplay: 'arpabet',
      wordHighlightStyle: 'bounce',
      wordAnimationIntensity: 0.8,
      ruleHintsLevel: 'all',
      precomputePronunciation: false,
    );

    final updated = settings.copyWith(wordSyncVisible: true);

    expect(updated.pronunciationVisible, isFalse);
    expect(updated.wordSyncVisible, isTrue);
    expect(updated.phonemeDisplay, 'arpabet');
    expect(updated.wordHighlightStyle, 'bounce');
    expect(updated.wordAnimationIntensity, 0.8);
    expect(updated.ruleHintsLevel, 'all');
    expect(updated.precomputePronunciation, isFalse);
  });

  test('falls back from an unsupported word highlight style', () {
    final settings = AppSettings.fromJson({
      'version': 7,
      'word_highlight_style': 'underline',
    });

    expect(settings.wordHighlightStyle, 'background');
  });
}
