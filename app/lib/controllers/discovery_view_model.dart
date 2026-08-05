import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/discovery_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../data/repositories/content_package_repository.dart';
import '../controllers/download_controller.dart';
import '../models/content_package.dart';
import '../services/content_generator_setup.dart';
import '../services/listen_gen_process_service.dart';
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
    Map<String, PackageStatus> packageStatuses = const {},
    Map<String, ContentGenerationStatus> generationStatuses = const {},
    Map<String, String?> generatorPhases = const {},
    Map<String, ApiFailure?> generationFailures = const {},
    this.generatorConfigured = true,
    this.generatorState = ContentGeneratorState.ready,
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       downloadSnapshots = Map.unmodifiable(downloadSnapshots),
       packageStatuses = Map.unmodifiable(packageStatuses),
       generationStatuses = Map.unmodifiable(generationStatuses),
       generatorPhases = Map.unmodifiable(generatorPhases),
       generationFailures = Map.unmodifiable(generationFailures);

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

  final Map<String, PackageStatus> packageStatuses;
  final Map<String, ContentGenerationStatus> generationStatuses;
  final Map<String, String?> generatorPhases;
  final Map<String, ApiFailure?> generationFailures;

  /// Whether `listen-gen` is configured on this machine. Read from the
  /// repository when the ViewModel is built, so the surface knows before it
  /// offers the action — an unavailable capability is never dressed up as a
  /// button that fails on press.
  final bool generatorConfigured;

  /// Which piece of the toolchain is missing when it is not configured, so
  /// the surface can name the one thing to fix instead of saying "not
  /// configured" at someone.
  final ContentGeneratorState generatorState;

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

  PackageStatus packageStatusOf(String entryId) =>
      packageStatuses[entryId] ?? PackageStatus.unknown;

  /// With no generator on this machine there is no idle state to be in: the
  /// capability is absent before anything is attempted, so the surface reads
  /// `unavailable` from the start rather than offering an action that can only
  /// fail on press.
  ContentGenerationStatus generationStatusOf(String entryId) =>
      generationStatuses[entryId] ??
      (generatorConfigured
          ? ContentGenerationStatus.idle
          : ContentGenerationStatus.unavailable);

  String? generatorPhaseOf(String entryId) => generatorPhases[entryId];

  ApiFailure? generationFailureOf(String entryId) =>
      generationFailures[entryId];

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
    Map<String, PackageStatus>? packageStatuses,
    Map<String, ContentGenerationStatus>? generationStatuses,
    Map<String, String?>? generatorPhases,
    Map<String, ApiFailure?>? generationFailures,
    bool? generatorConfigured,
    ContentGeneratorState? generatorState,
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
    packageStatuses: packageStatuses ?? this.packageStatuses,
    generationStatuses: generationStatuses ?? this.generationStatuses,
    generatorPhases: generatorPhases ?? this.generatorPhases,
    generationFailures: generationFailures ?? this.generationFailures,
    generatorConfigured: generatorConfigured ?? this.generatorConfigured,
    generatorState: generatorState ?? this.generatorState,
  );
}

/// Owns the media discovery presentation state.
final class DiscoveryViewModel extends ChangeNotifier {
  DiscoveryViewModel(
    this._repository, [
    MediaImportRepository? importRepository,
    ContentPackageRepository? contentPackageRepository,
    MediaLibraryRepository? mediaLibraryRepository,
    AcquisitionLedger? ledger,
  ]) : _ledger = ledger ?? AcquisitionLedger.inMemory(),
       _importRepository =
           importRepository ?? const _FakeMediaImportRepository(),
       _contentPackageRepository =
           contentPackageRepository ?? const _FakeContentPackageRepository(),
       _mediaLibraryRepository =
           mediaLibraryRepository ?? const _FakeMediaLibraryRepository() {
    // Read once at construction rather than on press. Whether the generator
    // exists is a property of this machine, not of any entry, and the surface
    // needs it before it decides what to offer.
    _state = _state.copyWith(
      generatorConfigured: _contentPackageRepository.generatorConfigured,
      generatorState: _contentPackageRepository.generatorState,
    );
  }

  final DiscoveryRepository _repository;
  final MediaImportRepository _importRepository;
  final ContentPackageRepository _contentPackageRepository;
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
  final List<MediaEntry> _customEntries = [];
  final Map<String, ListenGenProcessRun> _generationRuns = {};
  final Map<String, StreamSubscription<ListenGenMachineEvent>>
  _generationSubscriptions = {};
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
      unawaited(checkPackage(entries.first.id));
    }
    unawaited(_hydrateLocalDurations(entries));
    unawaited(_resolveRemoteDurations(sourceId, entries));
  }

  void selectItem(String entryId) {
    if (entryId == _state.selectedEntryId) return;

    _state = _state.copyWith(selectedEntryId: entryId);
    notifyListeners();
    final status = state.packageStatusOf(entryId);
    if (status == PackageStatus.unknown ||
        status == PackageStatus.undetermined) {
      unawaited(checkPackage(entryId));
    }
  }

  Future<void> checkPackage(String entryId) async {
    if (_state.packageStatusOf(entryId) == PackageStatus.checking) return;

    _setPackageStatus(entryId, PackageStatus.checking);

    // Without the core there is nothing to ask, so the answer stays missing —
    // "no package" would be a guess dressed up as a fact.
    if (!_mediaLibraryRepository.isAvailable) {
      _setPackageStatus(entryId, PackageStatus.undetermined);
      return;
    }

    final MediaLibraryEntry? localEntry;
    try {
      localEntry = await _findLocalEntry(entryId);
    } catch (error) {
      debugPrint('Error searching local media entry: $error');
      _setPackageStatus(entryId, PackageStatus.undetermined);
      return;
    }
    if (_disposed) return;

    if (localEntry == null) {
      _setPackageStatus(entryId, PackageStatus.notAvailable);
      return;
    }

    // Media already on disk reads as an acquisition that is done, whether this
    // session downloaded it or a previous one did.
    final finished = Map<String, DownloadStatusSnapshot>.of(
      _state.downloadSnapshots,
    )..[entryId] = DownloadStatusSnapshot.completed(localEntry.media.path);
    final updatedStatuses =
        Map<String, PackageStatus>.of(_state.packageStatuses)
          ..[entryId] = localEntry.primaryTrackId != null
              ? PackageStatus.available
              : PackageStatus.notAvailable;

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
      packageStatuses: updatedStatuses,
    );
    notifyListeners();
  }

  void _setPackageStatus(String entryId, PackageStatus status) {
    if (_disposed) return;
    final statuses = Map<String, PackageStatus>.of(_state.packageStatuses)
      ..[entryId] = status;
    _state = _state.copyWith(packageStatuses: statuses);
    notifyListeners();
  }

  /// Recognises media this app downloaded for [entryId] in an earlier session.
  ///
  /// Throws when the library cannot be listed; the caller turns that into an
  /// undetermined status rather than an answer.
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

    final entry = _state.entryById(entryId);
    final mediaUrl = entry?.mediaUrl;
    if (entry == null ||
        mediaUrl == null ||
        entry.acquisition == MediaAcquisition.none) {
      return;
    }

    final controller = _downloadControllerFor(entryId);
    controller.starting();

    try {
      if (_downloadDirectory == null) {
        final directory = await _importRepository.pickDownloadDirectory(
          confirmButtonText: 'Select',
        );
        if (_disposed) return;
        if (directory == null) return; // User cancelled directory pick
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
      controller.fail(_importRepository.failureDetail(error));
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
      );
      if (_disposed) return;
      _localPaths[entryId] = path;
      _mediaIds[entryId] = media.id;
      unawaited(_ledger.record(entryId, mediaId: media.id, path: path));
      _mediaDurations[entryId] = media.durationMs ?? probedDurationMs;
      notifyListeners();
      await checkPackage(entryId);
    } catch (error) {
      debugPrint('Error registering downloaded media: $error');
      if (_disposed) return;
      _downloadControllers[entryId]?.fail(
        _importRepository.failureDetail(error),
      );
    }
  }

  void cancelDownload(String entryId) =>
      _downloadControllers[entryId]?.cancel();

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

  /// Generates a local learning package with listen-gen for a downloaded
  /// entry and imports the result into Core. Replaces the Core-side
  /// transcription job path.
  Future<void> startGeneration(String entryId) async {
    final mediaId = _mediaIds[entryId];
    final mediaPath = _localPaths[entryId];
    final entry = _state.entryById(entryId);
    if (mediaId == null || mediaPath == null || entry == null) return;

    // Nothing to attempt without a generator. Land on `unavailable` rather
    // than running the journey into a `failed` that names an internal code and
    // offers a retry that cannot ever succeed.
    if (!_contentPackageRepository.generatorConfigured) {
      _setGenerationStatus(entryId, ContentGenerationStatus.unavailable);
      _setGenerationFailure(entryId, null);
      return;
    }

    final current = _state.generationStatusOf(entryId);
    if (current == ContentGenerationStatus.preparing ||
        current == ContentGenerationStatus.generating ||
        current == ContentGenerationStatus.importing ||
        current == ContentGenerationStatus.completed) {
      return;
    }

    // The local file is the authority here: it is the thing being generated
    // from. The feed's stated duration is the last resort, and when nothing
    // knows, the probe result stands as zero rather than a made-up length.
    final durationMs =
        _mediaDurations[entryId] ??
        await _importRepository.probeMediaDurationMs(mediaPath) ??
        entry.durationMs ??
        0;
    _mediaDurations[entryId] = durationMs;

    final request = ContentPackageGenerationRequest(
      mediaPath: mediaPath,
      title: entry.title,
      mediaKind: switch (entry.mediaKind) {
        MediaKind.audio => 'audio',
        MediaKind.video => 'video',
      },
      durationMs: durationMs,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    ListenGenProcessRun? run;
    StreamSubscription<ListenGenMachineEvent>? events;
    ApiFailure? eventFailure;
    try {
      run = await _contentPackageRepository.startGeneration(request);
      _generationRuns[entryId] = run;
      _setGenerationStatus(entryId, ContentGenerationStatus.preparing);

      events = run.events.listen(
        (event) {
          switch (event.kind) {
            case ListenGenEventKind.protocol:
            case ListenGenEventKind.started:
              _setGenerationStatus(entryId, ContentGenerationStatus.generating);
            case ListenGenEventKind.phase:
              _setGenerationPhase(entryId, event.phase);
              _setGenerationStatus(entryId, ContentGenerationStatus.generating);
            case ListenGenEventKind.completed:
              // Package path resolution gates the import below.
              break;
            case ListenGenEventKind.failed:
              eventFailure = ApiFailure(
                raw: '',
                code: event.code ?? 'generator_failed',
                message: event.message,
                retryable: true,
              );
            case ListenGenEventKind.cancelled:
              _setGenerationStatus(entryId, ContentGenerationStatus.cancelled);
          }
        },
        onError: (Object error) {
          eventFailure = _contentPackageRepository.failureDetail(error);
        },
      );
      _generationSubscriptions[entryId] = events;

      final packagePath = await run.packagePath;
      if (eventFailure != null) {
        _setGenerationFailure(entryId, eventFailure);
        _setGenerationStatus(entryId, ContentGenerationStatus.failed);
        return;
      }

      _setGenerationStatus(entryId, ContentGenerationStatus.importing);
      await _contentPackageRepository.importPackage(
        mediaId: mediaId,
        packagePath: packagePath,
      );
      if (_disposed) return;

      _setGenerationStatus(entryId, ContentGenerationStatus.completed);
      _setGenerationFailure(entryId, null);
      final packages = Map<String, PackageStatus>.of(_state.packageStatuses)
        ..[entryId] = PackageStatus.available;
      _state = _state.copyWith(packageStatuses: packages);
      notifyListeners();
    } catch (error) {
      debugPrint('Error generating learning package: $error');
      if (!_disposed) {
        final cancelled =
            error is ListenGenProcessFailure && error.code == 'cancelled';
        _setGenerationFailure(
          entryId,
          cancelled ? null : _contentPackageRepository.failureDetail(error),
        );
        _setGenerationStatus(
          entryId,
          cancelled
              ? ContentGenerationStatus.cancelled
              : ContentGenerationStatus.failed,
        );
      }
    } finally {
      await events?.cancel();
      _generationSubscriptions.remove(entryId);
      if (identical(_generationRuns[entryId], run)) {
        _generationRuns.remove(entryId);
      }
      await run?.cleanUp();
    }
  }

  void cancelGeneration(String entryId) {
    _generationRuns[entryId]?.cancel();
  }

  void _setGenerationStatus(String entryId, ContentGenerationStatus status) {
    if (_disposed) return;
    final statuses = Map<String, ContentGenerationStatus>.of(
      _state.generationStatuses,
    )..[entryId] = status;
    _state = _state.copyWith(generationStatuses: statuses);
    notifyListeners();
  }

  void _setGenerationPhase(String entryId, String? phase) {
    if (_disposed) return;
    final phases = Map<String, String?>.of(_state.generatorPhases)
      ..[entryId] = phase;
    _state = _state.copyWith(generatorPhases: phases);
    notifyListeners();
  }

  void _setGenerationFailure(String entryId, ApiFailure? failure) {
    if (_disposed) return;
    final failures = Map<String, ApiFailure?>.of(_state.generationFailures)
      ..[entryId] = failure;
    _state = _state.copyWith(generationFailures: failures);
    notifyListeners();
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

        await checkPackage(entry.id);
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
    for (final sub in _generationSubscriptions.values) {
      sub.cancel();
    }
    _generationSubscriptions.clear();
    for (final run in _generationRuns.values) {
      run.cancel();
    }
    _generationRuns.clear();
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

class _FakeContentPackageRepository implements ContentPackageRepository {
  const _FakeContentPackageRepository();
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  bool get coreAvailable => false;
  @override
  bool get generatorConfigured => false;
  @override
  ContentGeneratorState get generatorState => generatorConfigured
      ? ContentGeneratorState.ready
      : ContentGeneratorState.generatorMissing;
  @override
  Future<String?> pickPackage() async => null;
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) async => throw StateError('No fake import configured');
  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) async => throw StateError('No fake generator configured');
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
  Future<MediaItem> registerMedia(String path, {int? durationMs}) async =>
      throw UnimplementedError();
}
