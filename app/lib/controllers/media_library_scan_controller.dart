import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/media_library_repository.dart';
import '../models/api_failure.dart';
import '../services/media_library_scanner.dart';
import '../settings.dart';

/// Reads the cheap identity of an already-registered file.
///
/// Injected because the answer only exists on disk: Core stores a media's path
/// and duration, never its size or mtime, and a controller does not touch the
/// file system itself.
typedef KnownMediaStampReader = Future<KnownMediaStamp?> Function(String path);

/// What the media-library surface may honestly say about the library right now.
///
/// The three "no rows" outcomes are separate values on purpose: a folder that
/// was never chosen, a folder that went off disk, and a core that is not
/// answering are three different next steps, and none of them means the
/// library is empty.
enum MediaLibraryScanStatus {
  /// Nothing has been asked of the scanner yet — unknown, not empty.
  idle,

  /// A custom location is remembered, but the disk does not have it.
  folderMissing,

  /// Core is not reachable, so what the library holds cannot be known.
  coreUnavailable,

  /// Walking the folder; results land as they are found.
  scanning,

  /// The walk reached the end of the tree.
  completed,

  /// The caller stopped the walk; what was already registered stands.
  cancelled,

  /// The walk itself broke down.
  failed,
}

/// One file the scan found but Core refused to register.
///
/// Kept per file rather than as a count so the surface can name what did not
/// make it in, and so a retry has something concrete to retry.
@immutable
class MediaRegistrationFailure {
  const MediaRegistrationFailure({
    required this.path,
    required this.fileName,
    required this.failure,
  });

  final String path;
  final String fileName;
  final ApiFailure failure;
}

/// Immutable snapshot of a scan for the media-library surface.
@immutable
class MediaLibraryScanState {
  MediaLibraryScanState({
    this.status = MediaLibraryScanStatus.idle,
    this.folderPath = '',
    this.discovered = 0,
    this.registered = 0,
    this.unchanged = 0,
    this.skipped = 0,
    Set<String> sidecarSubtitlePaths = const <String>{},
    List<MediaRegistrationFailure> registrationFailures =
        const <MediaRegistrationFailure>[],
    this.failure,
  }) : sidecarSubtitlePaths = Set.unmodifiable(sidecarSubtitlePaths),
       registrationFailures = List.unmodifiable(registrationFailures);

  final MediaLibraryScanStatus status;
  final String folderPath;

  /// Files the cheap layer had never seen, this run.
  final int discovered;

  /// Of those, the ones Core accepted.
  final int registered;

  /// Files whose stamp still matched, so they were never probed.
  final int unchanged;

  /// Candidates the scan refused (unreadable, no audio track, probe failed).
  final int skipped;

  /// Library paths seen next to a subtitle file. A fact about the folder, not
  /// a claim that the media is ready to learn from — importing those subtitles
  /// is a separate step that does not exist yet.
  final Set<String> sidecarSubtitlePaths;

  final List<MediaRegistrationFailure> registrationFailures;

  /// Why the scan itself failed; only set for [MediaLibraryScanStatus.failed].
  final ApiFailure? failure;

  bool get isScanning => status == MediaLibraryScanStatus.scanning;

  /// True only when the scan finished a full walk of a real folder — the one
  /// state in which "no rows" is allowed to read as "empty".
  bool get libraryContentsKnown => status == MediaLibraryScanStatus.completed;
}

/// Owns the managed asset store scan: walk the folder, register what is new
/// with Core, then let Core's own list refresh the surface.
///
/// Core stays the authority. Nothing here is rendered as a library row — a
/// [ScannedMedia] is a discovery, and it only becomes content once
/// `registerMedia` accepted it and the library list came back. Registration is
/// discovery (retain false): finding a file in a folder never implies Personal
/// Library membership, which is an explicit Keep.
///
/// The controller owns the lifecycle so the surface never starts work: the
/// composition root calls [enterLibrary] when the media surface becomes
/// visible and [leaveLibrary] when it goes away. Nothing scans at launch —
/// a folder walk plus a probe per new file must not stand between the user and
/// a running app.
class MediaLibraryScanController extends ChangeNotifier {
  MediaLibraryScanController({
    required this.scanner,
    required this.repository,
    required this.resolveFolder,
    required this.registeredPaths,
    required this.refreshLibrary,
    required this.readStamp,
    this.refreshEvery = 25,
  });

  final MediaLibraryScanner scanner;
  final MediaLibraryRepository repository;

  /// The store location plus what the disk currently says about it.
  final Future<ManagedStoreLocation> Function() resolveFolder;

  /// Paths Core already holds, or null while that is unknown.
  final List<String>? Function() registeredPaths;

  /// Pulls Core's library list again — the only thing that puts a newly
  /// registered file on screen.
  final Future<void> Function() refreshLibrary;
  final KnownMediaStampReader readStamp;

  /// How many registrations may accumulate before the library list is pulled
  /// again mid-scan. Refreshing per file would put a second round trip behind
  /// every registration; never refreshing until the end would make a long first
  /// scan look like nothing was happening.
  final int refreshEvery;

  final _stamps = <String, KnownMediaStamp>{};
  final _failures = <MediaRegistrationFailure>[];
  final _pendingRetry = <ScannedMedia>[];
  final _sidecarPaths = <String>{};

  MediaLibraryScan? _active;
  int _generation = 0;
  bool _busy = false;
  bool _disposed = false;
  String _folderPath = '';
  int _discovered = 0;
  int _registered = 0;
  int _unchanged = 0;
  int _skipped = 0;
  int _sinceRefresh = 0;
  MediaLibraryScanStatus _status = MediaLibraryScanStatus.idle;
  ApiFailure? _failure;

  MediaLibraryScanState _state = MediaLibraryScanState();

  MediaLibraryScanState get state => _state;

  /// The media surface became visible: bring the library up to date.
  Future<void> enterLibrary() => _scan();

  /// The surface went away. The walk stops here rather than running on behind
  /// a screen nobody is looking at; whatever was registered stays registered.
  void leaveLibrary() {
    if (_status != MediaLibraryScanStatus.scanning) return;
    cancel();
  }

  /// The manual refresh entry on the surface.
  Future<void> refresh() => _scan();

  void cancel() {
    _generation++;
    _active?.cancel();
    _active = null;
    if (_status == MediaLibraryScanStatus.scanning) {
      _status = MediaLibraryScanStatus.cancelled;
      _publish();
    }
  }

  /// Re-register the files Core refused. Failures are per file, so a retry
  /// takes only those, not another walk of the folder.
  Future<void> retryFailedRegistrations() async {
    if (_busy || _pendingRetry.isEmpty) return;
    if (!repository.isAvailable) {
      _status = MediaLibraryScanStatus.coreUnavailable;
      _publish();
      return;
    }
    _busy = true;
    final generation = ++_generation;
    try {
      final retrying = List<ScannedMedia>.from(_pendingRetry);
      _pendingRetry.clear();
      _failures.clear();
      _publish();
      for (final media in retrying) {
        if (_stale(generation)) return;
        await _register(media);
      }
      if (_stale(generation)) return;
      await refreshLibrary();
    } finally {
      _busy = false;
    }
  }

  Future<void> _scan() async {
    // A second entry into the surface while the first walk is still running is
    // the same walk, not a new one.
    if (_busy) return;
    _busy = true;
    final generation = ++_generation;
    try {
      final folder = await resolveFolder();
      if (_stale(generation)) return;
      _folderPath = folder.path;
      switch (folder.state) {
        // The default app-managed store is a real, scannable location (it is
        // created on demand by the composition root) — only a *custom*
        // location that went off disk is a missing-folder story.
        case StorageLocationState.appManaged:
        case StorageLocationState.ready:
          break;
        case StorageLocationState.missing:
          _reset(MediaLibraryScanStatus.folderMissing);
          return;
      }
      if (!repository.isAvailable) {
        // Registration is the only way a discovery becomes content, so without
        // Core a walk would produce nothing the user could see — and the
        // library's contents stay unknown, not empty.
        _reset(MediaLibraryScanStatus.coreUnavailable);
        return;
      }
      final known = await _knownStamps();
      if (_stale(generation)) return;
      _reset(MediaLibraryScanStatus.scanning);
      final scan = scanner.scan(directory: folder.path, known: known);
      _active = scan;
      await for (final event in scan.events) {
        if (_stale(generation)) return;
        switch (event) {
          case MediaScanUnchanged(:final path, :final sidecarSubtitles):
            _unchanged++;
            if (sidecarSubtitles.isNotEmpty) _sidecarPaths.add(path);
            _publish();
          case MediaScanSkipped():
            _skipped++;
            _publish();
          case MediaScanDiscovered(:final media):
            _discovered++;
            if (media.hasSidecarSubtitles) _sidecarPaths.add(media.path);
            // No notification before the registration: the row only exists once
            // Core accepted it, and _register publishes either way.
            await _register(media);
        }
      }
      final report = await scan.report;
      if (_stale(generation)) return;
      _status = switch (report.status) {
        MediaScanStatus.completed => MediaLibraryScanStatus.completed,
        MediaScanStatus.cancelled => MediaLibraryScanStatus.cancelled,
        // The folder vanished under the walk: that is the missing-folder
        // sentence, not a scan failure.
        MediaScanStatus.rootUnavailable => MediaLibraryScanStatus.folderMissing,
      };
      _publish();
      if (_sinceRefresh > 0) {
        _sinceRefresh = 0;
        await refreshLibrary();
      }
    } catch (error) {
      if (_stale(generation)) return;
      _failure = repository.failureDetail(error);
      _status = MediaLibraryScanStatus.failed;
      _publish();
    } finally {
      _active = null;
      _busy = false;
    }
  }

  /// Seeds the cheap identification layer for everything Core already holds.
  ///
  /// One `stat` per registered path, cached for the rest of the session. That
  /// is what keeps the next scan from spending a probe process on every file
  /// in the folder — the stamps cannot come from Core, which records no size or
  /// mtime.
  Future<List<KnownMediaStamp>> _knownStamps() async {
    for (final path in registeredPaths() ?? const <String>[]) {
      if (_stamps.containsKey(path)) continue;
      final stamp = await readStamp(path);
      if (stamp != null) _stamps[path] = stamp;
    }
    return _stamps.values.toList(growable: false);
  }

  /// Registers one discovery. A refusal is recorded and the walk continues:
  /// one unreadable file must not cost the user the other three hundred.
  ///
  /// Registration is discovery, not retention: finding a file in the store
  /// must not imply Personal Library membership, so `retain` stays false here
  /// no matter what the file is.
  Future<void> _register(ScannedMedia media) async {
    try {
      await repository.registerMedia(
        media.path,
        durationMs: media.duration?.inMilliseconds,
        retain: false,
      );
      _stamps[media.path] = KnownMediaStamp(
        path: media.path,
        sizeBytes: media.sizeBytes,
        modifiedAt: media.modifiedAt,
      );
      _registered++;
      _sinceRefresh++;
      if (_sinceRefresh >= refreshEvery) {
        _sinceRefresh = 0;
        await refreshLibrary();
      }
    } catch (error) {
      _pendingRetry.add(media);
      _failures.add(
        MediaRegistrationFailure(
          path: media.path,
          fileName: media.fileName,
          failure: repository.failureDetail(error),
        ),
      );
    }
    _publish();
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _reset(MediaLibraryScanStatus status) {
    _status = status;
    _discovered = 0;
    _registered = 0;
    _unchanged = 0;
    _skipped = 0;
    _sinceRefresh = 0;
    _failure = null;
    _failures.clear();
    _pendingRetry.clear();
    _sidecarPaths.clear();
    _publish();
  }

  void _publish() {
    _state = MediaLibraryScanState(
      status: _status,
      folderPath: _folderPath,
      discovered: _discovered,
      registered: _registered,
      unchanged: _unchanged,
      skipped: _skipped,
      sidecarSubtitlePaths: _sidecarPaths,
      registrationFailures: _failures,
      failure: _failure,
    );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active?.cancel();
    _active = null;
    super.dispose();
  }
}
