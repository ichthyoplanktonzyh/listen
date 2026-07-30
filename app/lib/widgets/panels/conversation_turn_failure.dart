import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/realtime_conversation.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// One sentence for a turn's failure kind — the *named state*, never the
/// wire value and never an exception.
///
/// Charter P4 (「诚实的仪器,不是 debug 输出」): a turn that did not close its
/// loop says so in a sentence addressed to the learner. The backend's
/// vocabulary (`local_post_processing_failed`, `learner_barge_in`, …) is a
/// switch input here, not screen text; a kind this build has never heard of
/// degrades to the generic sentence rather than surfacing the raw token.
String conversationTurnFailureText(String kind, AppLocalizations l) =>
    l.text(switch (kind) {
      'learner_audio_capture_failed' => 'realtimeFailureAudioCapture',
      'local_transcription_failed' => 'realtimeFailureLocalTranscription',
      'local_post_processing_failed' => 'realtimeFailurePostProcessing',
      'assistant_history_not_saved' ||
      'interrupted_turn_not_saved' => 'realtimeFailureHistoryNotSaved',
      'learner_barge_in' => 'realtimeFailureBargeIn',
      'user_cancelled' => 'realtimeFailureCancelled',
      'assistant_response_incomplete' => 'realtimeFailureResponseIncomplete',
      'provider_drain_timeout' => 'realtimeFailureDrainTimeout',
      'surface_disposed' => 'realtimeFailureSurfaceDisposed',
      _ => 'realtimeFailureUnknown',
    });

/// One sentence for a conversation-level notice — same rule as
/// [conversationTurnFailureText], one level up.
///
/// These are the strings that used to be built by interpolation
/// (`'Realtime connection failed: $error'`), so the notice bar showed the
/// learner an `HttpException`, a `correlation_id` and a localhost port on the
/// very screen the turn card had just been cleaned up.
String conversationNoticeText(String kind, AppLocalizations l) =>
    l.text(switch (kind) {
      'providers_not_loaded' => 'realtimeNoticeProvidersNotLoaded',
      'history_not_loaded' => 'realtimeNoticeHistoryNotLoaded',
      'turns_not_loaded' => 'realtimeNoticeTurnsNotLoaded',
      'no_voice_selected' => 'realtimeNoticeNoVoiceSelected',
      'no_topic_selected' => 'realtimeNoticeNoTopicSelected',
      'start_failed' => 'realtimeNoticeStartFailed',
      'connection_failed' => 'realtimeNoticeConnectionFailed',
      'provider_disconnected' => 'realtimeNoticeProviderDisconnected',
      'provider_error' => 'realtimeNoticeProviderError',
      'provider_event_invalid' => 'realtimeNoticeProviderEventInvalid',
      'finish_failed' => 'realtimeNoticeFinishFailed',
      _ => 'realtimeNoticeUnknown',
    });

/// The conversation's error strip: one sentence, plus the reference id when
/// there is one.
///
/// Deliberately thinner than [ConversationTurnFailureNotice]. A strip has no
/// room for a disclosure, and the notice cases are things the learner can
/// mostly act on directly ("pick a voice", "the service disconnected") — so
/// the only diagnostic it carries is the id that ties a bug report to a
/// backend log line. The error code, the operator-facing message and
/// [ApiFailure.raw] all stay off screen entirely.
class ConversationNoticeBar extends StatelessWidget {
  const ConversationNoticeBar({super.key, required this.notice});

  final RealtimeConversationNotice notice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reference = notice.detail?.correlationId;
    return Container(
      key: const ValueKey('realtime-notice'),
      padding: const EdgeInsets.all(ListenSpacing.gap12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversationNoticeText(notice.kind, l),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          if (reference != null) ...[
            const SizedBox(height: ListenSpacing.gap4),
            SelectableText(
              key: const ValueKey('realtime-notice-reference'),
              l.text('failureReference').replaceAll('{id}', reference),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The two affordances a failed turn is allowed to grow, under the sentence
/// its host already wrote: a retry, and a way to see what actually happened.
///
/// **Nothing here is in the content flow.** The turn's body stays the
/// learner's own words or an honest "this did not come back"; the transport's
/// error code, `correlation_id` and message live behind a disclosure that is
/// closed on every build. They are kept rather than dropped because they are
/// the only thing that makes a bug report actionable — but a diagnostic
/// visible by default is debug output wearing a UI.
///
/// The raw transport text ([ApiFailure.raw] — response body plus the sidecar
/// URI the exception appended) is deliberately *not* rendered even when the
/// disclosure is open: a localhost port and an internal route tell the learner
/// nothing, and the reference id is what ties a report to the backend log.
///
/// [onRetry] is only ever called for a failure the backend itself marked
/// retryable; the button does not exist otherwise, so it never offers a rerun
/// nothing will act on.
class ConversationTurnFailureNotice extends StatefulWidget {
  const ConversationTurnFailureNotice({
    super.key,
    required this.failure,
    this.onRetry,
  });

  final RealtimeTurnFailure failure;

  /// Reruns this turn's local transcription. Null in hosts that cannot rerun
  /// it (history replay, tests) — which also removes the button.
  final VoidCallback? onRetry;

  @override
  State<ConversationTurnFailureNotice> createState() =>
      _ConversationTurnFailureNoticeState();
}

class _ConversationTurnFailureNoticeState
    extends State<ConversationTurnFailureNotice> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = widget.failure.detail;
    final canRetry = widget.failure.retryable && widget.onRetry != null;
    // Only a body the client could actually type is worth a disclosure; an
    // unrecognised body has nothing to show but the raw text this widget
    // exists to keep off screen.
    final details = detail != null && detail.isStructured ? detail : null;
    if (!canRetry && details == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: ListenSpacing.gap8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (canRetry)
              FilledButton.tonalIcon(
                key: const ValueKey('conversation-turn-retry'),
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l.text('realtimeRetryTranscription')),
              ),
            if (details != null)
              TextButton(
                key: const ValueKey('conversation-turn-failure-details'),
                onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
                child: Text(
                  l.text(
                    _detailsOpen
                        ? 'realtimeFailureDetailsHide'
                        : 'realtimeFailureDetailsShow',
                  ),
                ),
              ),
          ],
        ),
        if (details != null && _detailsOpen) ...[
          const SizedBox(height: ListenSpacing.gap4),
          SelectableText(
            key: const ValueKey('conversation-turn-failure-detail-text'),
            _detailLines(details, l).join('\n'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  List<String> _detailLines(ApiFailure detail, AppLocalizations l) => [
    if (detail.code != null) detail.code!,
    if (detail.message != null) detail.message!,
    if (detail.correlationId != null)
      l
          .text('failureReference')
          .replaceAll('{id}', detail.correlationId!),
  ];
}
