import 'api_failure.dart';

// Models for the content discovery flow.
//
// A discovery surface answers two questions about a source and its items:
// what is here, and can we get the bytes on this machine. It never answers
// "is this learnable" — that is the workbench's fact, decided after the
// material opens.

/// Acquisition state of a discovery item's content.
///
/// [failed] exists because the alternative was to drop a failed download back
/// to [acquirable]: the progress bar vanished, the button said "download"
/// again, and nothing said why. A failure the learner can see and retry is a
/// state, not the absence of one.
enum DiscoveryItemState {
  /// The source lists the item but grants nothing to fetch: a feed item
  /// without an enclosure and without an article link.
  discoverable,

  /// The item's content can be fetched and nothing has been attempted yet.
  acquirable,

  /// An acquisition (or a local-media check) is in flight.
  acquiring,

  /// The bytes are on this machine and can be opened.
  available,

  /// The availability question could not be answered — core disconnected, a
  /// library query failed. Claiming "not on this machine" when the library
  /// never answered would be a guess.
  unavailable,

  /// The last acquisition attempt failed. The typed failure is attached to
  /// the snapshot for the retry surface.
  failed,
}

/// What an in-flight [DiscoveryItemState.acquiring] attempt is doing.
///
/// A download and a local-media check render differently (progress bar versus
/// indeterminate status) even though both are "something is happening".
enum ItemAcquisitionPhase { download, check }

/// The observable state of one item's acquisition, mirrored from the
/// acquisition machinery. Absent means nothing has been attempted: the item
/// is [DiscoveryItemState.acquirable] or [DiscoveryItemState.discoverable]
/// depending on what its source grants.
final class ItemAcquisitionSnapshot {
  const ItemAcquisitionSnapshot(
    this.state, {
    this.phase = ItemAcquisitionPhase.download,
    this.progress,
    this.failure,
  });

  final DiscoveryItemState state;
  final ItemAcquisitionPhase phase;

  /// Download progress, null while no total is known.
  final double? progress;

  /// Why the attempt failed, when [state] is [DiscoveryItemState.failed].
  final ApiFailure? failure;

  static const checking = ItemAcquisitionSnapshot(
    DiscoveryItemState.acquiring,
    phase: ItemAcquisitionPhase.check,
  );

  static const downloading = ItemAcquisitionSnapshot(
    DiscoveryItemState.acquiring,
    phase: ItemAcquisitionPhase.download,
  );

  static const available = ItemAcquisitionSnapshot(
    DiscoveryItemState.available,
  );

  static const failedUnavailable = ItemAcquisitionSnapshot(
    DiscoveryItemState.unavailable,
  );
}

/// The families a content source can belong to.
///
/// The kind decides nothing about acquisition on its own — a podcast feed and
/// a blog feed are both fetched the same way — but it decides what the feed
/// text *means*: enclosures become media, article links become documents.
enum ContentSourceKind { youtube, podcast, document }

/// How this item's content may be obtained, if at all.
///
/// Discovery, playback and acquisition are separate capabilities: listing an
/// item says nothing about whether the app is entitled or able to fetch it.
/// Keeping the answer on the item means the surface can say which one it is
/// instead of showing a download button that turns out to be a dead end.
enum AcquisitionMode {
  /// The publisher put a media URL in the feed for clients to fetch. Podcast
  /// enclosures; plain HTTP, no extractor.
  enclosure,

  /// Acquisition goes through a user-provided external tool, on the user's own
  /// responsibility. The YouTube path.
  externalTool,

  /// The item is a document: an article link the publisher offered. Acquiring
  /// it fetches the page and takes it in as a Document Rendition.
  article,

  /// Nothing to acquire — a feed item with no enclosure and no article link.
  none,
}

/// What the acquired content is.
///
/// Separate from [AcquisitionMode]: a document item has one acquisition mode
/// and one content kind, but the kinds are about what the bytes are, not how
/// they arrived.
enum ItemContentKind { audio, video, article }

/// The typed evidence kinds a discovered item can carry.
///
/// Identity is source-scoped and canonical: the source identity plus the item
/// identity decide which Material a discovered item is. Every other fact —
/// the feed's item id, the entry URL, the enclosure URL, the publisher, the
/// title, the date, the byte fingerprint — is evidence about that identity,
/// never a substitute for it. Two different items with equal bytes are not
/// the same item.
enum SourceItemEvidenceKind {
  feedItemId,
  entryUrl,
  enclosureUrl,
  publisherId,
  title,
  date,
  byteFingerprint,
}

/// One typed evidence field of a discovered item.
///
/// The kind names what the value is, so a URL can never silently stand in for
/// an item id or a title for an identity.
final class SourceItemEvidence {
  const SourceItemEvidence(this.kind, this.value);

  final SourceItemEvidenceKind kind;
  final String value;
}

/// Cover artwork is a tone from the active color scheme.
enum ChannelCoverTone { green, amber, blue, slate, rose }

/// A subscribed or built-in content source: one feed, one identity.
class ContentSource {
  const ContentSource({
    required this.id,
    required this.name,
    required this.language,
    required this.description,
    required this.cover,
    required this.kind,
    this.avatarUrl,
  });

  /// The source-scoped canonical identity: the stable thing to point at —
  /// a feed URL, a channel id. Item identities are scoped to this.
  final String id;

  final String name;
  final String language;
  final String description;
  final ChannelCoverTone cover;
  final ContentSourceKind kind;
  final String? avatarUrl;
}

/// A discovered item of a [ContentSource].
///
/// Every feed-derived field is typed and never substituted for another:
/// [id] is the source-scoped item identity (RSS guid, Atom id), [entryUrl] is
/// the article link the publisher offered, [mediaUrl] is where the bytes come
/// from when there are bytes to fetch. Metadata changes on re-read do not
/// change the identity.
class DiscoveryItem {
  const DiscoveryItem({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.description,
    required this.language,
    required this.publishedOn,
    this.durationMs,
    this.thumbnailUrl,
    this.viewCount = 0,
    this.acquisition = AcquisitionMode.none,
    this.contentKind = ItemContentKind.article,
    this.mediaUrl,
    this.entryUrl,
    this.publisherId,
    this.mediaByteLength,
  });

  /// The source-scoped canonical item identity. Stable across re-reads,
  /// reordering, and metadata changes.
  final String id;

  /// The [ContentSource.id] this item belongs to.
  final String sourceId;

  final String title;
  final String description;

  /// Null when the source never said how long this is.
  ///
  /// It used to be a non-null field that the YouTube feed path filled with a
  /// hardcoded five minutes, which rendered as a duration badge on every card
  /// — a fabricated fact, indistinguishable from a real one. Unknown is a
  /// state the surface has to show.
  final int? durationMs;

  final String language;

  /// `yyyy-MM-dd` in UTC, or empty when the source omits or mangles the date.
  final String publishedOn;

  final String? thumbnailUrl;
  final int viewCount;

  final AcquisitionMode acquisition;
  final ItemContentKind contentKind;

  /// Where the bytes come from, read according to [acquisition]: an enclosure
  /// URL to fetch directly, a page URL to hand to an external tool, or null.
  final String? mediaUrl;

  /// The article link the source offered for a document item. Distinct from
  /// [mediaUrl]: it is evidence about what the item is, not where bytes are.
  final String? entryUrl;

  /// The publisher the feed named, when it did. Evidence, not identity.
  final String? publisherId;

  /// The size the source advertised, when it did. Advisory only — it is used
  /// to show progress when the response omits `Content-Length`, never as
  /// evidence about the bytes that actually arrived.
  final int? mediaByteLength;

  /// The typed evidence fields of this item, in a fixed order.
  ///
  /// [fileSha256] is the byte fingerprint of the acquired file and is only
  /// known after acquisition.
  List<SourceItemEvidence> evidence({String? fileSha256}) => [
    SourceItemEvidence(SourceItemEvidenceKind.feedItemId, id),
    if (entryUrl != null && entryUrl!.isNotEmpty)
      SourceItemEvidence(SourceItemEvidenceKind.entryUrl, entryUrl!),
    if (mediaUrl != null &&
        mediaUrl!.isNotEmpty &&
        acquisition == AcquisitionMode.enclosure)
      SourceItemEvidence(SourceItemEvidenceKind.enclosureUrl, mediaUrl!),
    if (publisherId != null && publisherId!.isNotEmpty)
      SourceItemEvidence(SourceItemEvidenceKind.publisherId, publisherId!),
    if (title.isNotEmpty)
      SourceItemEvidence(SourceItemEvidenceKind.title, title),
    if (publishedOn.isNotEmpty)
      SourceItemEvidence(SourceItemEvidenceKind.date, publishedOn),
    if (fileSha256 != null)
      SourceItemEvidence(SourceItemEvidenceKind.byteFingerprint, fileSha256),
  ];
}
