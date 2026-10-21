part of '../api_service.dart';

extension CoachDashboardApi on LocalApi {
  Future<CoachDashboard> coachDashboard({
    int days = 7,
  }) async {
    final query = Uri(queryParameters: {'days': '$days'}).query;
    return CoachDashboard.fromJson(
      (await _request('GET', '/v1/coach/dashboard?$query'))
          as Map<String, dynamic>,
    );
  }

  Future<List<CoachEvidenceItem>> coachEvidence({
    required String metric,
    int days = 7,
    int limit = 20,
    int offset = 0,
  }) async {
    final query = Uri(
      queryParameters: {
        'metric': metric,
        'days': '$days',
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final values =
        (await _request('GET', '/v1/coach/evidence?$query')) as List<dynamic>;
    return values
        .map(
          (value) => CoachEvidenceItem.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<MediaLibraryEntry> graduateCoachMaterial(String mediaId) async =>
      MediaLibraryEntry.fromJson(
        (await _request(
              'POST',
              '/v1/coach/materials/${Uri.encodeComponent(mediaId)}/graduate',
              const {},
            ))
            as Map<String, dynamic>,
      );

  Future<List<ContentFitCalibrationSample>> contentFitCalibrationSamples({
    String? language,
  }) async {
    final query = Uri(queryParameters: {'language': ?language});
    final suffix = query.query.isEmpty ? '' : '?${query.query}';
    final values =
        (await _request('GET', '/v1/content-fit/calibration-samples$suffix'))
            as List<dynamic>;
    return values
        .map(
          (value) => ContentFitCalibrationSample.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }
}
