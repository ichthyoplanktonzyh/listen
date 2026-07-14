part of '../api_service.dart';

// Word/chunk/sense-group/phone timeline resources.
// Split out of api_service.dart (mechanical decomposition).

extension TimelinesApi on LocalApi {
  Future<List<Map<String, dynamic>>> trackWordTimings(String trackId) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timings',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trackWordTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> wordTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/word-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> createTrackWordTimeline(
    String trackId,
    Map<String, dynamic> payload,
  ) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines',
            payload,
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activateWordTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/word-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackChunkTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> chunkTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> generateChunkTimeline(
    String trackId, {
    String status = 'candidate',
  }) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-timelines',
            {'status': status},
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activateChunkTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveChunkTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deleteChunkTimeline(String timelineId) async =>
      (await _request(
            'DELETE',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackSenseGroupAnalyses(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trackSenseGroupAnalysisSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> generateSenseGroupAnalysis(
    String trackId, {
    String status = 'candidate',
  }) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses',
            {'status': status},
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activateSenseGroupAnalysis(
    String analysisId,
  ) async =>
      (await _request(
            'POST',
            '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveSenseGroupAnalysis(
    String analysisId,
  ) async =>
      (await _request(
            'POST',
            '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deleteSenseGroupAnalysis(
    String analysisId,
  ) async =>
      (await _request(
            'DELETE',
            '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackPhoneTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/phone-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> phoneTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activatePhoneTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archivePhoneTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deletePhoneTimeline(String timelineId) async =>
      (await _request(
            'DELETE',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;
}
