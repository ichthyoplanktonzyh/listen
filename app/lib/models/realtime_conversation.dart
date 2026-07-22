class RealtimeProviderProfileView {
  const RealtimeProviderProfileView({
    required this.id,
    required this.displayName,
    required this.adapterKind,
    required this.baseUrl,
    required this.modelId,
    required this.voice,
    required this.hasCredential,
    required this.timeoutMs,
  });

  factory RealtimeProviderProfileView.fromJson(Map<String, dynamic> json) =>
      RealtimeProviderProfileView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        adapterKind: json['adapter_kind'] as String,
        baseUrl: json['base_url'] as String,
        modelId: json['model_id'] as String,
        voice: json['voice'] as String,
        hasCredential: json['has_credential'] as bool,
        timeoutMs: json['timeout_ms'] as int,
      );

  final String id;
  final String displayName;
  final String adapterKind;
  final String baseUrl;
  final String modelId;
  final String voice;
  final bool hasCredential;
  final int timeoutMs;
}

enum RealtimeConversationMode { free, topicAnchored }

class RealtimeConversationSessionView {
  const RealtimeConversationSessionView({
    required this.id,
    required this.profileId,
    required this.language,
    required this.surfaceKind,
    required this.status,
    required this.startedAtMs,
    this.endedAtMs,
    this.topic,
    this.conversationPreview,
    this.turnCount,
  });

  factory RealtimeConversationSessionView.fromJson(Map<String, dynamic> json) {
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

  final String id;
  final String profileId;
  final String language;
  final String surfaceKind;
  final String status;
  final int startedAtMs;
  final int? endedAtMs;
  final String? topic;
  final String? conversationPreview;
  final int? turnCount;

  RealtimeConversationSessionView withTurns(
    List<RealtimeConversationItem> turns,
  ) {
    final previews = turns
        .map((turn) => turn.displayText.trim())
        .where((text) => text.isNotEmpty);
    return RealtimeConversationSessionView(
      id: id,
      profileId: profileId,
      language: language,
      surfaceKind: surfaceKind,
      status: status,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      topic: topic,
      conversationPreview: previews.isEmpty ? null : previews.first,
      turnCount: turns.length,
    );
  }
}

class RealtimeConversationItem {
  const RealtimeConversationItem({
    required this.sequence,
    required this.role,
    required this.status,
    required this.startedAtMs,
    this.endedAtMs,
    this.providerItemId,
    this.providerText = '',
    this.localText = '',
    this.error,
  });

  factory RealtimeConversationItem.fromJson(Map<String, dynamic> json) {
    final provider = json['provider_transcript'] as Map<String, dynamic>?;
    final local = json['local_transcript'] as Map<String, dynamic>?;
    return RealtimeConversationItem(
      sequence: (json['sequence'] as num).toInt(),
      role: json['role'] as String,
      status: json['status'] as String,
      startedAtMs: (json['started_at_ms'] as num).toInt(),
      endedAtMs: (json['ended_at_ms'] as num?)?.toInt(),
      providerItemId: provider?['provider_item_id'] as String?,
      providerText: provider?['text'] as String? ?? '',
      localText: local?['text'] as String? ?? '',
      error: json['failure_kind'] as String?,
    );
  }

  final int sequence;
  final String role;
  final String status;
  final int startedAtMs;
  final int? endedAtMs;
  final String? providerItemId;
  final String providerText;
  final String localText;
  final String? error;

  String get displayText => localText.isNotEmpty ? localText : providerText;

  RealtimeConversationItem copyWith({
    String? status,
    int? endedAtMs,
    Object? providerItemId = _realtimeUnset,
    String? providerText,
    String? localText,
    Object? error = _realtimeUnset,
  }) => RealtimeConversationItem(
    sequence: sequence,
    role: role,
    status: status ?? this.status,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs ?? this.endedAtMs,
    providerItemId: identical(providerItemId, _realtimeUnset)
        ? this.providerItemId
        : providerItemId as String?,
    providerText: providerText ?? this.providerText,
    localText: localText ?? this.localText,
    error: identical(error, _realtimeUnset) ? this.error : error as String?,
  );
}

const _realtimeUnset = Object();
