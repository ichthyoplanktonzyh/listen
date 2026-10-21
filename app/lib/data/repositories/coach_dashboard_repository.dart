import '../../models/api_failure.dart';
import '../../models/coach_dashboard.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

abstract interface class CoachDashboardRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);

  Future<CoachDashboard> loadDashboard({
    required int days,
  });

  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  });

  Future<MediaLibraryEntry> graduateMaterial(String mediaId);
  Future<MediaLibraryEntry> setMaterialIntent(String mediaId, String? intent);
  Future<List<ContentFitCalibrationSample>> calibrationSamples({
    String? language,
  });
}

class LocalCoachDashboardRepository implements CoachDashboardRepository {
  LocalCoachDashboardRepository(this._getApi);

  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Coach API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<CoachDashboard> loadDashboard({
    required int days,
  }) => _api.coachDashboard(days: days);

  @override
  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  }) => _api.coachEvidence(
    metric: metric,
    days: days,
    limit: limit,
    offset: offset,
  );

  @override
  Future<MediaLibraryEntry> graduateMaterial(String mediaId) =>
      _api.graduateCoachMaterial(mediaId);

  @override
  Future<MediaLibraryEntry> setMaterialIntent(String mediaId, String? intent) =>
      _api.setMediaTriageIntent(mediaId, intent);

  @override
  Future<List<ContentFitCalibrationSample>> calibrationSamples({
    String? language,
  }) => _api.contentFitCalibrationSamples(language: language);
}
