part of '../api_service.dart';

extension RealtimeConversationApi on LocalApi {
  Future<List<RealtimeProviderProfileView>> realtimeProfiles() async =>
      ((await _request('GET', '/v1/realtime/providers')) as List<dynamic>)
          .map(
            (value) => RealtimeProviderProfileView.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<RealtimeProviderProfileView> registerRealtimeProfile({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
    int timeoutMs = 30000,
  }) async => RealtimeProviderProfileView.fromJson(
    (await _request('POST', '/v1/realtime/providers', {
          'display_name': displayName,
          'adapter_kind': adapterKind,
          'base_url': baseUrl,
          'model_id': modelId,
          'voice': voice,
          'secret': secret,
          'timeout_ms': timeoutMs,
        }))
        as Map<String, dynamic>,
  );

  Future<void> deleteRealtimeProfile(String id) async =>
      _request('DELETE', '/v1/realtime/providers/${Uri.encodeComponent(id)}');

  Uri realtimeSocketUri({
    required String profileId,
    required String language,
    required String instructions,
  }) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/realtime/conversations/ws',
      queryParameters: {
        'profile_id': profileId,
        'language': language,
        'instructions': instructions,
      },
    );
  }

  Future<void> saveRealtimeSession(Map<String, dynamic> session) async =>
      _request('POST', '/v1/realtime/sessions', session);

  Future<void> saveRealtimeTurn(Map<String, dynamic> turn) async =>
      _request('POST', '/v1/realtime/turns', turn);

  Future<List<RealtimeConversationSessionView>> realtimeSessions() async =>
      ((await _request('GET', '/v1/realtime/sessions')) as List<dynamic>)
          .map(
            (value) => RealtimeConversationSessionView.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<List<RealtimeConversationItem>> realtimeTurns(
    String sessionId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/realtime/sessions/${Uri.encodeComponent(sessionId)}/turns',
              ))
              as List<dynamic>)
          .map(
            (value) => RealtimeConversationItem.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
}
