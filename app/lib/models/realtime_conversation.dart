import 'api_failure.dart';

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

  /// How long the conversation lasted, or null when the backend never recorded
  /// an end — an unfinished session has no honest duration to state.
  Duration? get duration => endedAtMs == null
      ? null
      : Duration(milliseconds: endedAtMs! - startedAtMs);

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

/// Why a turn did not close its loop.
///
/// Replaces the free-text `error` string a turn used to carry. That string was
/// built by interpolating whatever was caught (`'Could not process learner
/// turn: $error'`), so a transport exception — internal error code,
/// `correlation_id`, sidecar URI and route — travelled all the way into the
/// card that shows what the learner said. Charter P4: an honest instrument,
/// not debug output.
///
/// The split is the point. [kind] is a *named state* the UI maps to a sentence
/// of its own; [detail] is diagnostics, which have real value and so are kept,
/// but never rendered as part of the content flow and never visible by
/// default.
class RealtimeTurnFailure {
  const RealtimeTurnFailure({required this.kind, this.detail});

  /// Wire-faithful failure kind — the same vocabulary as the turn's
  /// `failure_kind` field (`local_transcription_failed`, `learner_barge_in`,
  /// `user_cancelled`, …). Never rendered raw: a raw enum on screen is the
  /// thing this type exists to prevent.
  final String kind;

  /// The transport diagnostics behind this failure, when the failure came
  /// from a request. Null for failures the client decided locally, and for
  /// turns replayed from history (the backend stores the kind, not the
  /// exchange that produced it).
  final ApiFailure? detail;

  /// True only when the backend explicitly said the request may be retried.
  /// A missing signal is not a yes — no retry affordance is offered on a
  /// guess.
  bool get retryable => detail?.isRetryable ?? false;
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
    this.failure,
  });

  factory RealtimeConversationItem.fromJson(Map<String, dynamic> json) {
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

  final int sequence;
  final String role;
  final String status;
  final int startedAtMs;
  final int? endedAtMs;
  final String? providerItemId;
  final String providerText;
  final String localText;

  /// Named failure state plus its default-hidden diagnostics. Null means the
  /// turn has nothing to explain.
  final RealtimeTurnFailure? failure;

  String get displayText => localText.isNotEmpty ? localText : providerText;

  RealtimeConversationItem copyWith({
    String? status,
    int? endedAtMs,
    Object? providerItemId = _realtimeUnset,
    String? providerText,
    String? localText,
    Object? failure = _realtimeUnset,
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
    failure: identical(failure, _realtimeUnset)
        ? this.failure
        : failure as RealtimeTurnFailure?,
  );
}

const _realtimeUnset = Object();
