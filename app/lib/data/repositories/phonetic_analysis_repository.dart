import '../../models/api_failure.dart';
import '../../models/runtime_resources.dart';
import '../../services/api_service.dart';

abstract interface class PhoneticAnalysisRepository {
  ApiFailure failureDetail(Object error);
  Future<List<PhoneticProviderView>> providers();
  Future<List<PhoneticModelView>> models();
  Future<List<PhoneticJobView>> jobs();
  Future<void> installModel(String id);
  Future<void> cancelJob(String id);
  Future<void> retryJob(String id);
  Future<void> deleteJob(String id);
  Future<void> clearTerminalJobs();
}

final class LocalPhoneticAnalysisRepository
    implements PhoneticAnalysisRepository {
  const LocalPhoneticAnalysisRepository(this._api);
  final LocalApi _api;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<List<PhoneticProviderView>> providers() =>
      _api.phoneticAnalysisProviders();
  @override
  Future<List<PhoneticModelView>> models() => _api.phoneticAnalysisModels();
  @override
  Future<List<PhoneticJobView>> jobs() => _api.phoneticAnalysisJobs();
  @override
  Future<void> installModel(String id) async {
    await _api.installPhoneticAnalysisModel(id);
  }

  @override
  Future<void> cancelJob(String id) async {
    await _api.cancelPhoneticAnalysisJob(id);
  }

  @override
  Future<void> retryJob(String id) async {
    await _api.retryPhoneticAnalysisJob(id);
  }

  @override
  Future<void> deleteJob(String id) => _api.deletePhoneticAnalysisJob(id);
  @override
  Future<void> clearTerminalJobs() => _api.clearTerminalPhoneticAnalysisJobs();
}
