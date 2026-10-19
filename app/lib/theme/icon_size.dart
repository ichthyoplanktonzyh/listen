/// Icon sizes (#26 / #32 follow-up).
///
/// Icons are the second set of glyphs in this app: almost every one of them
/// sits on a line next to a label, so an icon's size is really a typographic
/// decision. Before this ladder existed, `Icon(size:)` used 14 different
/// values (13/14/15/16/17/18/20/21/28/34/46/64/68/72) and `iconSize:` another
/// 7, all chosen site by site — so a 15px icon ended up beside 13px text on
/// one row and a 20px icon beside the same 13px text on the next, and the two
/// rows no longer read as one list. Four steps, each pinned to a band of the
/// [ListenType] ladder, cover every icon in the product:
///
///     inline 14 · control 18 · chrome 22 · illustration 48
///
/// The gaps between steps are deliberately wide. Icon weight is perceived
/// coarsely, so 2pt neighbours (14/15/16, 20/21/22) are drift, not design:
/// they cost a decision at every call site and buy nothing the eye can see.
///
/// Off-scale values migrate by the role the icon plays, using the nearest step
/// as the tiebreak: 13/14/15 → [inline]; 16/17/18/20/21 → [control];
/// 22/24/28 → [chrome]; 34/46/64/68/72 → [illustration].
///
/// Scope: this is the size of an **icon glyph** — `Icon(size:)`,
/// `IconButton(iconSize:)`. The tap target around it is not an icon size (an
/// `IconButton` keeps its own 40–48pt hit area regardless of the glyph), and
/// neither is the side of a decorative box, an avatar, or a thumbnail; those
/// are element geometry and stay literals.
abstract final class ListenIconSize {
  /// Inline with the text flow: status dots, three-state rings, the small
  /// marker that sits inside a sentence of caption or body text. Pairs with
  /// 11–12px text ([ListenType.caption], [ListenType.body]).
  static const inline = 14.0;

  /// List rows, chips, secondary actions — the icon that leads a row or
  /// trails a control. Pairs with 12–13px text ([ListenType.body],
  /// [ListenType.reading]). **This is the default**: reach for another step
  /// only when the icon is doing something this one cannot.
  static const control = 18.0;

  /// App chrome: `AppBar` / toolbar primary actions, tab icons, the icons a
  /// user aims at without reading first. Pairs with 14–16px text
  /// ([ListenType.emphasis], [ListenType.title]).
  static const chrome = 22.0;

  /// Explanatory icons in empty states, first-run guidance and large cards —
  /// the only place an icon carries meaning on its own rather than labelling
  /// something. The one permitted "big icon"; anything larger is artwork and
  /// belongs in a widget, not an [Icon].
  static const illustration = 48.0;
}
