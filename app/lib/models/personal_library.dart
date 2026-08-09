import 'learning_material.dart';
import 'types.dart';

/// A Personal Library row for a media surface: one retained [MaterialDetails]
/// projected together with the [MediaLibraryEntry] rows whose media ids occur
/// in the material's current revision.
///
/// Pure and immutable. Every collection is wrapped unmodifiable at
/// construction, and every exposed fact is either read off [details] or
/// delegated to the joined [mediaEntries] — never stored as a second copy
/// that could drift out of sync with its source.
class PersonalLibraryEntry {
  PersonalLibraryEntry({
    required this.details,
    required List<MediaLibraryEntry> mediaEntries,
  }) : mediaEntries = _joinMediaEntries(details, mediaEntries);

  /// The underlying learning material with its actual current revision.
  final MaterialDetails details;

  /// The joined registered-media rows, ordered by first appearance of their
  /// media id in the current revision. Rows for media ids absent from the
  /// revision are dropped; immutable.
  final List<MediaLibraryEntry> mediaEntries;

  String get materialId => details.material.id;
  String get currentRevisionId => details.material.currentRevisionId;
  String get title => details.currentRevision.title;
  MaterialShape get shape => details.shape;
  int get updatedAtMs => details.material.updatedAtMs;
  bool get isRetained => details.isRetained;

  /// Document-text assets of the current revision, in revision order.
  /// Immutable.
  List<DocumentTextMaterialAsset> get documentAssets => List.unmodifiable(
    details.currentRevision.assets.whereType<DocumentTextMaterialAsset>(),
  );

  /// The current revision's media renditions, in revision order. Immutable.
  List<MediaRenditionMaterialAsset> get mediaRenditions => List.unmodifiable(
    details.currentRevision.assets.whereType<MediaRenditionMaterialAsset>(),
  );

  /// The deterministic primary media: the first usable media rendition in
  /// revision order, resolved to its joined registered-media row. Usable
  /// means the rendition and its joined [MediaItem] are both available.
  /// Null for text-only materials and for materials whose renditions are all
  /// missing/archived or unresolved.
  MediaLibraryEntry? get primaryMedia {
    for (final rendition in mediaRenditions) {
      if (rendition.availability != MediaRenditionAvailability.available) {
        continue;
      }
      for (final entry in mediaEntries) {
        if (entry.media.id == rendition.mediaId &&
            entry.media.availability == 'available') {
          return entry;
        }
      }
    }
    return null;
  }

  /// The primary media's path-bearing row, or null for a text-only material.
  MediaItem? get media => primaryMedia?.media;

  /// Triage facts delegated to the primary media; null/false without one.
  String? get triageIntent => primaryMedia?.triageIntent;
  bool get familiarMaterial => primaryMedia?.familiarMaterial ?? false;
  bool get isGoldenTarget => primaryMedia?.isGoldenTarget ?? false;
  ContentDifficultyProfile? get fit => primaryMedia?.fit;

  /// A copy of this row with [entry] swapped in for the joined row carrying
  /// the same media id. Returns the same row when no joined row matches.
  PersonalLibraryEntry withMediaEntry(MediaLibraryEntry entry) {
    final index = mediaEntries.indexWhere(
      (item) => item.media.id == entry.media.id,
    );
    if (index < 0) return this;
    return PersonalLibraryEntry(
      details: details,
      mediaEntries: [...mediaEntries]..[index] = entry,
    );
  }

  /// Filters and orders [snapshot] down to the rows whose media ids occur in
  /// the current revision, ordered by first appearance in the revision.
  static List<MediaLibraryEntry> _joinMediaEntries(
    MaterialDetails details,
    List<MediaLibraryEntry> snapshot,
  ) {
    final byMediaId = <String, MediaLibraryEntry>{};
    for (final entry in snapshot) {
      byMediaId[entry.media.id] = entry;
    }
    final joined = <MediaLibraryEntry>[];
    final seen = <String>{};
    for (final asset in details.currentRevision.assets) {
      if (asset is! MediaRenditionMaterialAsset) continue;
      if (!seen.add(asset.mediaId)) continue;
      final entry = byMediaId[asset.mediaId];
      if (entry != null) joined.add(entry);
    }
    return List.unmodifiable(joined);
  }
}
