part of '../api_service.dart';

// Practice sessions/items, shadowing, review queue, upgrade suggestions.
// Split out of api_service.dart (mechanical decomposition).

extension PracticeReviewApi on LocalApi {
  Future<PracticeSession> createPracticeSession(
    CreatePracticeSession input,
  ) async => PracticeSession.fromJson(
    (await _request('POST', '/v1/practice/sessions', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<PracticeItem> createPracticeItem(CreatePracticeItem input) async =>
      PracticeItem.fromJson(
        (await _request('POST', '/v1/practice/items', input.toJson()))
            as Map<String, dynamic>,
      );

  Future<PracticeAttempt> submitPracticeAttempt(
    SubmitPracticeAttempt input,
  ) async => PracticeAttempt.fromJson(
    (await _request('POST', '/v1/practice/attempts', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<RecordingAsset> createRecordingAsset(
    CreateRecordingAsset input,
  ) async => RecordingAsset.fromJson(
    (await _request('POST', '/v1/recordings', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<PracticeAttempt> completeShadowingAttempt({
    required String itemId,
    required String recordingId,
  }) async => PracticeAttempt.fromJson(
    (await _request('POST', '/v1/practice/shadowing-attempts', {
          'item_id': itemId,
          'recording_id': recordingId,
        }))
        as Map<String, dynamic>,
  );

  Future<ShadowingComparison> compareShadowing({
    required String recordingId,
    required String referenceWavPath,
  }) async => ShadowingComparison.fromJson(
    (await _request('POST', '/v1/shadowing/comparisons', {
          'recording_id': recordingId,
          'reference_wav_path': referenceWavPath,
        }))
        as Map<String, dynamic>,
  );

  Future<RecordingAudioFacts> recordingAudioFacts(String recordingId) async =>
      RecordingAudioFacts.fromJson(
        (await _request(
              'GET',
              '/v1/recordings/${Uri.encodeComponent(recordingId)}/audio-facts',
            ))
            as Map<String, dynamic>,
      );

  Future<RecordingAsset> deleteRecordingAsset(String id) async =>
      RecordingAsset.fromJson(
        (await _request('DELETE', '/v1/recordings/${Uri.encodeComponent(id)}'))
            as Map<String, dynamic>,
      );

  Future<PracticeAttempt> practiceAttempt(String id) async =>
      PracticeAttempt.fromJson(
        (await _request(
              'GET',
              '/v1/practice/attempts/${Uri.encodeComponent(id)}',
            ))
            as Map<String, dynamic>,
      );

  Future<ReviewItem> createReviewItem(CreateReviewItem input) async =>
      ReviewItem.fromJson(
        (await _request('POST', '/v1/review/items', input.toJson()))
            as Map<String, dynamic>,
      );

  Future<ReviewItem> reviewItem(String id) async => ReviewItem.fromJson(
    (await _request('GET', '/v1/review/items/${Uri.encodeComponent(id)}'))
        as Map<String, dynamic>,
  );

  /// The due queue *after* the backend clips it to today's budget, together
  /// with the budget status that explains a short or empty queue. The raw
  /// `/v1/review/items` list is still there but says nothing about limits, so
  /// a session built on it silently ignores them.
  Future<ReviewQueue> reviewQueue({int limit = 20}) async => ReviewQueue.fromJson(
    (await _request('GET', '/v1/review/queue?limit=$limit'))
        as Map<String, dynamic>,
  );

  Future<List<ReviewIntervalPreview>> reviewIntervalPreview(
    String itemId,
  ) async {
    final values =
        (await _request(
              'GET',
              '/v1/review/items/${Uri.encodeComponent(itemId)}'
                  '/interval-preview',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) =>
              ReviewIntervalPreview.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<ReviewDeckOverview> reviewDeckOverview() async =>
      ReviewDeckOverview.fromJson(
        (await _request('GET', '/v1/review/decks')) as Map<String, dynamic>,
      );

  Future<ReviewDailyLimits> reviewDailyLimits() async =>
      ReviewDailyLimits.fromJson(
        (await _request('GET', '/v1/review/settings/limits'))
            as Map<String, dynamic>,
      );

  Future<ReviewDailyLimits> updateReviewDailyLimits(
    ReviewDailyLimits limits,
  ) async => ReviewDailyLimits.fromJson(
    (await _request('PUT', '/v1/review/settings/limits', limits.toJson()))
        as Map<String, dynamic>,
  );

  Future<CustomStudyQueue> customStudy(CustomStudyRequest request) async =>
      CustomStudyQueue.fromJson(
        (await _request('POST', '/v1/review/custom-study', request.toJson()))
            as Map<String, dynamic>,
      );

  Future<ReviewSubmission> submitCustomStudyAttempt({
    required String itemId,
    required String rating,
    required CustomStudyRequest request,
  }) async => ReviewSubmission.fromJson(
    (await _request('POST', '/v1/review/custom-study/attempts', {
          'item_id': itemId,
          'rating': rating,
          ...request.toJson()..remove('limit'),
        }))
        as Map<String, dynamic>,
  );

  Future<AnkiPackageImportSummary> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  }) async => AnkiPackageImportSummary.fromJson(
    (await _request('POST', '/v1/review/anki/import', {
          'package_path': packagePath,
          'media_directory': mediaDirectory,
        }))
        as Map<String, dynamic>,
  );

  Future<AnkiPackageExportSummary> exportAnkiPackage(
    AnkiPackageExportRequest request,
  ) async => AnkiPackageExportSummary.fromJson(
    (await _request('POST', '/v1/review/anki/export', request.toJson()))
        as Map<String, dynamic>,
  );

  Future<ReviewSubmission> submitReviewAttempt(
    String itemId,
    String rating,
  ) async => ReviewSubmission.fromJson(
    (await _request('POST', '/v1/review/attempts', {
          'item_id': itemId,
          'rating': rating,
        }))
        as Map<String, dynamic>,
  );

  Future<List<UpgradeSuggestion>> upgradeSuggestions({
    String status = 'pending',
    String? lexicalEntryId,
  }) async {
    final query = <String, String>{
      'status': status,
      'limit': '100',
      'offset': '0',
    };
    if (lexicalEntryId != null) query['lexical_entry_id'] = lexicalEntryId;
    final values =
        (await _request(
              'GET',
              '/v1/review/upgrade-suggestions?${Uri(queryParameters: query).query}',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) => UpgradeSuggestion.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<UpgradeSuggestion>> upgradeSuggestionHistory({
    String? lexicalEntryId,
  }) async {
    final query = <String, String>{'limit': '100', 'offset': '0'};
    if (lexicalEntryId != null) query['lexical_entry_id'] = lexicalEntryId;
    final values =
        (await _request(
              'GET',
              '/v1/review/upgrade-suggestions/history?${Uri(queryParameters: query).query}',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) => UpgradeSuggestion.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<UpgradeSuggestion> confirmUpgradeSuggestion(
    String id,
  ) async => UpgradeSuggestion.fromJson(
    (await _request(
          'POST',
          '/v1/review/upgrade-suggestions/${Uri.encodeComponent(id)}/confirm',
        ))
        as Map<String, dynamic>,
  );

  Future<UpgradeSuggestion> rejectUpgradeSuggestion(
    String id,
  ) async => UpgradeSuggestion.fromJson(
    (await _request(
          'POST',
          '/v1/review/upgrade-suggestions/${Uri.encodeComponent(id)}/reject',
        ))
        as Map<String, dynamic>,
  );
}
