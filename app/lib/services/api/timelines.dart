part of '../api_service.dart';

// Word/chunk/sense-group/phone timeline resources.
// Split out of api_service.dart (mechanical decomposition).

extension TimelinesApi on LocalApi {
  Future<List<WordTiming>> trackWordTimings(String trackId) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timings',
              ))
              as List<dynamic>)
          .map((value) => WordTiming.fromJson(value as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<WordTimelineSummary>> trackWordTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines/summary',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                WordTimelineSummary.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<WordTimeline> wordTimeline(String timelineId) async =>
      WordTimeline.fromJson(
        (await _request(
              'GET',
              '/v1/word-timelines/${Uri.encodeComponent(timelineId)}',
            ))
            as Map<String, dynamic>,
      );

  Future<WordTimeline> createTrackWordTimeline(
    String trackId,
    Map<String, dynamic> payload,
  ) async => WordTimeline.fromJson(
    (await _request(
          'POST',
          '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines',
          payload,
        ))
        as Map<String, dynamic>,
  );

  Future<WordTimeline> activateWordTimeline(String timelineId) async =>
      WordTimeline.fromJson(
        (await _request(
              'POST',
              '/v1/word-timelines/${Uri.encodeComponent(timelineId)}/activate',
            ))
            as Map<String, dynamic>,
      );

  Future<List<SenseGroupAnalysis>> trackSenseGroupAnalyses(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                SenseGroupAnalysis.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<List<SenseGroupAnalysisSummary>> trackSenseGroupAnalysisSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses/summary',
              ))
              as List<dynamic>)
          .map(
            (value) => SenseGroupAnalysisSummary.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<SenseGroupAnalysis> generateSenseGroupAnalysis(
    String trackId, {
    String status = 'candidate',
  }) async => SenseGroupAnalysis.fromJson(
    (await _request(
          'POST',
          '/v1/subtitles/${Uri.encodeComponent(trackId)}/sense-group-analyses',
          {'status': status},
        ))
        as Map<String, dynamic>,
  );

  Future<SenseGroupAnalysis> activateSenseGroupAnalysis(
    String analysisId,
  ) async => SenseGroupAnalysis.fromJson(
    (await _request(
          'POST',
          '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}/activate',
        ))
        as Map<String, dynamic>,
  );

  Future<SenseGroupAnalysis> archiveSenseGroupAnalysis(
    String analysisId,
  ) async => SenseGroupAnalysis.fromJson(
    (await _request(
          'POST',
          '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}/archive',
        ))
        as Map<String, dynamic>,
  );

  Future<SenseGroupAnalysis> deleteSenseGroupAnalysis(
    String analysisId,
  ) async => SenseGroupAnalysis.fromJson(
    (await _request(
          'DELETE',
          '/v1/sense-group-analyses/${Uri.encodeComponent(analysisId)}',
        ))
        as Map<String, dynamic>,
  );

  Future<List<PhoneTimelineSummary>> trackPhoneTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/phone-timelines/summary',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                PhoneTimelineSummary.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<PhoneTimeline> phoneTimeline(String timelineId) async =>
      PhoneTimeline.fromJson(
        (await _request(
              'GET',
              '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
            ))
            as Map<String, dynamic>,
      );

  Future<PhoneTimeline> activatePhoneTimeline(String timelineId) async =>
      PhoneTimeline.fromJson(
        (await _request(
              'POST',
              '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/activate',
            ))
            as Map<String, dynamic>,
      );

  Future<PhoneTimeline> archivePhoneTimeline(String timelineId) async =>
      PhoneTimeline.fromJson(
        (await _request(
              'POST',
              '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/archive',
            ))
            as Map<String, dynamic>,
      );

  Future<PhoneTimeline> deletePhoneTimeline(String timelineId) async =>
      PhoneTimeline.fromJson(
        (await _request(
              'DELETE',
              '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
            ))
            as Map<String, dynamic>,
      );
}
