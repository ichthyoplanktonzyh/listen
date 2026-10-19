import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/main.dart';
import 'package:llplayer_next/settings.dart';

// Regression tests for the `_saveSettings` merge path. It once rebuilt a
// fresh `AppSettings(...)` from defaults, so every field not enumerated in
// the constructor call (theme mode, resume state, pronunciation prefs, …)
// was silently reset on every save — e.g. adjusting the volume under the
// light theme wrote `theme_mode: dark` back to disk.
void main() {
  test('mergeLiveSettings reads playback and subtitle state from the live '
      'controllers', () {
    final player = PlayerController();
    addTearDown(player.dispose);
    final subtitles = SubtitleController();
    addTearDown(subtitles.dispose);
    player
      ..setRate(1.5)
      ..setVolume(37);
    subtitles
      ..setPrimarySubtitleOffset(const Duration(milliseconds: -150))
      ..setVisible(false)
      ..setPrimaryFontSize(1.4)
      ..setPreset('compact');

    final merged = mergeLiveSettings(
      current: const AppSettings(),
      player: player,
      subtitles: subtitles,
    );

    expect(merged.rate, 1.5);
    expect(merged.volume, 37);
    expect(merged.primarySubtitleOffsetMs, -150);
    expect(merged.subtitlesVisible, isFalse);
    expect(merged.primaryFontSize, 1.4);
    expect(merged.subtitlePreset, 'compact');
  });

  test('mergeLiveSettings preserves every field the live controllers do not '
      'own', () {
    // Non-default values for exactly the fields the old from-scratch
    // construction silently reset to defaults.
    final current = const AppSettings().copyWith(
      themeMode: 'light',
      lastMediaPath: '/media/ep1.mkv',
      lastMediaTitle: 'Episode 1',
      lastMediaPositionMs: 61234,
      lastMediaDurationMs: 240000,
      lastMediaSubtitleCount: 2,
      pronunciationVisible: false,
      phonemeDisplay: 'arpabet',
      precomputePronunciation: false,
      showExperimentalPhoneticResults: true,
      phonemeHighlightVisible: false,
      phoneticCachePolicy: 'keep_all',
      familiarMaterialSuggestions: false,
      // Settings-owned fields the old code re-read through controller
      // getters; after the copyWith rewrite they simply ride along.
      language: 'zh',
      ffmpegPath: '/opt/homebrew/bin/ffmpeg',
      openSubtitlesApiKey: 'secret-key',
      groupingMode: 'semantic',
      learningLanguage: 'ja',
    );
    final player = PlayerController();
    addTearDown(player.dispose);
    final subtitles = SubtitleController();
    addTearDown(subtitles.dispose);
    player.setVolume(80); // The save trigger: a plain volume tweak.

    final merged = mergeLiveSettings(
      current: current,
      player: player,
      subtitles: subtitles,
    );

    expect(merged.volume, 80);
    // Every field below was lost before the copyWith rewrite.
    expect(merged.themeMode, 'light');
    expect(merged.lastMediaPath, '/media/ep1.mkv');
    expect(merged.lastMediaTitle, 'Episode 1');
    expect(merged.lastMediaPositionMs, 61234);
    expect(merged.lastMediaDurationMs, 240000);
    expect(merged.lastMediaSubtitleCount, 2);
    expect(merged.pronunciationVisible, isFalse);
    expect(merged.phonemeDisplay, 'arpabet');
    expect(merged.precomputePronunciation, isFalse);
    expect(merged.showExperimentalPhoneticResults, isTrue);
    expect(merged.phonemeHighlightVisible, isFalse);
    expect(merged.phoneticCachePolicy, 'keep_all');
    expect(merged.familiarMaterialSuggestions, isFalse);
    // Settings-owned fields keep their values without re-enumeration.
    expect(merged.language, 'zh');
    expect(merged.ffmpegPath, '/opt/homebrew/bin/ffmpeg');
    expect(merged.openSubtitlesApiKey, 'secret-key');
    expect(merged.groupingMode, 'semantic');
    expect(merged.learningLanguage, 'ja');
  });
}
