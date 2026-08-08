// Models for the media aggregation discovery flow.

/// Acquisition state of an entry's media.
///
/// [failed] exists because the alternative was to drop a failed download back
/// to [none]: the progress bar vanished, the button said "download" again, and
/// nothing said why. A failure the learner can see and retry is a state, not
/// the absence of one.
enum DownloadState { none, downloading, done, failed }

enum MediaSourceType { youtube, podcast }

/// How this entry's bytes may be obtained, if at all.
///
/// Discovery, playback and acquisition are separate capabilities: listing an
/// entry says nothing about whether the app is entitled or able to fetch it.
/// Keeping the answer on the entry means the surface can say which one it is
/// instead of showing a download button that turns out to be a dead end.
enum MediaAcquisition {
  /// The publisher put a media URL in the feed for clients to fetch. Podcast
  /// enclosures; plain HTTP, no extractor.
  enclosure,

  /// Acquisition goes through a user-provided external tool, on the user's own
  /// responsibility. The YouTube path.
  externalTool,

  /// Nothing to acquire — a feed item with no enclosure, a listing-only entry.
  none,
}

/// Whether an entry's media carries a picture. Podcast enclosures are usually
/// audio; the generator needs to be told which, rather than assuming video
/// because the first source the app ever had was YouTube.
enum MediaKind { audio, video }

/// Whether this discovery entry's media is known to exist on this machine.
///
/// This answers exactly one question — "do we have the bytes to open?" — and
/// nothing else. Whether the media has a learning transcript is Workbench's
/// fact, never Discovery's: a local entry with no transcript is still local
/// and still learnable, and only Workbench decides how to make it ready.
enum DiscoveryMediaAvailability {
  /// Nothing has been checked yet.
  unknown,

  /// A local-media lookup is in flight.
  checking,

  /// Checked: the media is not registered with the local library.
  ///
  /// Remote is not the same as "cannot acquire": whether this entry's bytes
  /// can be fetched is the entry's own [MediaAcquisition] fact.
  remote,

  /// Checked: the media exists locally and can be opened.
  local,

  /// The lookup could not run or failed — core disconnected, library query
  /// error — so the answer is still missing. Distinct from [remote]: claiming
  /// "not on this machine" when the library never answered would be a guess.
  undetermined,
}

/// Cover artwork is a tone from the active color scheme.
enum ChannelCoverTone { green, amber, blue, slate, rose }

class MediaSource {
  const MediaSource({
    required this.id,
    required this.name,
    required this.language,
    required this.description,
    required this.cover,
    required this.type,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String language;
  final String description;
  final ChannelCoverTone cover;
  final MediaSourceType type;
  final String? avatarUrl;
}

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.description,
    required this.durationMs,
    required this.language,
    required this.publishedOn,
    required this.thumbnailUrl,
    required this.viewCount,
    this.acquisition = MediaAcquisition.none,
    this.mediaKind = MediaKind.video,
    this.mediaUrl,
    this.mediaByteLength,
    this.localPath,
  });

  final String id;
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
  final String publishedOn;
  final String? thumbnailUrl;
  final int viewCount;

  final MediaAcquisition acquisition;
  final MediaKind mediaKind;

  /// Where the bytes come from, read according to [acquisition]: an enclosure
  /// URL to fetch directly, or a page URL to hand to an external tool.
  final String? mediaUrl;

  /// The size the source advertised, when it did. Advisory only — it is used
  /// to show progress when the response omits `Content-Length`, never as
  /// evidence about the bytes that actually arrived.
  final int? mediaByteLength;

  final String? localPath;
}
