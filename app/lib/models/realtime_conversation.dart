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

/// Something that went wrong with the *conversation*, rather than with one
/// turn inside it — loading the voices, opening a past session, reaching the
/// provider, finishing cleanly.
///
/// The sibling of [RealtimeTurnFailure], and it exists for the same reason.
/// Plugging the turn card's leak while the notice bar still rendered
/// `'Realtime connection failed: $error'` would only have moved the exception
/// a few hundred pixels up the same screen: the learner would still read an
/// `HttpException`, a `correlation_id` and a localhost port, just in a red
/// strip instead of a card.
///
/// So a notice is a [kind] the UI turns into a sentence, plus optional typed
/// [detail]. The notice bar is a single strip with no room for a disclosure,
/// so it shows at most the reference id — enough to make a bug report
/// actionable, and nothing a learner has to decode.
class RealtimeConversationNotice {
  const RealtimeConversationNotice({required this.kind, this.detail});

  /// Named state: `providers_not_loaded`, `connection_failed`, … Never
  /// rendered raw.
  final String kind;

  /// Transport diagnostics, when the notice came from a request. Null for the
  /// ones the client decides locally (no voice picked, no topic chosen).
  final ApiFailure? detail;
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

class RealtimeContentAnchorRecord {
  const RealtimeContentAnchorRecord({
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    required this.sourceText,
  });

  final String mediaId;
  final int startMs;
  final int endMs;
  final String sourceText;
}

class RealtimeConversationSessionRecord {
  const RealtimeConversationSessionRecord({
    required this.id,
    required this.profileId,
    required this.language,
    required this.surfaceKind,
    required this.status,
    required this.startedAtMs,
    this.contentAnchor,
    this.endedAtMs,
    this.failureKind,
  });

  final String id;
  final String profileId;
  final String language;
  final String surfaceKind;
  final String status;
  final int startedAtMs;
  final RealtimeContentAnchorRecord? contentAnchor;
  final int? endedAtMs;
  final String? failureKind;
}

class RealtimeProviderTranscriptRecord {
  const RealtimeProviderTranscriptRecord({
    required this.text,
    required this.receivedAtMs,
    this.providerItemId,
  });

  final String text;
  final String? providerItemId;
  final int receivedAtMs;
}

class RealtimeLocalTranscriptRecord {
  const RealtimeLocalTranscriptRecord({
    required this.text,
    required this.recordingAssetId,
    required this.transcriptionJobId,
    required this.completedAtMs,
  });

  final String text;
  final String recordingAssetId;
  final String transcriptionJobId;
  final int completedAtMs;
}

class RealtimeConversationTurnRecord {
  const RealtimeConversationTurnRecord({
    required this.id,
    required this.sessionId,
    required this.sequence,
    required this.role,
    required this.status,
    required this.assistance,
    required this.startedAtMs,
    this.providerTranscript,
    this.localTranscript,
    this.recordingAssetId,
    this.endedAtMs,
    this.failureKind,
  });

  final String id;
  final String sessionId;
  final int sequence;
  final String role;
  final String status;
  final String assistance;
  final int startedAtMs;
  final RealtimeProviderTranscriptRecord? providerTranscript;
  final RealtimeLocalTranscriptRecord? localTranscript;
  final String? recordingAssetId;
  final int? endedAtMs;
  final String? failureKind;
}
