/// Gap sizes for spacer `SizedBox`es (#26 / #32).
///
/// Before this scale existed, `SizedBox(height:/width:)` spacers used 25
/// different values (1–36) chosen site by site; 4/6/8/10/12/14 all coexisted
/// in bulk, so there was no readable rhythm. This ladder keeps a 2pt micro
/// step at the bottom (dense desktop chrome needs it) and widens toward an
/// 8pt grid at the top:
///
///     2 · 4 · 6 · 8 · 12 · 16 · 24 · 32
///
/// Off-scale values were merged to their nearest step, rounding down on ties
/// so no row got taller and overflowed (3→2, 5→4, 7→6, 9/10→8, 14→12,
/// 18/20→16, 22/26/28→24, 36→32).
///
/// Scope: these are **gaps between elements** — a childless `SizedBox` used
/// as whitespace. Fixed element geometry (a 238px mini player, a 160px label
/// column) is not spacing and stays a literal; `spacing_discipline_test.dart`
/// only polices the childless form.
abstract final class ListenSpacing {
  /// Hairline nudge — optical alignment between glyphs/icons, not a real gap.
  static const gap2 = 2.0;

  /// Tightest real gap: icon↔label inside one control.
  static const gap4 = 4.0;

  /// Gap between siblings inside one dense row (chips, inline meta).
  static const gap6 = 6.0;

  /// The base unit: default gap between related controls.
  static const gap8 = 8.0;

  /// Gap between small groups within one block (form rows, list sections).
  static const gap12 = 12.0;

  /// Gap between distinct blocks inside a panel.
  static const gap16 = 16.0;

  /// Gap between panel-level sections.
  static const gap24 = 24.0;

  /// Page-level breathing room (empty states, hero headers).
  static const gap32 = 32.0;
}
