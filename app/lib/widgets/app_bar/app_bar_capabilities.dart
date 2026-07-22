/// Which AppBar actions are currently meaningful, decided once at the
/// composition root instead of inside each menu item. The AppBar is the only
/// entry surface that stays mounted once media loads, so an item's
/// availability must be visible the moment the menu opens — "click and get
/// told no" is not an option (#24). The native macOS menu bar (#23) must
/// derive its enabled states from this same object rather than growing a
/// second definition.
class AppBarCapabilities {
  const AppBarCapabilities({required this.hasMedia, required this.coreReady});

  /// Availability used by widget tests and as an explicit "everything goes"
  /// marker; the composition root always computes the real values.
  const AppBarCapabilities.available() : hasMedia = true, coreReady = true;

  /// Whether a media session is loaded (`playerController.mediaId != null`).
  final bool hasMedia;

  /// Whether the local core API is connected (`api != null`).
  final bool coreReady;

  /// Subtitle import/generate/search and archiving all act on the loaded
  /// media through the local core, so they need both.
  bool get canActOnMedia => hasMedia && coreReady;
}
