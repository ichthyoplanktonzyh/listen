part of '../api_service.dart';

// Extensive-listening inbox and hunting workflow.
// Split out of api_service.dart (mechanical decomposition).

extension ListeningHuntingApi on LocalApi {
  Future<PracticeSession> completeListeningSession(
    String id, {
    String? comprehensionReport,
    HuntingCompletionSummary? huntingSummary,
  }) async => PracticeSession.fromJson(
    (await _request(
          'POST',
          '/v1/listening/sessions/${Uri.encodeComponent(id)}/complete',
          {
            'comprehension_report': comprehensionReport,
            'hunting_summary': huntingSummary?.toJson(),
          },
        ))
        as Map<String, dynamic>,
  );

  Future<List<ListeningInboxItem>> listeningInboxItems({
    String status = 'active',
    int limit = 100,
    int offset = 0,
  }) async {
    final query = Uri(
      queryParameters: {
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final values =
        (await _request('GET', '/v1/listening-inbox/items?$query'))
            as List<dynamic>;
    return values
        .map(
          (value) => ListeningInboxItem.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<ListeningInboxItem> captureListeningInboxItem(
    CaptureListeningInboxItemInput input,
  ) async => ListeningInboxItem.fromJson(
    (await _request('POST', '/v1/listening-inbox/items', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<ListeningInboxItem> processListeningInboxItem(
    String id,
    ProcessListeningInboxItemInput input,
  ) async => ListeningInboxItem.fromJson(
    (await _request(
          'POST',
          '/v1/listening-inbox/items/${Uri.encodeComponent(id)}/process',
          input.toJson(),
        ))
        as Map<String, dynamic>,
  );

  Future<List<HuntingCandidate>> huntingCandidates({
    String status = 'active',
    int limit = 100,
    int offset = 0,
  }) async {
    final query = Uri(
      queryParameters: {
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final values =
        (await _request('GET', '/v1/hunting/candidates?$query'))
            as List<dynamic>;
    return values
        .map(
          (value) => HuntingCandidate.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<HuntingTarget>> huntingTargets({
    String status = 'active',
    int limit = 100,
    int offset = 0,
  }) async {
    final query = Uri(
      queryParameters: {
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    final values =
        (await _request('GET', '/v1/hunting/targets?$query')) as List<dynamic>;
    return values
        .map((value) => HuntingTarget.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<HuntingTarget> createHuntingTarget({
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  }) async => HuntingTarget.fromJson(
    (await _request('POST', '/v1/hunting/targets', {
          'lexical_entry_id': lexicalEntryId,
          'source_kind': sourceKind,
          'source_id': sourceId,
        }))
        as Map<String, dynamic>,
  );

  Future<HuntingTarget> archiveHuntingTarget(String id) async =>
      HuntingTarget.fromJson(
        (await _request(
              'DELETE',
              '/v1/hunting/targets/${Uri.encodeComponent(id)}',
            ))
            as Map<String, dynamic>,
      );

  Future<HuntingOccurrenceQueryResult> huntingOccurrences({
    required String mediaId,
    String? trackId,
  }) async {
    final query = <String, String>{'media_id': mediaId};
    if (trackId != null) query['track_id'] = trackId;
    return HuntingOccurrenceQueryResult.fromJson(
      (await _request(
            'GET',
            '/v1/hunting/occurrences?${Uri(queryParameters: query).query}',
          ))
          as Map<String, dynamic>,
    );
  }

  Future<HuntingCheckResult> submitHuntingCheck({
    required String sessionId,
    required String targetId,
    required String occurrenceId,
    required String answer,
  }) async => HuntingCheckResult.fromJson(
    (await _request('POST', '/v1/hunting/checks', {
          'session_id': sessionId,
          'target_id': targetId,
          'occurrence_id': occurrenceId,
          'answer': answer,
        }))
        as Map<String, dynamic>,
  );
}
