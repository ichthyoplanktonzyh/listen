import 'package:flutter/foundation.dart';

import '../data/repositories/learning_assets_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../models/api_failure.dart';
import '../models/embedded_subtitle.dart';
import '../player_adapter.dart';
import 'download_controller.dart';
import 'learning_assets_view_models.dart';
import 'media_session_coordinator.dart';
import 'player_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

enum MediaImportPhase {
  idle,
  unavailable,
  empty,
  resolving,
  downloading,
  inspecting,
  extracting,
  failed,
}

@immutable
class MediaImportFlowState {
  const MediaImportFlowState({
    this.phase = MediaImportPhase.idle,
    this.failure,
  });

  final MediaImportPhase phase;
  final ApiFailure? failure;
}

sealed class MediaImportOutcome {
  const MediaImportOutcome();
}

final class MediaImportSucceeded extends MediaImportOutcome {
  const MediaImportSucceeded([this.path]);
  final String? path;
}

final class MediaImportCancelled extends MediaImportOutcome {
  const MediaImportCancelled();
}

final class MediaImportUnavailable extends MediaImportOutcome {
  const MediaImportUnavailable();
}

final class MediaImportEmpty extends MediaImportOutcome {
  const MediaImportEmpty();
}

final class MediaImportFailed extends MediaImportOutcome {
  const MediaImportFailed(this.failure);
  final ApiFailure failure;
}

final class EmbeddedSubtitleChoices extends MediaImportOutcome {
  EmbeddedSubtitleChoices(List<EmbeddedSubtitle> values)
    : values = List.unmodifiable(values);
  final List<EmbeddedSubtitle> values;
}

class MediaImportFlowController extends ChangeNotifier {
  MediaImportFlowController(
    this._repository,
    this._adapter,
    this._mediaSession,
    this._backendAvailable,
    this._isMediaPath, {
    required PlayerController playerController,
    required SubtitleController subtitleController,
    required DownloadController downloadController,
  }) : _player = playerController,
       _subtitle = subtitleController,
       _downloads = downloadController,
       super();

  final MediaImportRepository _repository;
  final DesktopPlayerAdapter _adapter;
  final PlayerController _player;
  final SubtitleController _subtitle;
  final DownloadController _downloads;
  final MediaSessionCoordinator _mediaSession;
  final bool Function() _backendAvailable;
  final bool Function(String path) _isMediaPath;

  MediaImportFlowState _state = const MediaImportFlowState();
  int _onlineGeneration = 0;
  int _downloadGeneration = 0;
  int _embeddedGeneration = 0;
  bool _disposed = false;
  MediaImportFlowState get state => _state;

  void reportStatus(
    String value, {
    bool error = false,
    bool playback = false,
    ApiFailure? failure,
  }) => _player.setStatus(
    value,
    error: error,
    playback: playback,
    failure: failure,
  );

  Future<MediaImportOutcome> playOnline(String pageUrl) async {
    final generation = ++_onlineGeneration;
    _publish(const MediaImportFlowState(phase: MediaImportPhase.resolving));
    try {
      final resolved = await _repository.resolveOnlineMedia(pageUrl);
      if (_stale(generation, _onlineGeneration)) {
        return const MediaImportCancelled();
      }
      await _adapter.open(resolved);
      if (_stale(generation, _onlineGeneration)) {
        return const MediaImportCancelled();
      }
      // The online clear is an external media switch: the session's material
      // leaves synchronously and every in-flight material resolve or retention
      // result from the previous session is invalidated before the player is
      // cleared.
      _mediaSession.beginExternalMediaSwitch();
      _player.clearMedia();
      _player.setMediaPath(pageUrl);
      _subtitle.setPrimaryTrack(null);
      _subtitle.setSecondaryTrack(null);
      _subtitle.setCurrentPrimaryCue(null);
      _subtitle.setCurrentSecondaryCue(null);
      _subtitle.clearSpeechEnhancements();
      _publish(const MediaImportFlowState());
      return const MediaImportSucceeded();
    } catch (error) {
      if (_stale(generation, _onlineGeneration)) {
        return const MediaImportCancelled();
      }
      return _failed(error);
    }
  }

  Future<MediaImportOutcome> startDownload(
    String pageUrl, {
    required String confirmButtonText,
    required String Function(String path) completedStatus,
    required String failedStatus,
  }) async {
    final generation = ++_downloadGeneration;
    try {
      final directory = await _repository.pickDownloadDirectory(
        confirmButtonText: confirmButtonText,
      );
      if (_stale(generation, _downloadGeneration)) {
        return const MediaImportCancelled();
      }
      if (directory == null) return const MediaImportCancelled();
      _downloads.starting();
      _publish(const MediaImportFlowState(phase: MediaImportPhase.downloading));
      final download = await _repository.downloadOnlineMedia(
        pageUrl,
        directory,
      );
      if (_stale(generation, _downloadGeneration)) {
        download.cancel();
        return const MediaImportCancelled();
      }
      _downloads.attach(
        progress: download.progress,
        completed: download.completed,
        cancel: download.cancel,
        onCompleted: (path) {
          if (!_stale(generation, _downloadGeneration)) {
            reportStatus(completedStatus(path));
          }
        },
        onFailed: (failure) {
          if (!_stale(generation, _downloadGeneration)) {
            reportStatus(failedStatus, error: true, failure: failure);
          }
        },
      );
      return const MediaImportSucceeded();
    } catch (error) {
      if (_stale(generation, _downloadGeneration)) {
        return const MediaImportCancelled();
      }
      final outcome = _failed(error);
      _downloads.fail(outcome.failure);
      return outcome;
    }
  }

  Future<MediaImportOutcome> inspectEmbedded() async {
    final generation = ++_embeddedGeneration;
    final path = _player.mediaPath;
    if (path == null ||
        !_isMediaPath(path) ||
        _player.mediaId == null ||
        !_backendAvailable()) {
      _publish(const MediaImportFlowState(phase: MediaImportPhase.unavailable));
      return const MediaImportUnavailable();
    }
    _publish(const MediaImportFlowState(phase: MediaImportPhase.inspecting));
    try {
      final values = await _repository.probeSubtitles(path);
      if (_stale(generation, _embeddedGeneration)) {
        return const MediaImportCancelled();
      }
      if (values.isEmpty) {
        _publish(const MediaImportFlowState(phase: MediaImportPhase.empty));
        return const MediaImportEmpty();
      }
      _publish(const MediaImportFlowState());
      return EmbeddedSubtitleChoices(values);
    } catch (error) {
      if (_stale(generation, _embeddedGeneration)) {
        return const MediaImportCancelled();
      }
      return _failed(error);
    }
  }

  Future<MediaImportOutcome> extractEmbedded(
    EmbeddedSubtitle subtitle, {
    required bool secondary,
  }) async {
    final generation = ++_embeddedGeneration;
    final path = _player.mediaPath;
    if (path == null || !_isMediaPath(path)) {
      _publish(const MediaImportFlowState(phase: MediaImportPhase.unavailable));
      return const MediaImportUnavailable();
    }
    _publish(const MediaImportFlowState(phase: MediaImportPhase.extracting));
    try {
      final extracted = await _repository.extractTextSubtitle(path, subtitle);
      if (_stale(generation, _embeddedGeneration)) {
        return const MediaImportCancelled();
      }
      await _mediaSession.openSubtitlePath(extracted, secondary: secondary);
      if (_stale(generation, _embeddedGeneration)) {
        return const MediaImportCancelled();
      }
      _publish(const MediaImportFlowState());
      return MediaImportSucceeded(extracted);
    } catch (error) {
      if (_stale(generation, _embeddedGeneration)) {
        return const MediaImportCancelled();
      }
      return _failed(error);
    }
  }

  MediaImportFailed _failed(Object error) {
    final failure = _repository.failureDetail(error);
    _publish(
      MediaImportFlowState(phase: MediaImportPhase.failed, failure: failure),
    );
    return MediaImportFailed(failure);
  }

  void _publish(MediaImportFlowState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  bool _stale(int generation, int current) =>
      _disposed || generation != current;

  @override
  void dispose() {
    _disposed = true;
    _onlineGeneration++;
    _downloadGeneration++;
    _embeddedGeneration++;
    super.dispose();
  }
}

sealed class OpenSubtitlesPreparation {
  const OpenSubtitlesPreparation();
}

final class OpenSubtitlesUnavailable extends OpenSubtitlesPreparation {
  const OpenSubtitlesUnavailable();
}

final class OpenSubtitlesNoMedia extends OpenSubtitlesPreparation {
  const OpenSubtitlesNoMedia();
}

final class OpenSubtitlesNeedsApiKey extends OpenSubtitlesPreparation {
  const OpenSubtitlesNeedsApiKey();
}

final class OpenSubtitlesReady extends OpenSubtitlesPreparation {
  const OpenSubtitlesReady(this.viewModel);
  final OpenSubtitlesSearchViewModel viewModel;
}

final class OpenSubtitlesSetupFailed extends OpenSubtitlesPreparation {
  const OpenSubtitlesSetupFailed(this.failure);
  final ApiFailure failure;
}

class OpenSubtitlesFlowController {
  OpenSubtitlesFlowController(
    this._repository,
    this._mediaSession, {
    required PlayerController playerController,
    required SettingsController settingsController,
  }) : _player = playerController,
       _settings = settingsController;

  final LearningAssetsRepository? _repository;
  final PlayerController _player;
  final SettingsController _settings;
  final MediaSessionCoordinator _mediaSession;

  String get apiKey => _settings.openSubtitlesApiKey;

  OpenSubtitlesPreparation prepare() {
    final repository = _repository;
    if (repository == null) return const OpenSubtitlesUnavailable();
    if (_player.mediaId == null) return const OpenSubtitlesNoMedia();
    if (apiKey.isEmpty) return const OpenSubtitlesNeedsApiKey();
    return OpenSubtitlesReady(
      OpenSubtitlesSearchViewModel(
        repository,
        apiKey: apiKey,
        initialTitle: _player.mediaTitle ?? '',
        initialFilename: _player.mediaPath == null
            ? ''
            : _player.mediaPath!.split(RegExp(r'[/\\]')).last,
        mediaPath: _player.mediaPath,
      ),
    );
  }

  Future<OpenSubtitlesPreparation> configureApiKey(String value) async {
    try {
      await _settings.update(
        _settings.settings.copyWith(openSubtitlesApiKey: value),
      );
      return prepare();
    } catch (error) {
      final repository = _repository;
      final failure =
          repository?.failureDetail(error) ??
          ApiFailure(message: 'The operation failed.', raw: error.toString());
      return OpenSubtitlesSetupFailed(failure);
    }
  }

  Future<void> openDownloaded(String path, {required bool secondary}) =>
      _mediaSession.openSubtitlePath(path, secondary: secondary);

  void reportStatus(String value, {bool error = false, ApiFailure? failure}) =>
      _player.setStatus(value, error: error, failure: failure);
}
