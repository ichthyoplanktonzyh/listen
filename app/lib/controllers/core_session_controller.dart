import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/core_session_repository.dart';
import '../models/api_failure.dart';
import '../models/backend_event.dart';

enum CoreConnectionStatus { disconnected, connecting, connected, failed }

@immutable
final class CoreSessionState {
  CoreSessionState({
    this.status = CoreConnectionStatus.disconnected,
    this.failure,
    this.connectionGeneration = 0,
    List<String> availableLanguages = const [],
  }) : availableLanguages = List.unmodifiable(availableLanguages);

  final CoreConnectionStatus status;
  final ApiFailure? failure;
  final int connectionGeneration;
  final List<String> availableLanguages;

  bool get isConnected => status == CoreConnectionStatus.connected;
  bool get isConnecting => status == CoreConnectionStatus.connecting;
}

/// Owns the local core lifecycle and exposes only immutable state and typed
/// backend events to presentation.
final class CoreSessionController extends ChangeNotifier {
  factory CoreSessionController({
    required CoreSessionRepository repository,
    required String? Function() currentMediaId,
    required Duration Function() currentPosition,
    required FutureOr<void> Function() onProgressTick,
    Duration progressInterval = const Duration(seconds: 5),
    Duration finalSaveTimeout = const Duration(seconds: 2),
  }) => CoreSessionController._(
    repository,
    currentMediaId,
    currentPosition,
    onProgressTick,
    progressInterval,
    finalSaveTimeout,
  );

  CoreSessionController._(
    this._repository,
    this._currentMediaId,
    this._currentPosition,
    this._onProgressTick,
    this.progressInterval,
    this.finalSaveTimeout,
  );

  final CoreSessionRepository _repository;
  final String? Function() _currentMediaId;
  final Duration Function() _currentPosition;
  final FutureOr<void> Function() _onProgressTick;
  final Duration progressInterval;
  final Duration finalSaveTimeout;
  final StreamController<BackendEvent> _events =
      StreamController<BackendEvent>.broadcast(sync: true);

  CoreSessionState _state = CoreSessionState();
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _progressTimer;
  int _operationGeneration = 0;
  bool _disposed = false;
  Future<void>? _shutdownFuture;

  CoreSessionState get state => _state;
  Stream<BackendEvent> get events => _events.stream;
  bool get isAvailable => _repository.isConnected;
  String? get diagnosticLogPath => _repository.diagnosticLogPath;

  Future<void> connect() async {
    if (_disposed || _state.isConnected || _state.isConnecting) return;
    final generation = ++_operationGeneration;
    _publish(
      CoreSessionState(
        status: CoreConnectionStatus.connecting,
        connectionGeneration: _state.connectionGeneration,
        availableLanguages: _state.availableLanguages,
      ),
    );
    try {
      await _repository.connect();
      if (!_isCurrent(generation)) {
        await _repository.close();
        return;
      }
      await _eventSubscription?.cancel();
      _eventSubscription = _repository.events().listen(
        _handleRawEvent,
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(generation)) return;
          _publish(
            CoreSessionState(
              status: CoreConnectionStatus.failed,
              failure: _repository.failureDetail(error),
              connectionGeneration: _state.connectionGeneration,
              availableLanguages: _state.availableLanguages,
            ),
          );
          _progressTimer?.cancel();
          _progressTimer = null;
        },
        onDone: () {
          if (!_isCurrent(generation) || !_state.isConnected) return;
          _progressTimer?.cancel();
          _progressTimer = null;
          _publish(
            CoreSessionState(
              connectionGeneration: _state.connectionGeneration,
              availableLanguages: _state.availableLanguages,
            ),
          );
        },
        cancelOnError: true,
      );
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(
        progressInterval,
        (_) => unawaited(_saveProgress()),
      );
      final connectionGeneration = _state.connectionGeneration + 1;
      _publish(
        CoreSessionState(
          status: CoreConnectionStatus.connected,
          connectionGeneration: connectionGeneration,
          availableLanguages: _state.availableLanguages,
        ),
      );
      unawaited(_loadLanguages(generation, connectionGeneration));
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _publish(
        CoreSessionState(
          status: CoreConnectionStatus.failed,
          failure: _repository.failureDetail(error),
          connectionGeneration: _state.connectionGeneration,
          availableLanguages: _state.availableLanguages,
        ),
      );
    }
  }

  Future<void> _loadLanguages(
    int operationGeneration,
    int connectionGeneration,
  ) async {
    try {
      final languages = await _repository.listLanguages();
      if (!_isCurrent(operationGeneration) || !_state.isConnected) return;
      _publish(
        CoreSessionState(
          status: CoreConnectionStatus.connected,
          connectionGeneration: connectionGeneration,
          availableLanguages: languages,
        ),
      );
    } catch (_) {
      // Language discovery was best-effort in the original lifecycle.
    }
  }

  void _handleRawEvent(Map<String, dynamic> raw) {
    if (_disposed || _events.isClosed) return;
    _events.add(BackendEvent.fromJson(raw));
  }

  Future<void> _saveProgress() async {
    if (!_state.isConnected) return;
    final mediaId = _currentMediaId();
    if (mediaId == null) return;
    final pendingSave = _repository
        .saveProgress(mediaId, _currentPosition())
        .catchError((Object _) {});
    try {
      await _onProgressTick();
    } catch (_) {
      // Recent-media bookkeeping must not create an unhandled timer error.
    }
    await pendingSave;
  }

  /// Saves the final position and only then asks the sidecar to stop. Repeated
  /// calls share the same future so dispose and explicit shutdown cannot race.
  Future<void> shutdown() {
    final mediaId = _currentMediaId();
    final position = _currentPosition();
    return _shutdownFuture ??= _shutdown(mediaId, position);
  }

  Future<void> _shutdown(String? mediaId, Duration position) async {
    ++_operationGeneration;
    _progressTimer?.cancel();
    _progressTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!_repository.isConnected) return;
    try {
      if (mediaId != null) {
        await _repository
            .saveProgress(mediaId, position)
            .timeout(finalSaveTimeout);
      }
    } catch (_) {
      // Shutdown must continue even if the final progress write fails/times out.
    } finally {
      _repository.requestStop();
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _operationGeneration;

  void _publish(CoreSessionState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_operationGeneration;
    _progressTimer?.cancel();
    unawaited(shutdown());
    unawaited(_events.close());
    super.dispose();
  }
}
