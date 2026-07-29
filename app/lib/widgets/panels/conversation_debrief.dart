import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../localization.dart';
import '../../models/realtime_conversation.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';
import 'conversation_turn_failure.dart';

/// 结束页 — the third room of the conversation (#70 Phase 2 · S9, issue #86).
///
/// Audit D6: the conversation→portrait 回流 used to be one line of small text.
/// The debrief makes it a readable instrument panel, in the three fixed
/// sections the design note pins down:
///
/// 1. **对话** — the local Whisper transcript as the body of the page. This is
///    the one place your own words are shown, and the only place they are
///    called learner output. The provider's live caption is *guidance*: it is
///    kept, but folded away behind an explicit disclosure so it can never be
///    mistaken for what you produced (charter · 诚实分层, audit D3).
/// 2. **靶子** — amber, and only where a real backend signal exists.
/// 3. **回流** — what this conversation handed to the speaking channel, with
///    the water frozen into [ConversationEchoTally].
///
/// Everything here is presentation. No status is re-decided, no text is
/// invented, and nothing pretends to be finished before the controller says
/// it is (P4).

/// What this conversation gave back, counted off controller state.
@immutable
class ConversationDebriefReadout {
  const ConversationDebriefReadout({
    required this.assistantTurns,
    required this.learnerTurns,
    required this.learnerOutputTurns,
    required this.transcribingTurns,
    required this.lostTurns,
  });

  /// Turns the other voice took.
  final int assistantTurns;

  /// Turns you took, whatever became of them.
  final int learnerTurns;

  /// Yours that came back with a completed local transcript — the only ones
  /// the backend treats as authoritative learner output, and therefore the
  /// only ones that carry words into the speaking channel.
  final int learnerOutputTurns;

  /// Yours whose local transcription has not finished. The debrief opens
  /// while these are still running; it says so rather than rounding up.
  final int transcribingTurns;

  /// Yours that ended without ever becoming output — the transcript failed,
  /// or the turn was cut short. These are the amber targets.
  final int lostTurns;

  /// False while local Whisper is still working. The readout stays provisional
  /// until this is true; it never announces a final tally early.
  bool get settled => transcribingTurns == 0;

  @override
  bool operator ==(Object other) =>
      other is ConversationDebriefReadout &&
      other.assistantTurns == assistantTurns &&
      other.learnerTurns == learnerTurns &&
      other.learnerOutputTurns == learnerOutputTurns &&
      other.transcribingTurns == transcribingTurns &&
      other.lostTurns == lostTurns;

  @override
  int get hashCode => Object.hash(
    assistantTurns,
    learnerTurns,
    learnerOutputTurns,
    transcribingTurns,
    lostTurns,
  );

  @override
  String toString() =>
      'ConversationDebriefReadout(assistant: $assistantTurns, learner: '
      '$learnerTurns, output: $learnerOutputTurns, transcribing: '
      '$transcribingTurns, lost: $lostTurns)';
}

/// Learner turn statuses that mean "local Whisper has not answered yet".
/// `local_transcription_pending` is the live controller's name for it,
/// `awaiting_local_transcript` the persisted one a replayed session carries.
bool conversationTurnIsTranscribing(RealtimeConversationItem item) =>
    item.role == 'learner' &&
    (item.status == 'local_transcription_pending' ||
        item.status == 'awaiting_local_transcript' ||
        item.status == 'streaming' ||
        item.status == 'active');

/// A learner turn that ended without becoming learner output.
///
/// **This is the only 靶子 rule, and it is a backend fact, not a judgment.**
/// The design note asks for 「你卡住/求助/换说法的地方」 and answers its own
/// question in the same row: 只标既有后端信号,前端不新造判定. No backend signal
/// for hesitation exists today, so the frontend does not invent one. What does
/// exist, per turn, is whether the turn closed the loop: `finalized` with a
/// local transcript did, `failed` and `interrupted` did not. Those are the
/// places this conversation did not reach your portrait — worth chasing, and
/// true.
bool conversationTurnIsTarget(RealtimeConversationItem item) =>
    item.role == 'learner' &&
    (item.status == 'failed' || item.status == 'interrupted');

/// A learner turn whose local transcript arrived — authoritative output.
bool conversationTurnIsLearnerOutput(RealtimeConversationItem item) =>
    item.role == 'learner' &&
    item.status == 'finalized' &&
    item.localText.trim().isNotEmpty;

ConversationDebriefReadout conversationDebriefReadoutOf(
  RealtimeConversationState state,
) {
  var assistant = 0, learner = 0, output = 0, transcribing = 0, lost = 0;
  for (final item in state.items) {
    if (item.role != 'learner') {
      assistant++;
      continue;
    }
    learner++;
    if (conversationTurnIsLearnerOutput(item)) {
      output++;
    } else if (conversationTurnIsTranscribing(item)) {
      transcribing++;
    } else if (conversationTurnIsTarget(item)) {
      lost++;
    }
  }
  return ConversationDebriefReadout(
    assistantTurns: assistant,
    learnerTurns: learner,
    learnerOutputTurns: output,
    transcribingTurns: transcribing,
    lostTurns: lost,
  );
}

List<RealtimeConversationItem> conversationDebriefTargetsOf(
  RealtimeConversationState state,
) => state.items.where(conversationTurnIsTarget).toList();

/// Section 3 · 回流 — the read-out, and the water frozen into a bar.
///
/// P3 (「可看的仪表读数,不是弹出的成绩单」): numbers you may read, no verdict,
/// no score. P4: while transcription is running the section says so and calls
/// its own count provisional.
class ConversationDebriefReflow extends StatelessWidget {
  const ConversationDebriefReflow({
    super.key,
    required this.readout,
    this.onOpenVocabulary,
  });

  final ConversationDebriefReadout readout;

  /// 词汇本 — where the words this conversation carried into the speaking
  /// channel now live. Null keeps the section a pure read-out (tests, hosts
  /// without the learning routes).
  final VoidCallback? onOpenVocabulary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('conversation-debrief-readout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('realtimeDebriefWhatCameBack'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: ListenSpacing.gap12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConversationEchoTally(
              key: const ValueKey('conversation-debrief-tally'),
              moonTurns: readout.assistantTurns,
              learnerTurns: readout.learnerTurns,
              learnerOutputTurns: readout.learnerOutputTurns,
            ),
            const SizedBox(width: ListenSpacing.gap24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l
                        .text('realtimeDebriefReflow')
                        .replaceAll('{output}', '${readout.learnerOutputTurns}')
                        .replaceAll('{total}', '${readout.learnerTurns}'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (!readout.settled) ...[
                    const SizedBox(height: ListenSpacing.gap6),
                    Text(
                      key: const ValueKey('conversation-debrief-provisional'),
                      l
                          .text('realtimeDebriefProvisional')
                          .replaceAll(
                            '{count}',
                            '${readout.transcribingTurns}',
                          ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (onOpenVocabulary != null) ...[
                    const SizedBox(height: ListenSpacing.gap8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey(
                          'conversation-debrief-open-vocabulary',
                        ),
                        onPressed: onOpenVocabulary,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: Text(l.text('realtimeDebriefOpenVocabulary')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// P4 made visible: while local Whisper is still running the debrief shows a
/// determinate bar over the turns it actually knows about.
///
/// Determinate on purpose — the counts are real, so a spinner would hide
/// information the learner already has. Nothing here is animated beyond the
/// indicator's own progress, so there is no motion to reduce.
class ConversationDebriefProgress extends StatelessWidget {
  const ConversationDebriefProgress({super.key, required this.readout});

  final ConversationDebriefReadout readout;

  @override
  Widget build(BuildContext context) {
    final done = readout.learnerTurns - readout.transcribingTurns;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('conversation-debrief-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l
              .text('realtimeDebriefTranscribingProgress')
              .replaceAll('{done}', '$done')
              .replaceAll('{total}', '${readout.learnerTurns}'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: ListenSpacing.gap6),
        LinearProgressIndicator(
          value: readout.learnerTurns == 0 ? 0 : done / readout.learnerTurns,
        ),
      ],
    );
  }
}

/// Section 2 · 靶子 — amber, and only where the loop stayed open.
///
/// 琥珀只留给靶子时刻 (charter): the color is spent here and nowhere else on
/// this page. Each target offers the one-click way on — into 我的表达, with
/// whatever text actually exists prefilled.
class ConversationDebriefTargets extends StatelessWidget {
  const ConversationDebriefTargets({
    super.key,
    required this.targets,
    this.onSaveExpression,
    this.onRetryTranscription,
  });

  final List<RealtimeConversationItem> targets;

  /// Opens 我的表达 with this turn's text. Null keeps the section a read-out.
  final ValueChanged<RealtimeConversationItem>? onSaveExpression;

  /// Reruns a turn's local transcription. Only ever reachable for a failure
  /// the backend itself marked retryable.
  final ValueChanged<RealtimeConversationItem>? onRetryTranscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('realtimeDebriefTargetsTitle'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        if (targets.isEmpty)
          Text(
            key: const ValueKey('conversation-debrief-targets-empty'),
            l.text('realtimeDebriefTargetsEmpty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final item in targets) ...[
            _TargetCard(
              item: item,
              onSaveExpression: onSaveExpression,
              onRetryTranscription: onRetryTranscription,
            ),
            const SizedBox(height: ListenSpacing.gap8),
          ],
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.item,
    required this.onSaveExpression,
    required this.onRetryTranscription,
  });

  final RealtimeConversationItem item;
  final ValueChanged<RealtimeConversationItem>? onSaveExpression;
  final ValueChanged<RealtimeConversationItem>? onRetryTranscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // The stage's amber, spent on the one thing it is reserved for.
    final amber = theme.colorScheme.secondary;
    final guidance = item.providerText.trim();
    final failure = item.failure;
    return DecoratedBox(
      key: ValueKey('conversation-debrief-target-${item.sequence}'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: amber, width: 3)),
        color: amber.withValues(alpha: 0.06),
        borderRadius: ListenRadii.panelBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text(switch (item.status) {
                'interrupted' => 'realtimeDebriefTargetEndedEarly',
                _ => 'realtimeDebriefTargetNoTranscript',
              }),
              style: theme.textTheme.labelLarge?.copyWith(color: amber),
            ),
            if (guidance.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap8),
              // All that survives of this turn is the provider's live caption,
              // and it stays labelled as guidance: it is not your output, and
              // saving it is you writing something down, not the portrait
              // gaining evidence.
              Text(
                l
                    .text('realtimeDebriefGuidanceQuote')
                    .replaceAll('{text}', guidance),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // Why the loop stayed open, as diagnostics — closed by default and
            // never as the card's prose.
            if (failure != null)
              ConversationTurnFailureNotice(
                failure: failure,
                onRetry: onRetryTranscription == null
                    ? null
                    : () => onRetryTranscription!(item),
              ),
            if (onSaveExpression != null) ...[
              const SizedBox(height: ListenSpacing.gap8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey(
                    'conversation-debrief-save-expression-${item.sequence}',
                  ),
                  onPressed: () => onSaveExpression!(item),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l.text('realtimeDebriefSaveExpression')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section 1 · 对话 — one card per turn, the local transcript as the body.
class ConversationDebriefTurnCard extends StatefulWidget {
  const ConversationDebriefTurnCard({
    super.key,
    required this.item,
    this.onRetryTranscription,
  });

  final RealtimeConversationItem item;

  /// Reruns this turn's local transcription. Null in hosts that cannot rerun
  /// it; the affordance additionally requires the backend to have called the
  /// failure retryable.
  final ValueChanged<RealtimeConversationItem>? onRetryTranscription;

  @override
  State<ConversationDebriefTurnCard> createState() =>
      _ConversationDebriefTurnCardState();
}

class _ConversationDebriefTurnCardState
    extends State<ConversationDebriefTurnCard> {
  bool _guidanceOpen = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final learner = item.role == 'learner';
    // 色的角色分配 (charter): your language is the signal teal, the other
    // person's is 月白. The same two lights the stage used, at rest.
    final edge = learner ? ListenColors.overlaySignal : ListenColors.moonWhite;
    final local = item.localText.trim();
    final guidance = item.providerText.trim();
    return DecoratedBox(
      key: ValueKey('conversation-debrief-turn-${item.sequence}'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: edge, width: 3)),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: ListenRadii.panelBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text(
                learner
                    ? 'realtimeDebriefLearnerLabel'
                    : 'realtimeTurnOtherVoice',
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: edge.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: ListenSpacing.gap4),
            if (learner)
              // The learner's body is the local transcript or nothing. It is
              // never back-filled from the provider caption: an unfinished
              // turn says it is unfinished (P4) instead of borrowing words
              // that were never learner output.
              local.isNotEmpty
                  ? SelectableText(local)
                  : Text(
                      key: ValueKey(
                        'conversation-debrief-pending-${item.sequence}',
                      ),
                      l.text(switch (item.status) {
                        'failed' => 'realtimeDebriefTurnNotTranscribed',
                        'interrupted' => 'realtimeDebriefTurnEndedEarly',
                        _ => 'realtimeTurnTranscribingLocally',
                      }),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
            else
              SelectableText(
                guidance.isEmpty ? l.text('realtimeDebriefNoText') : guidance,
              ),
            if (learner && guidance.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap6),
              // 「provider caption 默认折叠(guidance 版本按需展开)」: kept, never
              // level with the transcript. A plain toggle rather than an
              // expansion animation — there is no motion here to reduce.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey(
                    'conversation-debrief-guidance-toggle-${item.sequence}',
                  ),
                  onPressed: () =>
                      setState(() => _guidanceOpen = !_guidanceOpen),
                  child: Text(
                    l.text(
                      _guidanceOpen
                          ? 'realtimeDebriefHideGuidance'
                          : 'realtimeDebriefShowGuidance',
                    ),
                  ),
                ),
              ),
              if (_guidanceOpen)
                Text(
                  key: ValueKey(
                    'conversation-debrief-guidance-${item.sequence}',
                  ),
                  guidance,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            // The failure is already stated as this turn's body ("the local
            // transcript did not come back"). What is left is a rerun, when
            // the backend allows one, and the diagnostics — which stay closed
            // and never join the transcript they sit under. This is the line
            // that used to print `Could not process learner turn:
            // HttpException: {"code":…,"correlation_id":…}, uri = http://
            // 127.0.0.1:…` in the learner's own voice.
            if (item.failure != null)
              ConversationTurnFailureNotice(
                failure: item.failure!,
                onRetry: widget.onRetryTranscription == null
                    ? null
                    : () => widget.onRetryTranscription!(item),
              ),
          ],
        ),
      ),
    );
  }
}
