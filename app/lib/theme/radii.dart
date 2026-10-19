import 'package:flutter/painting.dart';

/// Corner radii (#26 / #32).
///
/// Before this scale existed, `*.circular()` used 13 different values (2–20
/// plus 999); `listen_theme.dart` alone mixed 7 (buttons/inputs/menus) with 8
/// (cards/dialogs), and widgets added 5, 6, 10, 11… so corners on one screen
/// visibly disagreed. Four tiers plus the capsule now cover every shape:
///
///     tight 4 · control 8 · surface 12 · panel 16 · pill
///
/// Off-scale values were merged to the tier that matches the element's role,
/// not just the nearest number (2/3/5→tight, 6/7/10→control, 11→surface,
/// 20→panel).
abstract final class ListenRadii {
  /// Inline accents: chips, tags, thin indicator bars.
  static const tight = Radius.circular(4);

  /// Interactive controls: buttons, inputs, menu items. This is the tier that
  /// ends the theme's old 7-vs-8 split — controls and their menus share it.
  static const control = Radius.circular(8);

  /// Content surfaces: cards, dialogs, popovers.
  static const surface = Radius.circular(12);

  /// Large hosting surfaces: sheets, media panels.
  static const panel = Radius.circular(16);

  /// Fully rounded capsules (badges, pills). Oversized on purpose so the
  /// radius clamps to half the element's height at any size.
  static const pill = Radius.circular(999);

  static const tightBorder = BorderRadius.all(tight);
  static const controlBorder = BorderRadius.all(control);
  static const surfaceBorder = BorderRadius.all(surface);
  static const panelBorder = BorderRadius.all(panel);
  static const pillBorder = BorderRadius.all(pill);
}
