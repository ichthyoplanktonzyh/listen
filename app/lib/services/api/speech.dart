part of '../api_service.dart';

// Syntax capability, pronunciation, phonetic analysis jobs.
// Split out of api_service.dart (mechanical decomposition).

extension SpeechAnalysisApi on LocalApi {
  Future<SyntaxCapabilityView> syntaxCapability() async =>
      SyntaxCapabilityView.fromJson(
        (await _request('GET', '/v1/syntax/capability'))
            as Map<String, dynamic>,
      );

  Future<SyntaxCapabilityView> syntaxCapabilityAction(String action) async =>
      SyntaxCapabilityView.fromJson(
        (await _request('POST', '/v1/syntax/capability/$action', const {}))
            as Map<String, dynamic>,
      );

  Future<TrackSyntaxAnalysisView> runTrackSyntaxAnalysis(
    String trackId, {
    bool force = false,
  }) async => TrackSyntaxAnalysisView.fromJson(
    (await _request(
          'POST',
          '/v1/subtitles/${Uri.encodeComponent(trackId)}/syntax-analysis',
          {'force': force},
        ))
        as Map<String, dynamic>,
  );

  Future<TrackSyntaxAnalysisView> trackSyntaxAnalysisStatus(
    String trackId,
  ) async => TrackSyntaxAnalysisView.fromJson(
    (await _request(
          'GET',
          '/v1/subtitles/${Uri.encodeComponent(trackId)}/syntax-analysis',
        ))
        as Map<String, dynamic>,
  );

  Future<WordPronunciation> lookupPronunciation(String word) async =>
      WordPronunciation.fromJson(
        (await _request(
              'GET',
              '/v1/pronunciation/lookup?word=${Uri.encodeQueryComponent(word)}',
            ))
            as Map<String, dynamic>,
      );

  Future<List<PronunciationProvider>> pronunciationProviders() async =>
      ((await _request('GET', '/v1/pronunciation/providers')) as List<dynamic>)
          .map(
            (value) =>
                PronunciationProvider.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId) async =>
      PronunciationAnalysis.fromJson(
        (await _request('POST', '/v1/pronunciation/analyze-sentence', {
              'sentence_id': sentenceId,
            }))
            as Map<String, dynamic>,
      );

  Future<List<PronunciationAnalysis>> trackPronunciation(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/pronunciation',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                PronunciationAnalysis.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<List<PhoneticAnalysis>> trackPhoneticAnalyses(String trackId) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/phonetic-analyses',
              ))
              as List<dynamic>)
          .map(
            (value) => PhoneticAnalysis.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<List<SentenceChunkPartition>> trackChunkPartitions(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-partitions',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                SentenceChunkPartition.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<List<Map<String, dynamic>>> phoneticAnalysisModels() async =>
      ((await _request('GET', '/v1/phonetic-analysis/models')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> phoneticAnalysisProviders() async =>
      ((await _request('GET', '/v1/phonetic-analysis/providers'))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> installPhoneticAnalysisModel(
    String modelId,
  ) async =>
      (await _request('POST', '/v1/phonetic-analysis/models/install', {
            'model_id': modelId,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> phoneticAnalysisJobs() async =>
      ((await _request('GET', '/v1/phonetic-analysis/jobs')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createPhoneticAnalysisJob({
    required String trackId,
    required String modelId,
    String? sentenceId,
  }) async =>
      (await _request('POST', '/v1/phonetic-analysis/jobs', {
            'track_id': trackId,
            'sentence_id': sentenceId,
            'model_id': modelId,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelPhoneticAnalysisJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}/cancel',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> retryPhoneticAnalysisJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}/retry',
          ))
          as Map<String, dynamic>;

  Future<void> deletePhoneticAnalysisJob(String jobId) async {
    await _request(
      'DELETE',
      '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}',
    );
  }

  Future<Map<String, dynamic>> clearTerminalPhoneticAnalysisJobs() async =>
      (await _request('POST', '/v1/phonetic-analysis/jobs/clear'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updatePhoneticFindingFeedback({
    required String findingId,
    required String value,
    String? note,
  }) async =>
      (await _request(
            'PUT',
            '/v1/phonetic-analysis/findings/${Uri.encodeComponent(findingId)}/feedback',
            {'value': value, 'note': note},
          ))
          as Map<String, dynamic>;
}
