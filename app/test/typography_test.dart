import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/typography.dart';

/// #26 / #32: the theme's textTheme mirrors the ListenType ladder and pins
/// the bundled Plex families, so `Theme.of(context)` sites and the constants
/// stay one system.
void main() {
  for (final (name, theme) in [
    ('light', ListenTheme.light()),
    ('dark', ListenTheme.dark()),
  ]) {
    group('$name textTheme', () {
      final text = theme.textTheme;

      test('slots carry the ladder sizes', () {
        expect(text.labelSmall?.fontSize, ListenType.caption.fontSize);
        expect(text.bodySmall?.fontSize, ListenType.body.fontSize);
        expect(text.bodyMedium?.fontSize, ListenType.reading.fontSize);
        expect(text.titleMedium?.fontSize, ListenType.title.fontSize);
        expect(text.titleLarge?.fontSize, ListenType.hero.fontSize);
      });

      test('slots render in the bundled family with SC fallback', () {
        expect(text.bodyMedium?.fontFamily, ListenFonts.sans);
        expect(
          text.bodyMedium?.fontFamilyFallback,
          contains(ListenFonts.sansSC),
        );
      });
    });
  }

  test('timecode and IPA styles pin their dedicated families', () {
    expect(ListenType.timecode.fontFamily, ListenFonts.mono);
    expect(ListenType.ipa.fontFamily, ListenFonts.ipa);
  });
}
