part of '../api_service.dart';

// Listening practice sessions/items and FSRS review queue.
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
  Future<ReviewQueue> reviewQueue({int limit = 20}) async =>
      ReviewQueue.fromJson(
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

  Future<CustomStudyQueue> customStudy(CustomStudyRequest request) async {
    _requireListeningCustomStudy(request);
    return CustomStudyQueue.fromJson(
      (await _request('POST', '/v1/review/custom-study', request.toJson()))
          as Map<String, dynamic>,
    );
  }

  Future<ReviewSubmission> submitCustomStudyAttempt({
    required String itemId,
    required String rating,
    required CustomStudyRequest request,
  }) async {
    _requireListeningCustomStudy(request);
    return ReviewSubmission.fromJson(
      (await _request('POST', '/v1/review/custom-study/attempts', {
            'item_id': itemId,
            'rating': rating,
            ...request.toJson()..remove('limit'),
          }))
          as Map<String, dynamic>,
    );
  }

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
    String? lexicalEntryId,
    String? status = 'pending',
    int limit = 100,
    int offset = 0,
  }) async {
    final query = <String, String>{
      'lexical_entry_id': ?lexicalEntryId,
      'status': ?status,
      'limit': '$limit',
      'offset': '$offset',
    };
    final values =
        (await _request(
              'GET',
              '/v1/review/upgrade-suggestions?${Uri(queryParameters: query).query}',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) => UpgradeSuggestion.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<UpgradeSuggestion>> upgradeSuggestionHistory({
    String? lexicalEntryId,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = <String, String>{
      'lexical_entry_id': ?lexicalEntryId,
      'limit': '$limit',
      'offset': '$offset',
    };
    final values =
        (await _request(
              'GET',
              '/v1/review/upgrade-suggestions/history?${Uri(queryParameters: query).query}',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) => UpgradeSuggestion.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<UpgradeSuggestion> confirmUpgradeSuggestion(
    String id,
  ) async => UpgradeSuggestion.fromJson(
    (await _request(
          'POST',
          '/v1/review/upgrade-suggestions/${Uri.encodeComponent(id)}/confirm',
          const {},
        ))
        as Map<String, dynamic>,
  );

  Future<UpgradeSuggestion> rejectUpgradeSuggestion(
    String id,
  ) async => UpgradeSuggestion.fromJson(
    (await _request(
          'POST',
          '/v1/review/upgrade-suggestions/${Uri.encodeComponent(id)}/reject',
          const {},
        ))
        as Map<String, dynamic>,
  );
}

void _requireListeningCustomStudy(CustomStudyRequest request) {
  if (request.kind == CustomStudyKind.channel &&
      request.channel != 'listening') {
    throw ArgumentError.value(
      request.channel,
      'channel',
      'manual custom study supports listening only',
    );
  }
}
