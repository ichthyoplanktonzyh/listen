import '../../models/api_failure.dart';
import '../../services/api_service.dart' show describeApiFailure;
import '../../services/core_transport_service.dart';

abstract interface class CoreSessionRepository {
  bool get isConnected;
  String? get diagnosticLogPath;
  ApiFailure failureDetail(Object error);
  Future<void> connect();
  Stream<Map<String, dynamic>> events();
  Future<List<String>> listLanguages();
  Future<void> saveProgress(String mediaId, Duration position);
  void requestStop();
  Future<void> close();
}

final class LocalCoreSessionRepository implements CoreSessionRepository {
  const LocalCoreSessionRepository(this._service);

  final CoreTransportService _service;

  @override
  bool get isConnected => _service.isConnected;
  @override
  String? get diagnosticLogPath => _service.diagnosticLogPath;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<void> connect() => _service.connect();
  @override
  Stream<Map<String, dynamic>> events() => _service.events();
  @override
  Future<List<String>> listLanguages() => _service.listLanguages();
  @override
  Future<void> saveProgress(String mediaId, Duration position) =>
      _service.saveProgress(mediaId, position);
  @override
  void requestStop() => _service.requestStop();
  @override
  Future<void> close() => _service.close();
}
