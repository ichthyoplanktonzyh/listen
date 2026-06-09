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
    });
    expect(settings.rate, 0.75);
    expect(settings.volume, 50);
    expect(settings.primarySubtitleOffsetMs, -200);
    expect(settings.secondarySubtitleOffsetMs, 350);
    expect(settings.subtitlesVisible, isFalse);
    expect(settings.secondarySubtitlesVisible, isFalse);
    expect(settings.primaryFontSize, 31);
    expect(settings.transcriptWidth, 510);
  });

  test('migrates version 1 subtitle offset', () {
    final settings = AppSettings.fromJson({
      'version': 1,
      'subtitle_offset_ms': -125,
    });
    expect(settings.version, 2);
    expect(settings.primarySubtitleOffsetMs, -125);
  });

  test('falls back safely for an unsupported settings version', () {
    final settings = AppSettings.fromJson({'version': 999, 'rate': 4});
    expect(settings.version, 2);
    expect(settings.rate, 1);
  });
}
