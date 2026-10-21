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

  /// The current revision's media renditions, in revision order. Immutable.
  List<MediaRendition> get mediaRenditions =>
      List.unmodifiable(details.currentRevision.mediaRenditions);

  List<DocumentRendition> get documentRenditions =>
      List.unmodifiable(details.currentRevision.documentRenditions);

  bool get hasDocuments => documentRenditions.isNotEmpty;

  /// A material is openable when it has either a usable media row or a
  /// source document rendition that the document session can resolve.
  bool get canOpen => primaryMedia != null || hasDocuments;

  /// The deterministic primary media: the first usable media rendition in
  /// revision order, resolved to its joined registered-media row. Usable
  /// means the rendition and its joined [MediaItem] are both available.
  /// Null when the material has no usable rendition or its media is unresolved.
  MediaLibraryEntry? get primaryMedia {
    for (final rendition in mediaRenditions) {
      if (rendition.availability != MediaRenditionAvailability.available) {
        continue;
      }
      final mediaId = rendition.mediaId;
      if (mediaId == null) continue;
      for (final entry in mediaEntries) {
        if (entry.media.id == mediaId &&
            entry.media.availability == 'available') {
          return entry;
        }
      }
    }
    return null;
  }

  /// The primary media's path-bearing row, when available.
  MediaItem? get media => primaryMedia?.media;

  /// Explicit user triage facts delegated to the primary media.
  String? get triageIntent => primaryMedia?.triageIntent;

  /// Whether this material offers listening: a usable primary audio media.
  bool get canListen => primaryMedia?.media.kind == 'audio';

  /// Whether this material offers Watch: a usable primary video media.
  bool get canWatch => primaryMedia?.media.kind == 'video';

  /// Whether this material offers Listen or Watch: a usable primary media.
  bool get canListenOrWatch => primaryMedia != null;

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
    for (final rendition in details.currentRevision.mediaRenditions) {
      final mediaId = rendition.mediaId;
      if (mediaId == null) continue;
      if (!seen.add(mediaId)) continue;
      final entry = byMediaId[mediaId];
      if (entry != null) joined.add(entry);
    }
    return List.unmodifiable(joined);
  }
}
