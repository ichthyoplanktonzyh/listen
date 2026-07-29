/// Width thresholds used by `LayoutBuilder` sites to switch layout shape.
///
/// Only thresholds compared against `constraints.maxWidth` belong here — fixed
/// `width:` / `SizedBox` sizes are element geometry, not breakpoints.
///
/// The one deliberate exception is the `*ColumnMax` block at the bottom:
/// content-column caps (`ConstrainedBox(maxWidth:)`) that keep a reading or
/// card column from sprawling on a wide window. They are a shared vocabulary,
/// not a layout switch, but owner (#77, 前置决策 1) put them here rather than
/// spawning a new file, since a column's cap and the breakpoint that folds it
/// are the same "how wide should content be" concern. The五页 that each
/// hard-coded their own width (audit C4) migrate to these as they are rebuilt.
///
/// Values that happen to coincide are kept as separate constants when the
/// reason for the threshold differs: each one is derived from what its own
/// widget needs to stay usable, so they are free to drift apart. Only merge two
/// constants when the underlying reason is genuinely the same.
abstract final class ListenBreakpoints {
  /// Smallest window the layouts are supported at, enforced by the platform
  /// shell (`macos/Runner/MainFlutterWindow.swift` sets `contentMinSize` from
  /// these; `window_min_size_test.dart` keeps the two sides in step).
  ///
  /// Width: `PlayerAppBar`'s icon-only form has a hard floor of 480px in both
  /// locales — below that it overflows no matter how it degrades, short of
  /// folding all four menus into one popup. 640 keeps real headroom over that
  /// floor and is already the width the compact-home tests treat as the
  /// canonical narrow desktop layout. Every breakpoint below is ≥520, so
  /// nothing between 480 and 640 is a shape anyone designed for.
  ///
  /// Height: `IntensivePracticeWindow` clamps itself to 360–560; at 560 the
  /// window still clears that range once the toolbar is subtracted.
  static const minWindowWidth = 640.0;
  static const minWindowHeight = 560.0;

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

  /// The coach dashboard's capability portrait keeps the compass ring beside
  /// the echo bars; below it the two stack vertically. The compass is a fixed
  /// 200px, so this leaves the bars at least ~380px of column width.
  static const capabilityPortraitSideBySide = 640.0;

  /// Reading surfaces (view header, task studio) drop to their compact
  /// arrangement below this width.
  static const readingCompact = 900.0;

  /// The reading word inspector sits beside the reader; below it the inspector
  /// moves under the reader instead.
  static const readingInspectorSideBySide = 980.0;

  /// The vocabulary workbench (#79 / S3) keeps its list+lens column beside the
  /// activity pane; below it the two collapse to a single column (the narrow
  /// "B" form). Derived from the two panes' floors: the list needs ~320 to show
  /// word rows with their lens, the activity pane ~540 to stay usable, plus the
  /// gutter ≈ 880; 900 leaves a little margin before the fold.
  static const vocabularyTwoPane = 900.0;

  // ── Content column max-widths ──
  // Caps for a centered content column (a `ConstrainedBox(maxWidth:)`), so a
  // single column of text or a card stops growing before line length gets
  // tiring on a wide window (charter principle 5, "降低疲劳"). See the class
  // doc for why these live alongside the layout breakpoints.

  /// A single reading column of text-dense content — word detail, conversation
  /// transcript, coach evidence. Sized to a comfortable measure (~70ch at the
  /// body size) so lines stay legible. Replaces the 780/760 that vocabulary
  /// detail and the conversation panel each hard-coded (audit C4); the 20px
  /// spread between them was incidental — the reason is one.
  static const contentColumnMax = 780.0;

  /// A single centered card — the review card, a page-inline studio card —
  /// which reads narrower than a full text column. Replaces the review card's
  /// hard-coded 680 (audit C4).
  static const cardColumnMax = 680.0;

  /// A dense form or single-column settings list — the conversation lobby, the
  /// provider forms. Narrower than a reading column on purpose: a form row is
  /// not continuous text but a label↔control pair, and once the row gets long
  /// the eye loses which control belongs to which label on the way across.
  static const formColumnMax = 560.0;

  /// Wide content that is two columns or carries media — the home surface, the
  /// media library. Not a reading measure: the cap here only stops the layout
  /// from sprawling once the window is much wider than the content needs.
  static const wideColumnMax = 960.0;
}
