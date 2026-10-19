import 'dart:async';

import 'api_service.dart';

/// Stateless transport boundary for starting and owning the local core.
abstract interface class CoreTransportService {
  bool get isConnected;
  String? get diagnosticLogPath;
  Stream<Map<String, dynamic>> events();
  Future<void> connect();
  Future<List<String>> listLanguages();
  Future<void> saveProgress(String mediaId, Duration position);
  void requestStop();
  Future<void> close();
}

final class LocalCoreTransportService implements CoreTransportService {
  LocalApi? _api;

  /// Used only by the repository composition provider. Presentation code must
  /// never access the raw transport handle.
  LocalApi? get currentApi => _api;

  @override
  bool get isConnected => _api != null;

  LocalApi get _requiredApi =>
      _api ?? (throw StateError('Local core is unavailable'));

  @override
  String? get diagnosticLogPath => _api?.logPath;

  @override
  Future<void> connect() async {
    if (_api != null) return;
    _api = await LocalApi.connect();
  }

  @override
  Stream<Map<String, dynamic>> events() => _requiredApi.events();

  @override
  Future<List<String>> listLanguages() => _requiredApi.listLanguages();

  @override
  Future<void> saveProgress(String mediaId, Duration position) =>
      _requiredApi.saveProgress(mediaId, position);

  @override
  void requestStop() {
    final api = _api;
    _api = null;
    api?.requestStop();
  }

  @override
  Future<void> close() async {
    final api = _api;
    _api = null;
    await api?.close();
  }
}
