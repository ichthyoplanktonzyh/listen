import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/discovery_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../data/repositories/transcription_repository.dart';
import '../models/discovery.dart';
import '../models/media_download.dart';
import '../models/media_resolution.dart';
import '../models/types.dart';
import '../models/api_failure.dart';
import '../models/embedded_subtitle.dart';
import '../models/runtime_resources.dart';
import '../models/saved_vocabulary_count.dart';
import '../models/timeline.dart';

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
    Map<String, TranscriptionStatus> transcriptionStatuses = const {},
    Map<String, double> transcriptionProgress = const {},
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       downloads = Map.unmodifiable(downloads),
       packageStatuses = Map.unmodifiable(packageStatuses),
       transcriptionStatuses = Map.unmodifiable(transcriptionStatuses),
       transcriptionProgress = Map.unmodifiable(transcriptionProgress);

  final bool loading;
  final bool resolvingUrl;
  final bool resolveFailed;
  final List<MediaSource> sources;
  final String? selectedSourceId;
  final List<MediaEntry> entries;
  final String? selectedEntryId;
  final Map<String, double> downloads;
  final Map<String, PackageStatus> packageStatuses;
  final Map<String, TranscriptionStatus> transcriptionStatuses;
  final Map<String, double> transcriptionProgress;

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

  TranscriptionStatus transcriptionStatusOf(String entryId) =>
      transcriptionStatuses[entryId] ?? TranscriptionStatus.idle;

  double transcriptionProgressOf(String entryId) =>
      transcriptionProgress[entryId] ?? 0;

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
    Map<String, TranscriptionStatus>? transcriptionStatuses,
    Map<String, double>? transcriptionProgress,
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
    transcriptionStatuses: transcriptionStatuses ?? this.transcriptionStatuses,
    transcriptionProgress: transcriptionProgress ?? this.transcriptionProgress,
  );
}

/// Owns the media discovery presentation state.
final class DiscoveryViewModel extends ChangeNotifier {
  DiscoveryViewModel(
    this._repository, [
    MediaImportRepository? importRepository,
    TranscriptionRepository? transcriptionRepository,
    MediaLibraryRepository? mediaLibraryRepository,
  ]) : _importRepository =
           importRepository ?? const _FakeMediaImportRepository(),
       _transcriptionRepository =
           transcriptionRepository ?? const _FakeTranscriptionRepository(),
       _mediaLibraryRepository =
           mediaLibraryRepository ?? const _FakeMediaLibraryRepository();

  final DiscoveryRepository _repository;
  final MediaImportRepository _importRepository;
  final TranscriptionRepository _transcriptionRepository;
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
  final Map<String, StreamSubscription<double>> _downloadSubscriptions = {};
  final Map<String, MediaDownloadHandle> _activeDownloads = {};
  final List<MediaEntry> _customEntries = [];

  /// Transcription entry ids we started and are still waiting on. Polling
  /// keeps running while this set is non-empty, so a job that the core has
  /// not listed yet cannot be dropped by an idle poll.
  final Set<String> _pendingTranscriptions = {};

  Timer? _transcriptionPollTimer;
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

  Future<void> startTranscription(String entryId) async {
    final mediaId = _mediaIds[entryId];
    if (mediaId == null) return;

    final currentStatus = _state.transcriptionStatusOf(entryId);
    if (currentStatus == TranscriptionStatus.transcribing ||
        currentStatus == TranscriptionStatus.completed) {
      return;
    }

    try {
      final models = await _transcriptionRepository.models();
      final installed = models.where((m) => m.state == 'installed').toList();
      final modelId = installed.isNotEmpty
          ? installed.first.id
          : 'whisper-base';

      _pendingTranscriptions.add(entryId);

      final statuses = Map<String, TranscriptionStatus>.of(
        _state.transcriptionStatuses,
      )..[entryId] = TranscriptionStatus.preparing;
      _state = _state.copyWith(transcriptionStatuses: statuses);
      notifyListeners();

      await _transcriptionRepository.createJob(
        mediaId: mediaId,
        modelId: modelId,
        secondary: false,
        translate: false,
        force: true,
      );

      final runningStatuses = Map<String, TranscriptionStatus>.of(
        _state.transcriptionStatuses,
      )..[entryId] = TranscriptionStatus.transcribing;
      _state = _state.copyWith(transcriptionStatuses: runningStatuses);
      notifyListeners();

      _startTranscriptionPolling();
    } catch (e) {
      debugPrint('Error starting transcription: $e');
      _pendingTranscriptions.remove(entryId);
      final failedStatuses = Map<String, TranscriptionStatus>.of(
        _state.transcriptionStatuses,
      )..[entryId] = TranscriptionStatus.failed;
      _state = _state.copyWith(transcriptionStatuses: failedStatuses);
      notifyListeners();
    }
  }

  void cancelTranscription(String entryId) {
    final mediaId = _mediaIds[entryId];
    if (mediaId == null) return;
    _pendingTranscriptions.remove(entryId);

    unawaited(() async {
      try {
        final jobs = await _transcriptionRepository.jobs();
        final job = jobs.firstWhere((j) => j.mediaId == mediaId);
        await _transcriptionRepository.cancelJob(job.id);
      } catch (e) {
        debugPrint('Error cancelling transcription job: $e');
      }
      final statuses = Map<String, TranscriptionStatus>.of(
        _state.transcriptionStatuses,
      )..[entryId] = TranscriptionStatus.idle;
      _state = _state.copyWith(transcriptionStatuses: statuses);
      notifyListeners();
    }());
  }

  void _startTranscriptionPolling() {
    if (_transcriptionPollTimer != null) return;
    _transcriptionPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollJobs()),
    );
  }

  Future<void> _pollJobs() async {
    if (_disposed) return;
    try {
      final jobs = await _transcriptionRepository.jobs();
      var hasPending = false;

      final updatedStatuses = Map<String, TranscriptionStatus>.of(
        _state.transcriptionStatuses,
      );
      final updatedProgress = Map<String, double>.of(
        _state.transcriptionProgress,
      );
      final updatedPackages = Map<String, PackageStatus>.of(
        _state.packageStatuses,
      );

      for (final entryId in _pendingTranscriptions.toList()) {
        final mediaId = _mediaIds[entryId];
        if (mediaId == null) {
          _pendingTranscriptions.remove(entryId);
          continue;
        }

        final jobList = jobs.where((j) => j.mediaId == mediaId).toList();
        if (jobList.isEmpty) {
          // The core has not listed the job yet; keep polling instead of
          // dropping the transcription silently.
          hasPending = true;
          continue;
        }

        // Find the latest job by ID/creation time
        jobList.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
        final job = jobList.first;

        if (job.status == 'completed') {
          updatedStatuses[entryId] = TranscriptionStatus.completed;
          updatedProgress[entryId] = 1.0;
          updatedPackages[entryId] = PackageStatus.available;
          _pendingTranscriptions.remove(entryId);
        } else if (job.status == 'failed' || job.status == 'cancelled') {
          updatedStatuses[entryId] = TranscriptionStatus.failed;
          _pendingTranscriptions.remove(entryId);
        } else {
          updatedStatuses[entryId] = TranscriptionStatus.transcribing;
          updatedProgress[entryId] = job.phaseProgress / 100.0;
          hasPending = true;
        }
      }

      _state = _state.copyWith(
        transcriptionStatuses: updatedStatuses,
        transcriptionProgress: updatedProgress,
        packageStatuses: updatedPackages,
      );
      notifyListeners();

      if (!hasPending) {
        _transcriptionPollTimer?.cancel();
        _transcriptionPollTimer = null;
      }
    } catch (e) {
      debugPrint('Error polling transcription jobs: $e');
    }
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
    _transcriptionPollTimer?.cancel();
    _pendingTranscriptions.clear();
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

class _FakeTranscriptionRepository implements TranscriptionRepository {
  const _FakeTranscriptionRepository();
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  Future<List<TranscriptionProviderView>> providers() async => [];
  @override
  Future<List<TranscriptionModelView>> models() async => [];
  @override
  Future<List<TranscriptionJobView>> jobs() async => [];
  @override
  Future<void> createJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    required bool force,
  }) async {}
  @override
  Future<void> registerCustomModel(String path) async {}
  @override
  Future<void> installModel(String id) async {}
  @override
  Future<void> cancelModelInstall(String id) async {}
  @override
  Future<void> deleteModel(String id) async {}
  @override
  Future<void> cancelJob(String id) async {}
  @override
  Future<void> retryJob(String id) async {}
  @override
  Future<SubtitleTrack> readSubtitle(String id) async =>
      throw UnimplementedError();
  @override
  Future<String> exportSubtitleSrt(String id) async => '';
  @override
  Future<void> archiveJob(String id) async {}
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
