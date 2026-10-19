import 'package:flutter/painting.dart';

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

/// Container padding — the inset between a surface's edge and its content.
///
/// [ListenSpacing] and this class answer two different questions, and treating
/// them as one is exactly how the drift happened. A gap says *how far apart
/// two siblings sit*; padding says *how much air a container keeps inside its
/// own border*. Because padding also has to absorb the border, the shadow and
/// the hit area, it does not want the gap ladder's fine 2pt bottom end — and
/// once every call site started composing its own `EdgeInsets` out of gap-like
/// numbers, 10, 14, 18 and 20 spread across 143 of the app's 340 `EdgeInsets`
/// and no two panels inset alike.
///
/// So padding is not a scale of numbers to pick from; it is five named
/// container roles, each a whole `EdgeInsets`:
///
///     tight · row · card · pageCompact · page
///
/// Pick by what the container *is*, not by which number looks close. Off-scale
/// insets migrate the same way: 4/5 → [tight], 8/10 → [row], 14/16/18 →
/// [card], 20/22/24/28 → [pageCompact], 32+ → [page].
///
/// The horizontal step is wider than the vertical one at the dense end
/// because this is a desktop tool: rows are short and numerous, so vertical
/// padding is the scarce budget while horizontal padding is what keeps text
/// off the border.
///
/// Scope: the padding of a **container**. A one-off asymmetric inset that
/// exists to align with a specific neighbour (nudging a label under an icon
/// column) is geometry, not a container role, and stays a literal.
///
/// The standing example is `lib/widgets/subtitle/` — the instruments drawn over
/// the video. Their insets are functions of the *rendered subtitle size*, which
/// the user sets and the video frame scales, so they are measured in units of
/// the glyph beside them rather than in steps of a fixed grid: the same 4pt
/// that hangs a bracket on an 11px cue detaches it from a 34px one. Snapping
/// them to this ladder would not tidy a rhythm, it would break the coupling
/// that makes each mark read as part of the word it annotates. They are named
/// as `static const`/helpers on the widget that owns them — the way
/// `capability_viz.dart` already names its baseline hairline — because a ratio
/// one instrument uses is element geometry, and a theme class of single-use
/// numbers would be a vocabulary nobody picks from. On-ladder values in those
/// files still use these names; only the derived ones are local.
abstract final class ListenPadding {
  /// Inside a dense control: chips, badges, inline buttons, table cells —
  /// anything whose own height is the constraint.
  static const tight = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  /// One row of a list or panel: the repeating unit a user scans down.
  static const row = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// A card, dialog body or grouped container — a surface that reads as its
  /// own object. Symmetric on purpose: a card with unequal insets looks
  /// misprinted.
  static const card = EdgeInsets.all(16);

  /// A full page or sheet at a narrow window, where [page] would eat too much
  /// of the content column.
  static const pageCompact = EdgeInsets.symmetric(horizontal: 24, vertical: 24);

  /// A full page or sheet at a comfortable window: the outermost breathing
  /// room, matching [ListenSpacing.gap32].
  static const page = EdgeInsets.symmetric(horizontal: 32, vertical: 32);
}
