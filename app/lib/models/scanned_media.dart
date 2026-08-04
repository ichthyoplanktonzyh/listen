/// Typed vocabulary for a media-library folder scan.
///
/// A scan answers one question per file — "is this a learnable media file this
/// library has not seen yet?" — and it answers it in layers, because the cheap
/// layer (path, size, mtime) is the only one allowed to run on every file of
/// every scan. Everything here is transport-free and process-free so the
/// scanner's public boundary stays a value type.
library;

/// Container families the scanner treats as candidates.
///
/// The kind comes from the extension alone, so it is a *container* claim, not a
/// content claim: an `.mp4` with no video stream is still [video] here. Whether
/// the file actually carries audio is decided by the probe, one layer up.
enum ScannedMediaKind { audio, video }

/// Sidecar subtitle formats that can be paired without any preparation work.
enum SidecarSubtitleFormat { srt, vtt, ass }

/// Why a candidate did not become a [ScannedMedia].
///
/// These are reasons, not messages. The scanner produces no user-visible copy;
/// callers map these to localized text.
enum MediaScanSkipReason {
  /// The entry could not be listed or stat'ed: no permission, a broken link, or
  /// a file that vanished between listing and inspection.
  unreadable,

  /// A symbolic link. Skipped rather than followed, so one scan cannot loop
  /// through a cycle or wander outside the library folder.
  symbolicLink,

  /// The probe failed or the container could not be parsed — the usual shape of
  /// a truncated download or a corrupt file.
  probeFailed,

  /// Probed successfully and carries no audio track, so there is nothing to
  /// listen to.
  noAudioTrack,
}

/// How a scan ended.
enum MediaScanStatus {
  completed,

  /// The caller cancelled. Whatever was already emitted stays valid; the rest
  /// of the tree was simply never visited.
  cancelled,

  /// The root folder could not be opened at all — missing, or not permitted.
  rootUnavailable,
}

/// The cheap identity of an already-known file, supplied by the caller.
///
/// Size plus mtime is deliberately weaker than a fingerprint: it is wrong only
/// for an edit that preserves both, and it costs one `stat` instead of reading
/// the file.
class KnownMediaStamp {
  const KnownMediaStamp({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  /// Compared at whole-second resolution: mtime survives a round trip through
  /// storage and through `File.lastModified` only to the second, and a stricter
  /// comparison would report every known file as changed after a restart.
  bool matches({required int sizeBytes, required DateTime modifiedAt}) =>
      this.sizeBytes == sizeBytes &&
      _wholeSeconds(this.modifiedAt) == _wholeSeconds(modifiedAt);

  static int _wholeSeconds(DateTime value) =>
      value.millisecondsSinceEpoch ~/ 1000;
}

/// A subtitle file sitting next to its media file under the same stem.
class SidecarSubtitle {
  const SidecarSubtitle({required this.path, required this.format});

  final String path;
  final SidecarSubtitleFormat format;
}

/// A candidate that survived every layer of the scan.
class ScannedMedia {
  const ScannedMedia({
    required this.path,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.duration,
    required this.sidecarSubtitles,
  });

  final String path;
  final String fileName;
  final ScannedMediaKind kind;
  final int sizeBytes;
  final DateTime modifiedAt;

  /// `null` when the probe read an audio track but no usable duration. Unknown
  /// is not zero, and callers must render it as unknown.
  final Duration? duration;

  /// First-class, not an afterthought: a media file that arrives with its own
  /// subtitles can skip resource generation entirely, which is the cheapest
  /// path to "start learning now" this product has.
  final List<SidecarSubtitle> sidecarSubtitles;

  bool get hasSidecarSubtitles => sidecarSubtitles.isNotEmpty;
}

/// Incremental scan output. Emitted as the walk proceeds so a caller can show
/// results before the tree is finished.
sealed class MediaScanEvent {
  const MediaScanEvent();

  /// The file or folder the event is about.
  String get path;
}

/// A new or changed media file, fully identified.
class MediaScanDiscovered extends MediaScanEvent {
  const MediaScanDiscovered(this.media);

  final ScannedMedia media;

  @override
  String get path => media.path;
}

/// A known file whose stamp still matches, so it was never probed.
///
/// It is reported rather than silently dropped for two reasons: the caller
/// needs the set of paths still present to decide which records went missing,
/// and sidecar subtitles can appear next to an untouched media file.
class MediaScanUnchanged extends MediaScanEvent {
  const MediaScanUnchanged({
    required this.path,
    required this.sidecarSubtitles,
  });

  @override
  final String path;
  final List<SidecarSubtitle> sidecarSubtitles;
}

/// A candidate the scan refused, with the reason it refused it.
class MediaScanSkipped extends MediaScanEvent {
  const MediaScanSkipped({required this.path, required this.reason});

  @override
  final String path;
  final MediaScanSkipReason reason;
}

/// The terminal summary of a scan, including everything already emitted so a
/// cancelled run still hands back its partial harvest.
class MediaScanReport {
  MediaScanReport({
    required this.status,
    required List<ScannedMedia> discovered,
    required List<String> unchangedPaths,
    required List<MediaScanSkipped> skipped,
  }) : discovered = List.unmodifiable(discovered),
       unchangedPaths = List.unmodifiable(unchangedPaths),
       skipped = List.unmodifiable(skipped);

  final MediaScanStatus status;
  final List<ScannedMedia> discovered;
  final List<String> unchangedPaths;
  final List<MediaScanSkipped> skipped;
}
