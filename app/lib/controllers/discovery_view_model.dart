import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/discovery_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../data/repositories/content_package_repository.dart';
import '../models/content_package.dart';
import '../services/listen_gen_process_service.dart';
import '../models/discovery.dart';
import '../models/media_download.dart';
import '../models/media_resolution.dart';
import '../models/types.dart';
import '../models/api_failure.dart';
import '../models/embedded_subtitle.dart';
import '../models/saved_vocabulary_count.dart';

/// Immutable snapshot of the discovery home.
@immutable
class DiscoveryState {
  DiscoveryState({
    this.loading = true,
    this.resolvingUrl = false,
    this.resolveFailed = false,
    List<MediaSource> sources = const [],
    this.selectedSourceId,
    List<MediaEntry> entries = const [],
    this.selectedEntryId,
    Map<String, double> downloads = const {},
    Map<String, PackageStatus> packageStatuses = const {},
    Map<String, ContentGenerationStatus> generationStatuses = const {},
    Map<String, String?> generatorPhases = const {},
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       downloads = Map.unmodifiable(downloads),
       packageStatuses = Map.unmodifiable(packageStatuses),
       generationStatuses = Map.unmodifiable(generationStatuses),
       generatorPhases = Map.unmodifiable(generatorPhases);

  final bool loading;
  final bool resolvingUrl;
  final bool resolveFailed;
  final List<MediaSource> sources;
  final String? selectedSourceId;
  final List<MediaEntry> entries;
  final String? selectedEntryId;
  final Map<String, double> downloads;
  final Map<String, PackageStatus> packageStatuses;
  final Map<String, ContentGenerationStatus> generationStatuses;
  final Map<String, String?> generatorPhases;

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

  double downloadProgressOf(String entryId) => downloads[entryId] ?? 0;

  DownloadState downloadStateOf(String entryId) {
    final progress = downloads[entryId];
    if (progress == null) return DownloadState.none;
    return progress >= 1 ? DownloadState.done : DownloadState.downloading;
  }

  PackageStatus packageStatusOf(String entryId) =>
      packageStatuses[entryId] ?? PackageStatus.unknown;

  ContentGenerationStatus generationStatusOf(String entryId) =>
      generationStatuses[entryId] ?? ContentGenerationStatus.idle;

  String? generatorPhaseOf(String entryId) => generatorPhases[entryId];

  DiscoveryState copyWith({
    bool? loading,
    bool? resolvingUrl,
    bool? resolveFailed,
    List<MediaSource>? sources,
    String? selectedSourceId,
    List<MediaEntry>? entries,
    String? selectedEntryId,
    Map<String, double>? downloads,
    Map<String, PackageStatus>? packageStatuses,
    Map<String, ContentGenerationStatus>? generationStatuses,
    Map<String, String?>? generatorPhases,
  }) => DiscoveryState(
    loading: loading ?? this.loading,
    resolvingUrl: resolvingUrl ?? this.resolvingUrl,
    resolveFailed: resolveFailed ?? this.resolveFailed,
    sources: sources ?? this.sources,
    selectedSourceId: selectedSourceId ?? this.selectedSourceId,
    entries: entries ?? this.entries,
    selectedEntryId: selectedEntryId ?? this.selectedEntryId,
    downloads: downloads ?? this.downloads,
    packageStatuses: packageStatuses ?? this.packageStatuses,
    generationStatuses: generationStatuses ?? this.generationStatuses,
    generatorPhases: generatorPhases ?? this.generatorPhases,
  );
}

/// Owns the media discovery presentation state.
final class DiscoveryViewModel extends ChangeNotifier {
  DiscoveryViewModel(
    this._repository, [
    MediaImportRepository? importRepository,
    ContentPackageRepository? contentPackageRepository,
    MediaLibraryRepository? mediaLibraryRepository,
  ]) : _importRepository =
           importRepository ?? const _FakeMediaImportRepository(),
       _contentPackageRepository =
           contentPackageRepository ?? const _FakeContentPackageRepository(),
       _mediaLibraryRepository =
           mediaLibraryRepository ?? const _FakeMediaLibraryRepository();

  final DiscoveryRepository _repository;
  final MediaImportRepository _importRepository;
  final ContentPackageRepository _contentPackageRepository;
  final MediaLibraryRepository _mediaLibraryRepository;

  static const customSource = MediaSource(
    id: 'custom_imports',
    name: 'Imports',
    language: 'en',
    description: 'YouTube videos imported by pasting custom links.',
    cover: ChannelCoverTone.slate,
    type: MediaSourceType.youtube,
    avatarUrl: null,
  );

  DiscoveryState _state = DiscoveryState();
  DiscoveryState get state => _state;

  final Map<String, String> _localPaths = {};
  final Map<String, String> _mediaIds = {};
  final Map<String, int?> _mediaDurations = {};
  final Map<String, StreamSubscription<double>> _downloadSubscriptions = {};
  final Map<String, MediaDownloadHandle> _activeDownloads = {};
  final List<MediaEntry> _customEntries = [];
  final Map<String, ListenGenProcessRun> _generationRuns = {};
  final Map<String, StreamSubscription<ListenGenMachineEvent>>
  _generationSubscriptions = {};
  String? _downloadDirectory;
  bool _disposed = false;

  Future<void> load() async {
    final repoSources = await _repository.sources();
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

    _state = _state.copyWith(selectedSourceId: sourceId, selectedEntryId: null);
    notifyListeners();
    await _loadEntriesFor(sourceId);
  }

  Future<void> _loadEntriesFor(String sourceId) async {
    List<MediaEntry> entries;
    if (sourceId == 'custom_imports') {
      entries = _customEntries;
    } else {
      entries = await _repository.entriesFor(sourceId);
    }
    if (_disposed) return;

    _state = _state.copyWith(
      entries: entries,
      selectedEntryId: entries.isEmpty ? null : entries.first.id,
    );
    notifyListeners();
    if (entries.isNotEmpty) {
      unawaited(checkPackage(entries.first.id));
    }
  }

  void selectItem(String entryId) {
    if (entryId == _state.selectedEntryId) return;

    _state = _state.copyWith(selectedEntryId: entryId);
    notifyListeners();
    if (state.packageStatusOf(entryId) == PackageStatus.unknown) {
      unawaited(checkPackage(entryId));
    }
  }

  Future<void> checkPackage(String entryId) async {
    if (_state.packageStatusOf(entryId) == PackageStatus.checking) return;

    final statuses = Map<String, PackageStatus>.of(_state.packageStatuses)
      ..[entryId] = PackageStatus.checking;
    _state = _state.copyWith(packageStatuses: statuses);
    notifyListeners();

    final localEntry = await _findLocalEntry(entryId);
    if (_disposed) return;

    if (localEntry != null) {
      final finished = Map<String, double>.of(_state.downloads)
        ..[entryId] = 1.0;
      final updatedStatuses =
          Map<String, PackageStatus>.of(_state.packageStatuses)
            ..[entryId] = localEntry.primaryTrackId != null
                ? PackageStatus.available
                : PackageStatus.notAvailable;

      _localPaths[entryId] = localEntry.media.path;
      _mediaIds[entryId] = localEntry.media.id;

      _state = _state.copyWith(
        downloads: finished,
        packageStatuses: updatedStatuses,
      );
      notifyListeners();
    } else {
      final updatedStatuses = Map<String, PackageStatus>.of(
        _state.packageStatuses,
      )..[entryId] = PackageStatus.notAvailable;
      _state = _state.copyWith(packageStatuses: updatedStatuses);
      notifyListeners();
    }
  }

  Future<MediaLibraryEntry?> _findLocalEntry(String entryId) async {
    try {
      if (!_mediaLibraryRepository.isAvailable) return null;
      final library = await _mediaLibraryRepository.listMediaLibrary();
      for (final entry in library) {
        final path = entry.media.path;
        if (path.contains('[$entryId]')) {
          return entry;
        }
      }
    } catch (e) {
      debugPrint('Error searching local media entry: $e');
    }
    return null;
  }

  Future<void> startDownload(String entryId) async {
    if (_state.downloadStateOf(entryId) == DownloadState.done) return;

    final entry = _state.entryById(entryId);
    if (entry == null || entry.videoUrl == null) return;

    try {
      if (_downloadDirectory == null) {
        final directory = await _importRepository.pickDownloadDirectory(
          confirmButtonText: 'Select',
        );
        if (_disposed) return;
        if (directory == null) return; // User cancelled directory pick
        _downloadDirectory = directory;
      }

      final downloads = Map<String, double>.of(_state.downloads)
        ..[entryId] = 0.01;
      _state = _state.copyWith(downloads: downloads);
      notifyListeners();

      _activeDownloads[entryId]?.cancel();
      await _downloadSubscriptions[entryId]?.cancel();

      final handle = await _importRepository.downloadOnlineMedia(
        entry.videoUrl!,
        _downloadDirectory!,
      );
      _activeDownloads[entryId] = handle;

      _downloadSubscriptions[entryId] = handle.progress.listen(
        (progress) {
          if (_disposed) return;
          final updated = Map<String, double>.of(_state.downloads)
            ..[entryId] = progress;
          _state = _state.copyWith(downloads: updated);
          notifyListeners();
        },
        onError: (Object error) {
          debugPrint('Download error: $error');
          _cleanDownload(entryId);
        },
      );

      unawaited(
        handle.completed.then((path) async {
          if (_disposed) return;
          if (path == null) {
            _cleanDownload(entryId);
            return;
          }

          try {
            final media = await _mediaLibraryRepository.registerMedia(path);
            _localPaths[entryId] = path;
            _mediaIds[entryId] = media.id;
            _mediaDurations[entryId] = media.durationMs;

            final finished = Map<String, double>.of(_state.downloads)
              ..[entryId] = 1.0;
            _state = _state.copyWith(downloads: finished);
            notifyListeners();

            await checkPackage(entryId);
          } catch (e) {
            debugPrint('Error registering downloaded media: $e');
            _cleanDownload(entryId);
          }
        }),
      );
    } catch (e) {
      debugPrint('Error starting download: $e');
      _cleanDownload(entryId);
    }
  }

  void _cleanDownload(String entryId) {
    _activeDownloads.remove(entryId)?.cancel();
    _downloadSubscriptions.remove(entryId)?.cancel();
    final downloads = Map<String, double>.of(_state.downloads)..remove(entryId);
    _state = _state.copyWith(downloads: downloads);
    notifyListeners();
  }

  void cancelDownload(String entryId) {
    _cleanDownload(entryId);
  }

  String? localPathFor(String entryId) => _localPaths[entryId];

  /// Generates a local learning package with listen-gen for a downloaded
  /// entry and imports the result into Core. Replaces the Core-side
  /// transcription job path.
  Future<void> startGeneration(String entryId) async {
    final mediaId = _mediaIds[entryId];
    final mediaPath = _localPaths[entryId];
    final entry = _state.entryById(entryId);
    if (mediaId == null || mediaPath == null || entry == null) return;

    final current = _state.generationStatusOf(entryId);
    if (current == ContentGenerationStatus.preparing ||
        current == ContentGenerationStatus.generating ||
        current == ContentGenerationStatus.importing ||
        current == ContentGenerationStatus.completed) {
      return;
    }

    final request = ContentPackageGenerationRequest(
      mediaPath: mediaPath,
      title: entry.title,
      mediaKind: 'video',
      durationMs: _mediaDurations[entryId] ?? entry.durationMs,
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
      final packages = Map<String, PackageStatus>.of(_state.packageStatuses)
        ..[entryId] = PackageStatus.available;
      _state = _state.copyWith(packageStatuses: packages);
      notifyListeners();
    } catch (error) {
      debugPrint('Error generating learning package: $error');
      if (!_disposed) {
        _setGenerationStatus(
          entryId,
          error is ListenGenProcessFailure && error.code == 'cancelled'
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
          selectedSourceId: 'custom_imports',
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
    for (final sub in _downloadSubscriptions.values) {
      sub.cancel();
    }
    _downloadSubscriptions.clear();
    for (final handle in _activeDownloads.values) {
      handle.cancel();
    }
    _activeDownloads.clear();
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
  Future<MediaItem> registerMedia(String path) async =>
      throw UnimplementedError();
}
