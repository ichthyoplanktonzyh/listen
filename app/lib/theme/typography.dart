import 'package:flutter/painting.dart';

/// The bundled font families (#32). Owner-picked super-family: one systematic
/// voice across Latin UI, numbers, Chinese UI, and IPA instead of whatever
/// each machine's system stack happens to serve.
abstract final class ListenFonts {
  /// Latin UI + body/subtitle chrome.
  static const sans = 'IBM Plex Sans';

  /// Timecodes and counters — digits keep one width so they don't jitter.
  static const mono = 'IBM Plex Mono';

  /// Chinese UI, as fallback behind [sans] so mixed 中英 lines share metrics.
  static const sansSC = 'IBM Plex Sans SC';

  /// IPA phonetics (phoneme ribbon / phonetic analysis). Charis SIL is
  /// designed for IPA — full coverage, no glyph-fallback patchwork.
  static const ipa = 'Charis SIL';
}

/// Semantic text styles for app chrome (#26 / #32).
///
/// Before this scale existed, widgets hand-picked 7 `fontSize` literals
/// (10–22) with no hierarchy. This is one modular ladder — dense at the
/// bottom because this is a desktop tool, widening toward titles:
///
///     11 caption · 12 body · 13 reading · 14 emphasis · 16 title · 22 hero
///
/// Line heights follow the charter table: UI labels 1.2–1.4, running text
/// 1.5–1.7, titles 1.1–1.3. Styles carry size/height/weight only — color
/// stays with the theme (`colorScheme`), family with the theme's default
/// ([ListenFonts.sans]) unless a style exists to change it.
///
/// `ListenTheme` mirrors these onto `textTheme` slots (caption→labelSmall,
/// body→bodySmall, reading→bodyMedium, …) so `Theme.of(context)` sites and
/// these constants agree; the constants exist because most chrome sites set
/// a style where no `BuildContext` theme lookup is warranted (const lists,
/// decoration labels).
abstract final class ListenType {
  /// Dense meta: timestamps-as-text, counts, footnotes under controls.
  static const caption = TextStyle(fontSize: 11, height: 1.3);

  /// The workhorse: panel body text, list rows, form labels.
  static const body = TextStyle(fontSize: 12, height: 1.4);

  /// Running text meant to be read (task sheets, explanations) — one step up
  /// with reading-grade line height.
  static const reading = TextStyle(fontSize: 13, height: 1.5);

  /// Emphasized row headers inside a panel.
  static const emphasis = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// Section titles.
  static const title = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  /// The one hero size (home greeting).
  static const hero = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  /// Timecodes / counters: mono so digits keep one width while playing.
  static const timecode = TextStyle(
    fontFamily: ListenFonts.mono,
    fontSize: 12,
    height: 1.3,
  );

  /// IPA runs. Size is set per site (ribbon cells scale with the video), so
  /// this style only pins the family.
  static const ipa = TextStyle(fontFamily: ListenFonts.ipa);
}
