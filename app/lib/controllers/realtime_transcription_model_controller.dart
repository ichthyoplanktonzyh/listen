import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/transcription_repository.dart';
import '../models/api_failure.dart';
import '../models/runtime_resources.dart';

sealed class RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelOutcome();
}

final class RealtimeTranscriptionModelSelected
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelSelected(this.modelId);

  final String modelId;
}

final class RealtimeTranscriptionModelNeedsDownload
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelNeedsDownload(this.model);

  final TranscriptionModelView model;
}

final class RealtimeTranscriptionModelUnavailable
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelUnavailable();
}

final class RealtimeTranscriptionModelFailure
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelFailure(this.failure);

  final ApiFailure failure;
}

enum RealtimeTranscriptionModelInstallStatus {
  idle,
  awaitingConsent,
  starting,
  installing,
  cancelling,
  failed,
  cancelled,
  installed,
}

@immutable
final class RealtimeTranscriptionModelInstallState {
  const RealtimeTranscriptionModelInstallState({
    required this.status,
    this.model,
    this.failure,
  });

  const RealtimeTranscriptionModelInstallState.idle()
    : status = RealtimeTranscriptionModelInstallStatus.idle,
      model = null,
      failure = null;

  final RealtimeTranscriptionModelInstallStatus status;
  final TranscriptionModelView? model;
  final ApiFailure? failure;

  double? get progress {
    final item = model;
    if (item == null || item.sizeBytes <= 0 || item.installedBytes <= 0) {
      return null;
    }
    return (item.installedBytes / item.sizeBytes).clamp(0, 1).toDouble();
  }
}

/// Selects or installs a compatible local transcription model for realtime
/// conversation. Installation is only started after the learner confirms in
/// the prompt; Core remains authoritative for progress and verified state.
final class RealtimeTranscriptionModelController extends ChangeNotifier {
  RealtimeTranscriptionModelController(
    this._repository, {
    this._pollInterval = const Duration(seconds: 1),
    this._maxPollAttempts = 600,
  });

  static const preferredMultilingualModelId = 'whisper.cpp:base@main';

  final TranscriptionRepository _repository;
  final Duration _pollInterval;
  final int _maxPollAttempts;

  RealtimeTranscriptionModelInstallState _installState =
      const RealtimeTranscriptionModelInstallState.idle();
  RealtimeTranscriptionModelInstallState get installState => _installState;

  String? _language;
  String? _activeModelId;
  Future<void>? _installRequest;
  Future<void>? _cancelFuture;
  Future<RealtimeTranscriptionModelOutcome>? _installFuture;
  bool _installRequested = false;
  bool _cancelRequested = false;
  bool _cancelCompleted = false;
  bool _disposed = false;

  Future<RealtimeTranscriptionModelOutcome> selectForLanguage(
    String language,
  ) async {
    _language = language;
    try {
      final models = await _repository.models();
      if (_disposed) return const RealtimeTranscriptionModelUnavailable();
      final selected = _firstInstalledCompatible(models, language);
      if (selected != null) {
        _markInstalled(selected);
        return RealtimeTranscriptionModelSelected(selected.id);
      }

      final candidate = _installationCandidate(models, language);
      if (candidate == null) {
        _setInstallState(const RealtimeTranscriptionModelInstallState.idle());
        return const RealtimeTranscriptionModelUnavailable();
      }
      _activeModelId = candidate.id;
      // Even if Core reports a download already in flight, this entry point
      // requires an explicit click before joining it or starting a replacement
      // if it disappears before the consent prompt is accepted.
      _installRequested = false;
      _cancelRequested = false;
      _cancelCompleted = false;
      _setInstallState(
        RealtimeTranscriptionModelInstallState(
          status: RealtimeTranscriptionModelInstallStatus.awaitingConsent,
          model: candidate,
        ),
      );
      return RealtimeTranscriptionModelNeedsDownload(candidate);
    } catch (error) {
      final failure = _repository.failureDetail(error);
      _setInstallState(
        RealtimeTranscriptionModelInstallState(
          status: RealtimeTranscriptionModelInstallStatus.failed,
          failure: failure,
        ),
      );
      return RealtimeTranscriptionModelFailure(failure);
    }
  }

  /// Starts the offered model install, or joins an install already reported by
  /// Core. Returns a selected model only after Core reports it as installed.
  Future<RealtimeTranscriptionModelOutcome> installOfferedModel() {
    if (_disposed) {
      return Future.value(const RealtimeTranscriptionModelUnavailable());
    }
    final active = _installFuture;
    if (active != null) return active;
    final future = _installOfferedModel();
    _installFuture = future;
    return future.whenComplete(() {
      if (identical(_installFuture, future)) _installFuture = null;
    });
  }

  Future<RealtimeTranscriptionModelOutcome> _installOfferedModel() async {
    final language = _language;
    final modelId = _activeModelId;
    if (language == null || modelId == null) {
      return const RealtimeTranscriptionModelUnavailable();
    }

    _cancelRequested = false;
    _cancelCompleted = false;
    _setInstallState(
      RealtimeTranscriptionModelInstallState(
        status: RealtimeTranscriptionModelInstallStatus.starting,
        model: _installState.model,
      ),
    );

    try {
      // A model may have completed while the consent sheet was open. Check
      // again before sending the install command to avoid a redundant request.
      final latest = await _repository.models();
      if (_cancelRequested || _disposed) {
        return const RealtimeTranscriptionModelUnavailable();
      }
      final compatible = _firstInstalledCompatible(latest, language);
      if (compatible != null) {
        _markInstalled(compatible);
        return RealtimeTranscriptionModelSelected(compatible.id);
      }

      final current = _modelById(latest, modelId);
      if (current == null || !isCompatible(current, language)) {
        _setInstallState(const RealtimeTranscriptionModelInstallState.idle());
        return const RealtimeTranscriptionModelUnavailable();
      }
      if (_isInstalled(current)) {
        _markInstalled(current);
        return RealtimeTranscriptionModelSelected(current.id);
      }

      if (current.state == 'installing') {
        _installRequested = true;
        _setInstallState(
          RealtimeTranscriptionModelInstallState(
            status: RealtimeTranscriptionModelInstallStatus.installing,
            model: current,
          ),
        );
      } else if (current.state == 'downloadable' || current.state == 'failed') {
        _installRequested = true;
        final request = _repository.installModel(current.id);
        _installRequest = request;
        try {
          await request;
        } finally {
          if (identical(_installRequest, request)) _installRequest = null;
        }
        if (_cancelRequested) {
          await _cancelActiveInstall();
          return const RealtimeTranscriptionModelUnavailable();
        }
      } else {
        return const RealtimeTranscriptionModelUnavailable();
      }

      return await _pollUntilTerminal(language, modelId);
    } catch (error) {
      if (_cancelRequested) {
        await _cancelActiveInstall();
        return const RealtimeTranscriptionModelUnavailable();
      }
      final failure = _repository.failureDetail(error);
      _setInstallState(
        RealtimeTranscriptionModelInstallState(
          status: RealtimeTranscriptionModelInstallStatus.failed,
          model: _installState.model,
          failure: failure,
        ),
      );
      return RealtimeTranscriptionModelFailure(failure);
    }
  }

  Future<RealtimeTranscriptionModelOutcome> _pollUntilTerminal(
    String language,
    String modelId,
  ) async {
    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      await Future<void>.delayed(_pollInterval);
      if (_cancelRequested) {
        await _cancelActiveInstall();
        return const RealtimeTranscriptionModelUnavailable();
      }

      final models = await _repository.models();
      if (_cancelRequested || _disposed) {
        await _cancelActiveInstall();
        return const RealtimeTranscriptionModelUnavailable();
      }

      final compatible = _firstInstalledCompatible(models, language);
      if (compatible != null) {
        _markInstalled(compatible);
        return RealtimeTranscriptionModelSelected(compatible.id);
      }

      final current = _modelById(models, modelId);
      if (current == null) break;
      if (current.state == 'installing') {
        _setInstallState(
          RealtimeTranscriptionModelInstallState(
            status: RealtimeTranscriptionModelInstallStatus.installing,
            model: current,
          ),
        );
        continue;
      }
      if (current.state == 'failed') {
        final failure = ApiFailure(
          raw: current.error ?? 'model install failed',
        );
        _installRequested = false;
        _setInstallState(
          RealtimeTranscriptionModelInstallState(
            status: RealtimeTranscriptionModelInstallStatus.failed,
            model: current,
            failure: failure,
          ),
        );
        return RealtimeTranscriptionModelFailure(failure);
      }
      if (_isInstalled(current) && isCompatible(current, language)) {
        _markInstalled(current);
        return RealtimeTranscriptionModelSelected(current.id);
      }
      if (current.state == 'downloadable') {
        _installRequested = false;
        break;
      }
    }

    if (_cancelRequested) {
      await _cancelActiveInstall();
      return const RealtimeTranscriptionModelUnavailable();
    }
    final failure = ApiFailure(raw: 'model install did not complete');
    _setInstallState(
      RealtimeTranscriptionModelInstallState(
        status: RealtimeTranscriptionModelInstallStatus.failed,
        model: _installState.model,
        failure: failure,
      ),
    );
    return RealtimeTranscriptionModelFailure(failure);
  }

  Future<void> cancelInstall() async {
    if (!_installRequested || _cancelCompleted) {
      _cancelRequested = true;
      if (_installState.status !=
              RealtimeTranscriptionModelInstallStatus.idle &&
          _installState.status !=
              RealtimeTranscriptionModelInstallStatus.installed) {
        _setInstallState(
          RealtimeTranscriptionModelInstallState(
            status: RealtimeTranscriptionModelInstallStatus.cancelled,
            model: _installState.model,
          ),
        );
      }
      return;
    }
    _cancelRequested = true;
    _setInstallState(
      RealtimeTranscriptionModelInstallState(
        status: RealtimeTranscriptionModelInstallStatus.cancelling,
        model: _installState.model,
      ),
    );
    await _cancelActiveInstall();
  }

  Future<void> _cancelActiveInstall() {
    final existing = _cancelFuture;
    if (existing != null) return existing;
    final modelId = _activeModelId;
    if (modelId == null || !_installRequested || _cancelCompleted) {
      return Future<void>.value();
    }
    final cancellation = () async {
      try {
        final request = _installRequest;
        if (request != null) {
          try {
            await request;
          } catch (_) {
            // The cancel endpoint remains the authority for an interrupted
            // install even when the original POST failed.
          }
        }
        await _repository.cancelModelInstall(modelId);
        _cancelCompleted = true;
        if (!_disposed) {
          _setInstallState(
            RealtimeTranscriptionModelInstallState(
              status: RealtimeTranscriptionModelInstallStatus.cancelled,
              model: _installState.model,
            ),
          );
        }
      } catch (error) {
        // Cancellation is best effort when Core disappears. Keep the command
        // owned so dispose can retry, but never let the close path or the
        // install Future escape with an unhandled exception.
        if (!_disposed) {
          _setInstallState(
            RealtimeTranscriptionModelInstallState(
              status: RealtimeTranscriptionModelInstallStatus.failed,
              model: _installState.model,
              failure: _repository.failureDetail(error),
            ),
          );
        }
      }
    }();
    _cancelFuture = cancellation;
    return cancellation.whenComplete(() {
      if (identical(_cancelFuture, cancellation)) _cancelFuture = null;
    });
  }

  static bool isCompatible(TranscriptionModelView model, String language) {
    if (!model.englishOnly) return true;
    final normalized = language.trim().replaceAll('_', '-').toLowerCase();
    final primaryLanguage = normalized.split('-').first;
    return primaryLanguage == 'en';
  }

  static TranscriptionModelView? _firstInstalledCompatible(
    List<TranscriptionModelView> models,
    String language,
  ) {
    for (final model in models) {
      if (_isInstalled(model) && isCompatible(model, language)) return model;
    }
    return null;
  }

  static TranscriptionModelView? _installationCandidate(
    List<TranscriptionModelView> models,
    String language,
  ) {
    final compatible = models.where(
      (model) =>
          isCompatible(model, language) &&
          (model.state == 'downloadable' ||
              model.state == 'failed' ||
              model.state == 'installing'),
    );
    for (final model in compatible) {
      if (model.id == preferredMultilingualModelId) return model;
    }
    final alternatives = compatible.toList()
      ..sort((left, right) => left.sizeBytes.compareTo(right.sizeBytes));
    return alternatives.isEmpty ? null : alternatives.first;
  }

  static TranscriptionModelView? _modelById(
    List<TranscriptionModelView> models,
    String id,
  ) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  static bool _isInstalled(TranscriptionModelView model) =>
      model.state == 'installed' || model.state == 'custom';

  void _setInstallState(RealtimeTranscriptionModelInstallState next) {
    _installState = next;
    if (!_disposed) notifyListeners();
  }

  void _markInstalled(TranscriptionModelView model) {
    _installRequested = false;
    _cancelRequested = false;
    _cancelCompleted = true;
    _activeModelId = null;
    _setInstallState(
      RealtimeTranscriptionModelInstallState(
        status: RealtimeTranscriptionModelInstallStatus.installed,
        model: model,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_installRequested && !_cancelCompleted) {
      _cancelRequested = true;
      unawaited(_cancelActiveInstall().catchError((Object _) {}));
    }
    super.dispose();
  }
}
