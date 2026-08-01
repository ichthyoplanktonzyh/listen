import '../../models/coach_dashboard.dart';
import '../../services/api_service.dart';

/// Data boundary for the coach dashboard and its inline actions.
abstract interface class CoachDashboardRepository {
  Future<CoachDashboard> loadDashboard({
    required int days,
    required String language,
  });

  Future<void> graduateMaterial(String mediaId);

  Future<void> setMaterialIntent(String mediaId, String? intent);

  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  });
}

class LocalCoachDashboardRepository implements CoachDashboardRepository {
  LocalCoachDashboardRepository(this._api);

  final LocalApi _api;

  @override
  Future<CoachDashboard> loadDashboard({
    required int days,
    required String language,
  }) => _api.coachDashboard(days: days, language: language);

  @override
  Future<void> graduateMaterial(String mediaId) =>
      _api.graduateCoachMaterial(mediaId);

  @override
  Future<void> setMaterialIntent(String mediaId, String? intent) async {
    await _api.setMediaTriageIntent(mediaId, intent);
  }

  @override
  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  }) => _api.coachEvidence(metric, days: days, limit: limit, offset: offset);
}
