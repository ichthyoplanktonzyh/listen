import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/discovery_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../controllers/download_controller.dart';
import '../models/discovery.dart';
import '../models/media_download.dart';
import '../models/media_resolution.dart';
import '../models/types.dart';
import '../models/api_failure.dart';
import '../services/acquisition_ledger.dart';
import '../models/embedded_subtitle.dart';
import '../models/saved_vocabulary_count.dart';

/// Immutable snapshot of the discovery home.
@immutable
class DiscoveryState {
  DiscoveryState({
    this.loading = true,
    this.entriesLoading = false,
    this.resolvingUrl = false,
    this.resolveFailed = false,
    List<MediaSource> sources = const [],
    this.selectedSourceId,
    this.sourcesFailure,
    List<MediaEntry> entries = const [],
    this.selectedEntryId,
    this.entriesFailure,
    Map<String, DownloadStatusSnapshot> downloadSnapshots = const {},
    Map<String, DiscoveryMediaAvailability> mediaAvailability = const {},
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       downloadSnapshots = Map.unmodifiable(downloadSnapshots),
       mediaAvailability = Map.unmodifiable(mediaAvailability);

  /// The first catalog load — the surface has no sources yet.
  final bool loading;

  /// A channel's feed is in flight. Distinct from [loading]: the sources are
  /// already on screen, only the shelf below them is still unknown.
  final bool entriesLoading;

  final bool resolvingUrl;
  final bool resolveFailed;
  final List<MediaSource> sources;
  final String? selectedSourceId;

  /// Set when the catalog itself failed. An empty [sources] with no failure is
  /// an empty catalog; with one it is a broken surface.
  final ApiFailure? sourcesFailure;

  final List<MediaEntry> entries;
  final String? selectedEntryId;

  /// Set when the selected channel's feed failed. An empty [entries] with no
  /// failure means the channel is genuinely empty.
  final ApiFailure? entriesFailure;

  /// Typed acquisition state per entry, mirrored from that entry's
  /// [DownloadController]. Absent means nothing has been acquired or attempted.
  final Map<String, DownloadStatusSnapshot> downloadSnapshots;

  /// Whether each entry's media is known to exist on this machine.
  ///
  /// Deliberately separate from [downloadSnapshots]: "is the media local" and
  /// "what is this acquisition attempt doing" are different questions and
  /// must not be fused into one enum. A local row also projects a completed
  /// download snapshot so the acquisition UI reads naturally, but the
  /// availability answer is its own fact.
  final Map<String, DiscoveryMediaAvailability> mediaAvailability;

  bool get hasSources => sources.isNotEmpty;

  MediaSource? sourceById(String id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  MediaEntry? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  MediaSource? get selectedSource =>
      selectedSourceId == null ? null : sourceById(selectedSourceId!);

  MediaEntry? get selectedEntry =>
      selectedEntryId == null ? null : entryById(selectedEntryId!);

  /// Null while a download runs with no known total, so the surface can show
  /// an indeterminate bar rather than a fraction nobody measured.
  double? downloadProgressOf(String entryId) =>
      downloadSnapshots[entryId]?.progress;

  DownloadState downloadStateOf(String entryId) {
    final snapshot = downloadSnapshots[entryId];
    if (snapshot == null) return DownloadState.none;
    return switch (snapshot.kind) {
      DownloadStatusKind.downloading => DownloadState.downloading,
      DownloadStatusKind.completed => DownloadState.done,
      DownloadStatusKind.failed => DownloadState.failed,
    };
  }

  /// Why the last acquisition attempt failed, for the row that offers a retry.
  ApiFailure? downloadFailureOf(String entryId) =>
      downloadSnapshots[entryId]?.failure;

  DiscoveryMediaAvailability mediaAvailabilityOf(String entryId) =>
      mediaAvailability[entryId] ?? DiscoveryMediaAvailability.unknown;

  /// Nullable fields take an explicit `clear*` flag: `selectedEntryId: null`
  /// cannot mean "drop the selection" when every field merges with `??`.
  DiscoveryState copyWith({
    bool? loading,
    bool? entriesLoading,
    bool? resolvingUrl,
    bool? resolveFailed,
    List<MediaSource>? sources,
    String? selectedSourceId,
    ApiFailure? sourcesFailure,
    bool clearSourcesFailure = false,
    List<MediaEntry>? entries,
    String? selectedEntryId,
    bool clearSelectedEntryId = false,
    ApiFailure? entriesFailure,
    bool clearEntriesFailure = false,
    Map<String, DownloadStatusSnapshot>? downloadSnapshots,
    Map<String, DiscoveryMediaAvailability>? mediaAvailability,
  }) => DiscoveryState(
    loading: loading ?? this.loading,
    entriesLoading: entriesLoading ?? this.entriesLoading,
    resolvingUrl: resolvingUrl ?? this.resolvingUrl,
    resolveFailed: resolveFailed ?? this.resolveFailed,
    sources: sources ?? this.sources,
    selectedSourceId: selectedSourceId ?? this.selectedSourceId,
    sourcesFailure: clearSourcesFailure
        ? null
        : sourcesFailure ?? this.sourcesFailure,
    entries: entries ?? this.entries,
    selectedEntryId: clearSelectedEntryId
        ? null
        : selectedEntryId ?? this.selectedEntryId,
    entriesFailure: clearEntriesFailure
        ? null
        : entriesFailure ?? this.entriesFailure,
    downloadSnapshots: downloadSnapshots ?? this.downloadSnapshots,
    mediaAvailability: mediaAvailability ?? this.mediaAvailability,
  );
}

/// Owns the media discovery presentation state.
///
/// Discovery's responsibility ends at "which content, and can we get its
/// bytes on this machine". Whether those bytes are learnable — transcript
/// present, one or several, needs generation — is Workbench's fact, owned by
/// [TranscriptReadinessViewModel] after the media opens. This view model
/// therefore knows nothing about packages, generation, or listen-gen.
final class DiscoveryViewModel extends ChangeNotifier {
  DiscoveryViewModel(
    this._repository, [
    MediaImportRepository? importRepository,
    MediaLibraryRepository? mediaLibraryRepository,
    AcquisitionLedger? ledger,
  ]) : _ledger = ledger ?? AcquisitionLedger.inMemory(),
       _importRepository =
           importRepository ?? const _FakeMediaImportRepository(),
       _mediaLibraryRepository =
           mediaLibraryRepository ?? const _FakeMediaLibraryRepository();

  final DiscoveryRepository _repository;
  final MediaImportRepository _importRepository;
  final MediaLibraryRepository _mediaLibraryRepository;

  /// What earlier sessions acquired, so a restart does not offer a download
  /// that already happened.
  final AcquisitionLedger _ledger;

  static const customSource = MediaSource(
    id: 'custom_imports',
    name: 'Imports',
    language: 'en',
    description: 'Items imported by pasting a link.',
    cover: ChannelCoverTone.slate,
    type: MediaSourceType.youtube,
    avatarUrl: null,
  );

  DiscoveryState _state = DiscoveryState();
  DiscoveryState get state => _state;

  final Map<String, String> _localPaths = {};
  final Map<String, String> _mediaIds = {};
  final Map<String, int?> _mediaDurations = {};
  final Map<String, DownloadController> _downloadControllers = {};

  /// Per-entry single-flight for the "start learning" intent: one intent owns
  /// one acquisition, and a second caller joins the same future instead of
  /// starting a second download.
  final Map<String, Completer<String?>> _acquisitionCompleters = {};

  /// Per-entry in-flight local-media checks, so a reconnect recheck and a
  /// selection-triggered check share one lookup and callers can await it.
  final Map<String, Future<void>> _availabilityChecks = {};

  /// Which launch attempt is currently awaiting its download handle, per
  /// entry. Present while a `startDownload` is between `controller.starting()`
  /// and `controller.attach()` — the window where the controller has no
  /// downloading state yet and a second caller must join instead of relaunch.
  ///
  /// The value is the attempt token: cancellation bumps the token so the
  /// pending launch sees itself as stale when its handle finally lands.
  final Map<String, int> _launchesInFlight = {};

  /// Monotonic per-entry launch token. A launch records the token it started
  /// with; `cancelDownload` bumps it to invalidate the in-flight launch. A
  /// handle that returns after its token was bumped belongs to an attempt
  /// nobody wants and is dropped without attach or adoption.
  final Map<String, int> _launchTokens = {};

  final List<MediaEntry> _customEntries = [];
  String? _downloadDirectory;
  bool _disposed = false;

  Future<void> load() async {
    if (!_ledger.isLoaded) await _ledger.load();
    _state = _state.copyWith(loading: true, clearSourcesFailure: true);
    notifyListeners();

    final List<MediaSource> repoSources;
    try {
      repoSources = await _repository.sources();
    } catch (error) {
      // A catalog that failed is not a catalog that is empty, and leaving
      // `loading` set would spin forever.
      debugPrint('Error loading discovery sources: $error');
      if (_disposed) return;
      _state = _state.copyWith(
        loading: false,
        sourcesFailure: ApiFailure(raw: error.toString()),
      );
      notifyListeners();
      return;
    }
    if (_disposed) return;

    final allSources = [...repoSources, customSource];
    final first = allSources.isEmpty ? null : allSources.first.id;

    _state = _state.copyWith(
      loading: false,
      sources: allSources,
      selectedSourceId: first,
    );

    if (first != null) {
      await _loadEntriesFor(first);
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectChannel(String sourceId) async {
    if (sourceId == _state.selectedSourceId) return;

    _state = _state.copyWith(
      selectedSourceId: sourceId,
      clearSelectedEntryId: true,
    );
    notifyListeners();
    await _loadEntriesFor(sourceId);
  }

  /// Re-runs the selected channel's feed after a failure.
  Future<void> retryEntries() async {
    final sourceId = _state.selectedSourceId;
    if (sourceId == null) return;
    await _loadEntriesFor(sourceId);
  }

  Future<void> _loadEntriesFor(String sourceId) async {
    // The old channel's cards stop standing in for the new one's while its
    // header is already on screen.
    _state = _state.copyWith(
      entriesLoading: true,
      entries: const [],
      clearSelectedEntryId: true,
      clearEntriesFailure: true,
    );
    notifyListeners();

    final List<MediaEntry> entries;
    try {
      entries = sourceId == customSource.id
          ? List<MediaEntry>.of(_customEntries)
          : await _repository.entriesFor(sourceId);
    } catch (error) {
      debugPrint('Error loading entries for channel $sourceId: $error');
      if (_disposed || sourceId != _state.selectedSourceId) return;
      _state = _state.copyWith(
        entriesLoading: false,
        entriesFailure: ApiFailure(raw: error.toString()),
      );
      notifyListeners();
      return;
    }
    if (_disposed) return;
    // A slow channel must not land on top of the one the learner switched to.
    if (sourceId != _state.selectedSourceId) return;

    _state = _state.copyWith(
      entriesLoading: false,
      entries: entries,
      selectedEntryId: entries.isEmpty ? null : entries.first.id,
      clearSelectedEntryId: entries.isEmpty,
    );
    notifyListeners();
    if (entries.isNotEmpty) {
      unawaited(refreshMediaAvailability(entries.first.id));
    }
    unawaited(_hydrateLocalDurations(entries));
    unawaited(_resolveRemoteDurations(sourceId, entries));
  }

  void selectItem(String entryId) {
    if (entryId == _state.selectedEntryId) return;

    _state = _state.copyWith(selectedEntryId: entryId);
    notifyListeners();
    final availability = state.mediaAvailabilityOf(entryId);
    if (availability == DiscoveryMediaAvailability.unknown ||
        availability == DiscoveryMediaAvailability.undetermined) {
      unawaited(refreshMediaAvailability(entryId));
    }
  }

  /// Reconciles whether [entryId]'s media exists on this machine.
  ///
  /// The only question asked is "is the media local". Whether it has a
  /// transcript is never consulted: local media whose primary learning track
  /// is not set is still local and still learnable. Workbench decides whether
  /// a transcript is needed after the media opens.
  ///
  /// Result states:
  ///
  /// * core/library unavailable → [DiscoveryMediaAvailability.undetermined]
  /// * library query failed → [DiscoveryMediaAvailability.undetermined]
  /// * matching local media found → [DiscoveryMediaAvailability.local], with
  ///   `_localPaths`/`_mediaIds`/`_mediaDurations` filled, the ledger recorded,
  ///   and the download snapshot projected to completed
  /// * no match → [DiscoveryMediaAvailability.remote]
  Future<void> refreshMediaAvailability(String entryId) {
    final inFlight = _availabilityChecks[entryId];
    if (inFlight != null) return inFlight;
    late final Future<void> future;
    future = _refreshMediaAvailability(entryId).whenComplete(() {
      if (identical(_availabilityChecks[entryId], future)) {
        _availabilityChecks.remove(entryId);
      }
    });
    _availabilityChecks[entryId] = future;
    return future;
  }

  /// The same reconciliation for whatever entry is selected, so a meaningful
  /// invalidation (core reconnect, entry change) can re-ask without polling.
  Future<void> refreshSelectedMediaAvailability() async {
    final selectedId = _state.selectedEntryId;
    if (selectedId == null) return;
    await refreshMediaAvailability(selectedId);
  }

  Future<void> _refreshMediaAvailability(String entryId) async {
    // Without the core there is nothing to ask, so the answer stays missing —
    // "not on this machine" would be a guess dressed up as a fact.
    if (!_mediaLibraryRepository.isAvailable) {
      _setMediaAvailability(entryId, DiscoveryMediaAvailability.undetermined);
      return;
    }
    _setMediaAvailability(entryId, DiscoveryMediaAvailability.checking);

    final MediaLibraryEntry? localEntry;
    try {
      localEntry = await _findLocalEntry(entryId);
    } catch (error) {
      debugPrint('Error searching local media entry: $error');
      if (_disposed) return;
      _setMediaAvailability(entryId, DiscoveryMediaAvailability.undetermined);
      return;
    }
    if (_disposed) return;

    if (localEntry == null) {
      // Definitive answer: this entry's media is not on this machine. Any
      // local identity from an earlier, now-refuted answer must go with it —
      // a stale path would let Start Learning open a file Core no longer
      // knows about, and a projected "completed" snapshot would keep saying
      // "on this device" after the media is gone.
      _localPaths.remove(entryId);
      _mediaIds.remove(entryId);
      final snapshots = Map<String, DownloadStatusSnapshot>.of(
        _state.downloadSnapshots,
      );
      // Only the stale completed projection is dropped. A live downloading or
      // failed snapshot is the acquisition lifecycle's own fact and survives.
      if (snapshots[entryId]?.kind == DownloadStatusKind.completed) {
        snapshots.remove(entryId);
      }
      _state = _state.copyWith(
        downloadSnapshots: snapshots,
        mediaAvailability: {
          ..._state.mediaAvailability,
          entryId: DiscoveryMediaAvailability.remote,
        },
      );
      notifyListeners();
      return;
    }

    // Media already on disk reads as an acquisition that is done, whether this
    // session downloaded it or a previous one did.
    final finished = Map<String, DownloadStatusSnapshot>.of(
      _state.downloadSnapshots,
    )..[entryId] = DownloadStatusSnapshot.completed(localEntry.media.path);
    _localPaths[entryId] = localEntry.media.path;
    _mediaIds[entryId] = localEntry.media.id;
    unawaited(
      _ledger.record(
        entryId,
        mediaId: localEntry.media.id,
        path: localEntry.media.path,
      ),
    );
    _mediaDurations[entryId] = localEntry.media.durationMs;

    _state = _state.copyWith(
      downloadSnapshots: finished,
      mediaAvailability: {
        ..._state.mediaAvailability,
        entryId: DiscoveryMediaAvailability.local,
      },
    );
    notifyListeners();
  }

  void _setMediaAvailability(String entryId, DiscoveryMediaAvailability value) {
    if (_disposed) return;
    _state = _state.copyWith(
      mediaAvailability: {..._state.mediaAvailability, entryId: value},
    );
    notifyListeners();
  }

  /// Recognises media this app downloaded for [entryId] in an earlier session.
  ///
  /// Throws when the library cannot be listed; the caller turns that into an
  /// undetermined answer rather than a claim.
  ///
  /// The written record answers first: the app knows what it downloaded, so
  /// it does not have to re-derive it from a filename. yt-dlp's `[id]`
  /// convention stays as the fallback that recognises media acquired before
  /// the ledger existed, and it only ever applied to the external-tool path —
  /// an enclosure is saved under the publisher's filename, which has nothing
  /// to do with the feed's guid.
  ///
  /// A recorded media id still has to be present in Core's library. The record
  /// says what was acquired, not what survives: a person who emptied a folder
  /// did not consult this file first, and a row that claimed a file that is
  /// gone would be exactly the kind of confident lie the ledger exists to
  /// avoid.
  Future<MediaLibraryEntry?> _findLocalEntry(String entryId) async {
    final library = await _mediaLibraryRepository.listMediaLibrary();

    final recorded = _ledger[entryId];
    if (recorded != null) {
      for (final entry in library) {
        if (entry.media.id == recorded.mediaId) return entry;
      }
      // Recorded but no longer in the library: drop it rather than re-check
      // this row on every visit for the life of the install.
      await _ledger.forget(entryId);
    }

    if (_state.entryById(entryId)?.acquisition !=
        MediaAcquisition.externalTool) {
      return null;
    }
    for (final entry in library) {
      if (entry.media.path.contains('[$entryId]')) return entry;
    }
    return null;
  }

  /// One [DownloadController] per entry: several rows can be acquiring at once,
  /// and each needs its own generation guard so a late callback from a
  /// cancelled or superseded run cannot land on the row that replaced it.
  DownloadController _downloadControllerFor(String entryId) =>
      _downloadControllers.putIfAbsent(entryId, () {
        final controller = DownloadController(
          failureMapper: _importRepository.failureDetail,
          // A discovery row stays on screen, so its failure waits for a retry
          // instead of quietly timing out from under the learner.
          failedAutoDismiss: null,
        );
        controller.addListener(
          () => _publishDownloadSnapshot(entryId, controller.snapshot),
        );
        return controller;
      });

  void _publishDownloadSnapshot(String entryId, DownloadStatusSnapshot? value) {
    if (_disposed) return;
    final snapshots = Map<String, DownloadStatusSnapshot>.of(
      _state.downloadSnapshots,
    );
    if (value == null) {
      snapshots.remove(entryId);
    } else {
      snapshots[entryId] = value;
      if (value.kind == DownloadStatusKind.failed) {
        // A failed attempt ends the "start learning" intent without a path;
        // Workbench must not open for an acquisition that never landed. The
        // typed failure stays in the download state for the retry surface.
        _completeAcquisition(entryId, null);
      }
    }
    _state = _state.copyWith(downloadSnapshots: snapshots);
    notifyListeners();
  }

  /// Also the retry: a failed row calls straight back into this.
  ///
  /// Which acquisition runs is the entry's own fact, not the app's default. A
  /// podcast enclosure is fetched directly because the publisher put it in the
  /// feed for that; a YouTube page goes to the user's external tool. An entry
  /// with nothing to acquire never starts one.
  Future<void> startDownload(String entryId) async {
    if (_state.downloadStateOf(entryId) == DownloadState.done) return;
    // Established single-flight: once a handle is attached the controller is
    // in `downloading`, and restarting it would cancel the live handle and
    // relaunch. A joiner (e.g. `acquireForLearning`) waits on the acquisition
    // completer instead, which the original handle's adoption resolves.
    if (_state.downloadStateOf(entryId) == DownloadState.downloading) return;
    // Launch-window single-flight: another attempt is still between
    // `controller.starting()` and `controller.attach()`. A launch whose token
    // was invalidated by a cancel is not in flight anymore and may be
    // superseded by a fresh attempt.
    final inFlight = _launchesInFlight[entryId];
    if (inFlight != null && inFlight == _launchTokens[entryId]) return;

    final entry = _state.entryById(entryId);
    final mediaUrl = entry?.mediaUrl;
    if (entry == null ||
        mediaUrl == null ||
        entry.acquisition == MediaAcquisition.none) {
      _completeAcquisition(entryId, null);
      return;
    }

    final controller = _downloadControllerFor(entryId);
    controller.starting();
    final token = (_launchTokens[entryId] ?? 0) + 1;
    _launchTokens[entryId] = token;
    _launchesInFlight[entryId] = token;

    try {
      if (_downloadDirectory == null) {
        final directory = await _importRepository.pickDownloadDirectory(
          confirmButtonText: 'Select',
        );
        if (_disposed) {
          _completeAcquisition(entryId, null);
          return;
        }
        if (directory == null) {
          // User cancelled directory pick: the intent ends without a path.
          _completeAcquisition(entryId, null);
          return;
        }
        _downloadDirectory = directory;
      }

      final handle = switch (entry.acquisition) {
        MediaAcquisition.enclosure => await _importRepository.downloadEnclosure(
          mediaUrl,
          _downloadDirectory!,
          expectedBytes: entry.mediaByteLength,
        ),
        MediaAcquisition.externalTool =>
          await _importRepository.downloadOnlineMedia(
            mediaUrl,
            _downloadDirectory!,
          ),
        MediaAcquisition.none => throw StateError('guarded above'),
      };
      if (_disposed) {
        handle.cancel();
        _completeAcquisition(entryId, null);
        return;
      }
      // A cancel during the launch window invalidated this attempt: the
      // handle belongs to nobody and must be dropped without attach, without
      // adoption, and without disturbing the cancelled state.
      if (!_isCurrentLaunch(entryId, token)) {
        handle.cancel();
        return;
      }

      controller.attach(
        progress: handle.progress,
        completed: handle.completed,
        cancel: handle.cancel,
        onCompleted: (path) => unawaited(_adoptDownloadedMedia(entryId, path)),
      );
    } catch (error) {
      debugPrint('Error starting download: $error');
      if (_disposed) return;
      // Only a current attempt may surface its launch failure. A stale launch
      // that errors after a cancel must not flip the cancelled/none state to
      // failed.
      if (_isCurrentLaunch(entryId, token)) {
        controller.fail(_importRepository.failureDetail(error));
      }
    } finally {
      // Remove this attempt's own marker only: a newer attempt that started
      // while this one was still finishing keeps its bookkeeping.
      if (_launchesInFlight[entryId] == token) {
        _launchesInFlight.remove(entryId);
      }
    }
  }

  bool _isCurrentLaunch(String entryId, int token) =>
      !_disposed && _launchTokens[entryId] == token;

  /// The "start learning" intent, as a future that resolves to a local path.
  ///
  /// Semantics:
  ///
  /// * media already local → returns the registered path without touching the
  ///   downloader;
  /// * remote and acquirable → starts (or joins) one acquisition, waits for
  ///   probe → Core registration → ledger, then returns the path;
  /// * cancelled / failed / unacquirable → null; the typed failure (if any)
  ///   is already in the download state for the surface to show and retry.
  ///
  /// Workbench opening is the caller's decision: this only guarantees local
  /// media, and a non-null result is the signal to open it.
  Future<String?> acquireForLearning(String entryId) async {
    // Let an in-flight local-media check land first: media already on disk
    // must not be re-downloaded because the check lost the race.
    final inFlightCheck = _availabilityChecks[entryId];
    if (inFlightCheck != null) await inFlightCheck;

    final localPath = _localPaths[entryId];
    if (localPath != null) return localPath;

    final existing = _acquisitionCompleters[entryId];
    if (existing != null) return existing.future;

    final completer = Completer<String?>();
    _acquisitionCompleters[entryId] = completer;
    unawaited(
      completer.future.then(
        (_) => _dropAcquisitionCompleter(entryId, completer),
        onError: (_) => _dropAcquisitionCompleter(entryId, completer),
      ),
    );

    // Launch in the background. The returned future resolves the moment the
    // acquisition lifecycle resolves — adoption with the path, failure or
    // cancel with null — so a cancel during the launch window is answered
    // promptly instead of waiting for the stale launch to settle.
    unawaited(() async {
      try {
        await startDownload(entryId);
      } catch (_) {
        // The launch reports its own failures through the download state.
      }
      // Safety net: a launch that decided there is nothing to acquire (no
      // URL, acquisition none, directory pick cancelled) resolves the intent
      // empty rather than hanging the caller. An active download resolves
      // the bridge itself.
      final state = _state.downloadStateOf(entryId);
      if (!completer.isCompleted &&
          !_launchesInFlight.containsKey(entryId) &&
          state != DownloadState.downloading &&
          state != DownloadState.done) {
        completer.complete(null);
      }
    }());

    return completer.future;
  }

  void _dropAcquisitionCompleter(String entryId, Completer<String?> completer) {
    if (identical(_acquisitionCompleters[entryId], completer)) {
      _acquisitionCompleters.remove(entryId);
    }
  }

  void _completeAcquisition(String entryId, String? path) {
    final completer = _acquisitionCompleters[entryId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(path);
    }
  }

  /// Registers a freshly downloaded file with the core so the entry stops being
  /// a remote listing and becomes local media.
  ///
  /// A failure here is reported as an acquisition failure rather than dropped:
  /// the bytes may be on disk, but an entry the core never registered is not
  /// something the learner can act on, and silently reverting to "not
  /// downloaded" would invite an identical second attempt.
  Future<void> _adoptDownloadedMedia(String entryId, String path) async {
    try {
      final probedDurationMs = await _importRepository.probeMediaDurationMs(
        path,
      );
      final media = await _mediaLibraryRepository.registerMedia(
        path,
        durationMs: probedDurationMs,
        // Download adoption is acquisition, not retention: the bytes landing
        // on disk must not silently create a Personal Library row.
        retain: false,
      );
      if (_disposed) return;
      _localPaths[entryId] = path;
      _mediaIds[entryId] = media.id;
      unawaited(_ledger.record(entryId, mediaId: media.id, path: path));
      _mediaDurations[entryId] = media.durationMs ?? probedDurationMs;
      _setMediaAvailability(entryId, DiscoveryMediaAvailability.local);
      _completeAcquisition(entryId, path);
    } catch (error) {
      debugPrint('Error registering downloaded media: $error');
      if (_disposed) return;
      _downloadControllers[entryId]?.fail(
        _importRepository.failureDetail(error),
      );
    }
  }

  void cancelDownload(String entryId) {
    _downloadControllers[entryId]?.cancel();
    // Invalidate an in-flight launch: a handle that lands later belongs to
    // an attempt nobody wants, so the pending `startDownload` will see a
    // stale token and drop it. (No launch in flight → nothing to invalidate;
    // an attached download is already handled by the controller's own cancel.)
    if (_launchesInFlight.containsKey(entryId)) {
      _launchTokens[entryId] = (_launchTokens[entryId] ?? 0) + 1;
    }
    // A cancelled run ends the intent empty: no adoption, no Workbench.
    _completeAcquisition(entryId, null);
  }

  String? localPathFor(String entryId) => _localPaths[entryId];

  /// Real duration for an entry when known (probed locally or resolved from
  /// the remote video); null falls back to the feed placeholder.
  int? durationMsFor(String entryId) => _mediaDurations[entryId];

  /// Fills known durations from the media library for already-downloaded
  /// entries using one batched query instead of per-entry lookups.
  Future<void> _hydrateLocalDurations(List<MediaEntry> entries) async {
    if (entries.isEmpty || !_mediaLibraryRepository.isAvailable) return;
    try {
      final library = await _mediaLibraryRepository.listMediaLibrary();
      if (_disposed) return;
      var changed = false;
      for (final entry in entries) {
        if (_mediaDurations[entry.id] != null) continue;
        // Same filename-convention limit as [_findLocalEntry].
        if (entry.acquisition != MediaAcquisition.externalTool) continue;
        final local = library.where(
          (item) => item.media.path.contains('[${entry.id}]'),
        );
        final duration = local.isEmpty ? null : local.first.media.durationMs;
        if (duration == null) continue;
        _mediaDurations[entry.id] = duration;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('Error hydrating discovery durations: $e');
    }
  }

  /// Resolves real durations for feed entries in the background (yt-dlp) with
  /// a small concurrency cap. Zero/unknown results keep the placeholder until
  /// a real value lands.
  ///
  /// The workers belong to [sourceId]: once the learner has switched channels
  /// their entries are off screen, so they abort instead of piling subprocesses
  /// up behind every switch.
  Future<void> _resolveRemoteDurations(
    String sourceId,
    List<MediaEntry> entries,
  ) async {
    final pending = entries
        .where(
          (entry) =>
              _mediaDurations[entry.id] == null &&
              entry.durationMs == null &&
              entry.mediaUrl != null &&
              // Only the external-tool path needs this: a podcast feed states
              // its own durations, and there is no page for yt-dlp to read at
              // an enclosure URL anyway.
              entry.acquisition == MediaAcquisition.externalTool &&
              entry.sourceId != customSource.id,
        )
        .toList(growable: false);
    if (pending.isEmpty) return;

    var index = 0;
    final workers = List.generate(3, (_) async {
      while (!_disposed && _state.selectedSourceId == sourceId) {
        final next = index++;
        if (next >= pending.length) return;
        final entry = pending[next];
        try {
          final details = await _importRepository.resolveVideoDetails(
            entry.mediaUrl!,
          );
          if (_disposed || _state.selectedSourceId != sourceId) return;
          if (details.durationMs <= 0) continue;
          if (_mediaDurations[entry.id] == null) {
            _mediaDurations[entry.id] = details.durationMs;
            notifyListeners();
          }
        } catch (_) {
          // Best-effort: keep the feed placeholder on resolution failure.
        }
      }
    });
    await Future.wait(workers);
  }

  Future<void> importCustomUrl(String url) async {
    if (url.trim().isEmpty) return;

    _state = _state.copyWith(resolvingUrl: true, resolveFailed: false);
    notifyListeners();

    try {
      final isVideo =
          url.contains('watch?v=') ||
          url.contains('youtu.be/') ||
          url.contains('/shorts/') ||
          url.contains('/v/');

      if (isVideo) {
        final entry = await _repository.resolveCustomVideo(
          url,
          _importRepository,
        );
        if (_disposed) return;

        // Insert into custom entries
        if (!_customEntries.any((e) => e.id == entry.id)) {
          _customEntries.add(entry);
        }

        // Switch to Custom Imports channel
        _state = _state.copyWith(
          selectedSourceId: customSource.id,
          entriesLoading: false,
          clearEntriesFailure: true,
          entries: _customEntries,
          selectedEntryId: entry.id,
        );
        notifyListeners();

        await refreshMediaAvailability(entry.id);
      } else {
        // Channel URL
        final channel = await _repository.resolveCustomChannel(
          url,
          _importRepository,
        );
        if (_disposed) return;

        // Reload channels
        await load();
        if (_disposed) return;

        // Select the newly added channel
        await selectChannel(channel.id);
      }
    } catch (e) {
      debugPrint('Error importing custom URL: $e');
      if (_disposed) return;
      _state = _state.copyWith(resolveFailed: true);
      notifyListeners();
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(resolvingUrl: false);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final completer in _acquisitionCompleters.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _acquisitionCompleters.clear();
    for (final controller in _downloadControllers.values) {
      controller.dispose();
    }
    _downloadControllers.clear();
    super.dispose();
  }
}

class _FakeMediaImportRepository implements MediaImportRepository {
  const _FakeMediaImportRepository();
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => null;
  @override
  Future<String> resolveOnlineMedia(String pageUrl) async => '';
  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) async => const _FakeMediaDownloadHandle();
  @override
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  }) async => const _FakeMediaDownloadHandle();
  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) async =>
      const ResolvedVideoDetails(
        id: '',
        title: 'YouTube Video',
        description: '',
        durationMs: 0,
        viewCount: 0,
        thumbnail: null,
        channelId: '',
        uploadDate: '',
      );
  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(
    String channelUrl,
  ) async => const ResolvedChannelDetails(id: '', name: '');
  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async => [];
  @override
  Future<int?> probeMediaDurationMs(String mediaPath) async => null;
  @override
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) async => '';
}

class _FakeMediaDownloadHandle implements MediaDownloadHandle {
  const _FakeMediaDownloadHandle();
  @override
  Stream<double> get progress => const Stream.empty();
  @override
  Future<String?> get completed => Future.value(null);
  @override
  void cancel() {}
}

class _FakeMediaLibraryRepository implements MediaLibraryRepository {
  const _FakeMediaLibraryRepository();
  @override
  bool get isAvailable => false;
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) async => const SavedVocabularyCount(total: 0, capped: false);
  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() async => [];
  @override
  Future<MediaLibraryEntry> setTriageIntent(
    String mediaId,
    String? intent,
  ) async => throw UnimplementedError();
  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) async => throw UnimplementedError();
}
