/// Width thresholds used by `LayoutBuilder` sites to switch layout shape.
///
/// Only thresholds compared against `constraints.maxWidth` belong here — fixed
/// `width:` / `SizedBox` sizes are element geometry, not breakpoints.
///
/// Values that happen to coincide are kept as separate constants when the
/// reason for the threshold differs: each one is derived from what its own
/// widget needs to stay usable, so they are free to drift apart. Only merge two
/// constants when the underlying reason is genuinely the same.
abstract final class ListenBreakpoints {
  /// [ListeningHome] keeps the navigation sidebar next to the content; below
  /// it, the content pane takes the full width.
  static const homeSidebar = 760.0;

  /// The home status strip lays its tiles out in a row; below it the tiles
  /// stack vertically so each label still fits on one line.
  static const homeStatusStrip = 720.0;

  /// Side-panel tabs show text labels beside their icons; below it only the
  /// icons remain.
  static const sidePanelTabLabels = 520.0;

  /// The media workbench splits media and panel side by side; below it the
  /// split turns vertical.
  static const workbenchStacked = 820.0;

  /// Playback controls keep the transport row on a single line; below it the
  /// row switches to its narrow arrangement.
  static const playbackControlsNarrow = 760.0;

  /// Below this the flat function buttons (extensive listening / chunk /
  /// subtitle menus) collapse into a single overflow popup rather than
  /// disappearing. ~900 keeps the flat toolbar while the function area
  /// (roughly 800px) still fits comfortably.
  static const playbackControlsRoomy = 900.0;

  /// [PlayerAppBar]'s four menu buttons keep their text labels; below it only
  /// the icons remain (the tooltips already carry the same wording, so no
  /// information is lost).
  ///
  /// Derived from the widest locale, not the narrowest: English needs 836px
  /// for `Content / Subtitles / Learning / More actions` plus the settings
  /// icon, while Chinese fits under 700. Sized at 860 for margin, so a longer
  /// translation does not immediately reintroduce the overflow this fixed.
  static const appBarLabels = 860.0;

  /// Reading surfaces (view header, task studio) drop to their compact
  /// arrangement below this width.
  static const readingCompact = 900.0;

  /// The reading word inspector sits beside the reader; below it the inspector
  /// moves under the reader instead.
  static const readingInspectorSideBySide = 980.0;
}
