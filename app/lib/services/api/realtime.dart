part of '../api_service.dart';

RealtimeProviderProfileView _realtimeProfileFromJson(
  Map<String, dynamic> json,
) => RealtimeProviderProfileView(
  id: json['id'] as String,
  displayName: json['display_name'] as String,
  adapterKind: json['adapter_kind'] as String,
  baseUrl: json['base_url'] as String,
  modelId: json['model_id'] as String,
  voice: json['voice'] as String,
  hasCredential: json['has_credential'] as bool,
  timeoutMs: json['timeout_ms'] as int,
);

RealtimeConversationSessionView _realtimeSessionFromJson(
  Map<String, dynamic> json,
) {
  final context = json['context'] as Map<String, dynamic>?;
  final anchor = context?['content_anchor'] as Map<String, dynamic>?;
  return RealtimeConversationSessionView(
    id: json['id'] as String,
    profileId: json['profile_id'] as String,
    language: json['language'] as String,
    surfaceKind: context?['surface_kind'] as String? ?? 'open_chat',
    status: json['status'] as String,
    startedAtMs: (json['started_at_ms'] as num).toInt(),
    endedAtMs: (json['ended_at_ms'] as num?)?.toInt(),
    topic: anchor?['source_text'] as String?,
  );
}

RealtimeConversationItem _realtimeTurnFromJson(Map<String, dynamic> json) {
  final provider = json['provider_transcript'] as Map<String, dynamic>?;
  final local = json['local_transcript'] as Map<String, dynamic>?;
  final failureKind = json['failure_kind'] as String?;
  return RealtimeConversationItem(
    sequence: (json['sequence'] as num).toInt(),
    role: json['role'] as String,
    status: json['status'] as String,
    startedAtMs: (json['started_at_ms'] as num).toInt(),
    endedAtMs: (json['ended_at_ms'] as num?)?.toInt(),
    providerItemId: provider?['provider_item_id'] as String?,
    providerText: provider?['text'] as String? ?? '',
    localText: local?['text'] as String? ?? '',
    failure: failureKind == null
        ? null
        : RealtimeTurnFailure(kind: failureKind),
  );
}

Map<String, dynamic> _realtimeSessionJson(
  RealtimeConversationSessionRecord session,
) => {
  'id': session.id,
  'profile_id': session.profileId,
  'language': session.language,
  'context': {
    'surface_kind': session.surfaceKind,
    'content_anchor': switch (session.contentAnchor) {
      final anchor? => {
        'media_id': anchor.mediaId,
        'start_ms': anchor.startMs,
        'end_ms': anchor.endMs,
        'source_text': anchor.sourceText,
      },
      null => null,
    },
  },
  'status': session.status,
  'started_at_ms': session.startedAtMs,
  'ended_at_ms': session.endedAtMs,
  'failure_kind': session.failureKind,
};

Map<String, dynamic> _realtimeTurnJson(RealtimeConversationTurnRecord turn) => {
  'id': turn.id,
  'session_id': turn.sessionId,
  'sequence': turn.sequence,
  'role': turn.role,
  'status': turn.status,
  'assistance': turn.assistance,
  'provider_transcript': switch (turn.providerTranscript) {
    final transcript? => {
      'text': transcript.text,
      'provider_item_id': transcript.providerItemId,
      'received_at_ms': transcript.receivedAtMs,
    },
    null => null,
  },
  'local_transcript': switch (turn.localTranscript) {
    final transcript? => {
      'text': transcript.text,
      'recording_asset_id': transcript.recordingAssetId,
      'transcription_job_id': transcript.transcriptionJobId,
      'completed_at_ms': transcript.completedAtMs,
    },
    null => null,
  },
  'recording_asset_id': turn.recordingAssetId,
  'started_at_ms': turn.startedAtMs,
  'ended_at_ms': turn.endedAtMs,
  'failure_kind': turn.failureKind,
};

Map<String, dynamic> _createRecordingAssetJson(CreateRecordingAsset input) => {
  'file_path': input.filePath,
  'duration_ms': input.durationMs,
  'target': input.target.toJson(),
  'source_segment': {
    'media_id': input.sourceSegment.mediaId,
    'start_ms': input.sourceSegment.startMs,
    'end_ms': input.sourceSegment.endMs,
    'label': input.sourceSegment.label,
    'subtitle_snapshot': input.sourceSegment.subtitleSnapshot,
    'availability': input.sourceSegment.availability,
  },
  'language': input.language,
  'audio': {
    'container': input.audio.container,
    'codec': input.audio.codec,
    'sample_rate_hz': input.audio.sampleRateHz,
    'channels': input.audio.channels,
    'sample_format': input.audio.sampleFormat,
    'byte_length': input.audio.byteLength,
    'content_sha256': input.audio.contentSha256,
  },
  'recorder_version': input.recorderVersion,
};

extension RealtimeConversationApi on LocalApi {
  Future<List<RealtimeProviderProfileView>> realtimeProfiles() async =>
      ((await _request('GET', '/v1/realtime/providers')) as List<dynamic>)
          .map(
            (value) => _realtimeProfileFromJson(value as Map<String, dynamic>),
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
  }) async => _realtimeProfileFromJson(
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

  Future<void> saveRealtimeSession(
    RealtimeConversationSessionRecord session,
  ) async =>
      _request('POST', '/v1/realtime/sessions', _realtimeSessionJson(session));

  Future<void> saveRealtimeTurn(RealtimeConversationTurnRecord turn) async =>
      _request('POST', '/v1/realtime/turns', _realtimeTurnJson(turn));

  Future<RecordingAsset> createRecordingAsset(
    CreateRecordingAsset input,
  ) async => RecordingAsset(
    id:
        ((await _request(
                  'POST',
                  '/v1/recordings',
                  _createRecordingAssetJson(input),
                ))
                as Map<String, dynamic>)['id']
            as String,
  );

  Future<void> deleteRecordingAsset(String id) async =>
      _request('DELETE', '/v1/recordings/${Uri.encodeComponent(id)}');

  Future<List<RealtimeConversationSessionView>> realtimeSessions() async =>
      ((await _request('GET', '/v1/realtime/sessions')) as List<dynamic>)
          .map(
            (value) => _realtimeSessionFromJson(value as Map<String, dynamic>),
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
          .map((value) => _realtimeTurnFromJson(value as Map<String, dynamic>))
          .toList(growable: false);
}
