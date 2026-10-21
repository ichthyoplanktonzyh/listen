part of '../api_service.dart';

extension PersonalExpressionApi on LocalApi {
  Future<PersonalExpressionExportBundleView> exportPersonalExpression({
    String? language,
  }) async {
    final query = language == null
        ? ''
        : '?${Uri(queryParameters: {'language': language}).query}';
    return PersonalExpressionExportBundleView.fromJson(
      await _request('GET', '/v1/personal-expression/export$query')
          as Map<String, dynamic>,
    );
  }

  Future<List<SentencePatternAssetView>> sentencePatterns({
    String? language,
    String? query,
  }) async {
    final params = Uri(
      queryParameters: {
        // ignore: use_null_aware_elements
        if (language != null) 'language': language,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      },
    ).query;
    final value = await _request(
      'GET',
      '/v1/personal-expression/patterns${params.isEmpty ? '' : '?$params'}',
    );
    return (value as List<dynamic>)
        .map(
          (item) =>
              SentencePatternAssetView.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<SentencePatternAssetView> createSentencePattern({
    required String language,
    required PersonalExpressionSourceView source,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
    String? systemConstructionId,
  }) async => SentencePatternAssetView.fromJson(
    await _request('POST', '/v1/personal-expression/patterns', {
          'language': language,
          'source': source.toJson(),
          'name': name,
          'pattern_text': patternText,
          'slots': slots.map((slot) => slot.toJson()).toList(),
          'note': note,
          'system_construction_id': systemConstructionId,
        })
        as Map<String, dynamic>,
  );

  Future<SentencePatternAssetView> reviseSentencePattern({
    required String id,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
    String? systemConstructionId,
  }) async => SentencePatternAssetView.fromJson(
    await _request('PUT', '/v1/personal-expression/patterns/$id', {
          'name': name,
          'pattern_text': patternText,
          'slots': slots.map((slot) => slot.toJson()).toList(),
          'note': note,
          'system_construction_id': systemConstructionId,
        })
        as Map<String, dynamic>,
  );

  Future<void> deleteSentencePattern(String id) async =>
      _request('DELETE', '/v1/personal-expression/patterns/$id');

  Future<List<SentencePatternVersionView>> sentencePatternVersions(
    String id,
  ) async =>
      ((await _request('GET', '/v1/personal-expression/patterns/$id/versions'))
              as List<dynamic>)
          .map(
            (item) => SentencePatternVersionView.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<List<PersonalExpressionAttemptView>> personalExpressionAttempts(
    String id,
  ) async =>
      ((await _request('GET', '/v1/personal-expression/patterns/$id/attempts'))
              as List<dynamic>)
          .map(
            (item) => PersonalExpressionAttemptView.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<PersonalExpressionAttemptView> recordPersonalExpressionAttempt({
    required String patternId,
    required String patternVersionId,
    required String channel,
    required String assistance,
    required String responseText,
    String? rawTranscript,
    String? recordingAssetId,
    String? semanticAttemptId,
    required String selfAssessment,
    String? contextNote,
  }) async => PersonalExpressionAttemptView.fromJson(
    await _request(
          'POST',
          '/v1/personal-expression/patterns/$patternId/attempts',
          {
            'pattern_version_id': patternVersionId,
            'channel': channel,
            'assistance': assistance,
            'response_text': responseText,
            'raw_transcript': rawTranscript,
            'recording_asset_id': recordingAssetId,
            'semantic_attempt_id': semanticAttemptId,
            'self_assessment': selfAssessment,
            'context_note': contextNote,
          },
        )
        as Map<String, dynamic>,
  );
}
