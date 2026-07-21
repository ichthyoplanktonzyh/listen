import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/speaking_task_controller.dart';
import '../../localization.dart';
import '../../services/api_service.dart';
import 'llm_feedback_assist.dart';

class SpeakingTargetCandidate {
  const SpeakingTargetCandidate({
    required this.lexicalEntryId,
    required this.surfaceForm,
  });

  final String lexicalEntryId;
  final String surfaceForm;
}

/// Whole-scene Speaking host. Each phase gets the space it needs; transcript
/// and feedback are absent until the state machine makes them available.
class SpeakingTaskStudio extends StatelessWidget {
  const SpeakingTaskStudio({
    super.key,
    required this.controller,
    required this.api,
    required this.onPlaySource,
    required this.onPlayRecording,
    required this.onAcquireRecordingFocus,
    required this.onShowRetelling,
    required this.onShowRoleReply,
    required this.onOpenL1Check,
    required this.onOpenRealtimeConversation,
    this.targetCandidates = const [],
    required this.onClose,
  });

  final SpeakingTaskController controller;
  final LocalApi api;
  final Future<void> Function() onPlaySource;
  final Future<void> Function() onPlayRecording;
  final Future<void> Function() onAcquireRecordingFocus;
  final Future<void> Function() onShowRetelling;
  final Future<void> Function(String assistance) onShowRoleReply;
  final Future<void> Function() onOpenL1Check;
  final VoidCallback onOpenRealtimeConversation;
  final List<SpeakingTargetCandidate> targetCandidates;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.surface,
        child: Column(
          children: [
            _header(context, state, colors),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _phase(context, state),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _header(
    BuildContext context,
    SpeakingTaskState state,
    ColorScheme colors,
  ) {
    final l = AppLocalizations.of(context);
    const stages = ['listening', 'recording', 'reviewing', 'done'];
    final normalized = switch (state.phase) {
      'transcribing' => 'recording',
      'ready_feedback' => 'reviewing',
      _ => state.phase,
    };
    final current = stages.indexOf(normalized).clamp(0, stages.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('speaking-task-back'),
              tooltip: l.text('speakingClose'),
              onPressed: state.busy ? null : () => onClose(),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < stages.length; i++)
                    _StageLabel(
                      index: i + 1,
                      label: l.text(switch (stages[i]) {
                        'listening' => 'speakingStageListen',
                        'recording' => 'speakingStageRecord',
                        'reviewing' => 'speakingStageReview',
                        _ => 'speakingStageDone',
                      }),
                      active: i == current,
                      complete: i < current,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phase(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    if (state.busy && state.phase == 'idle') {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) ...[
          _Notice(text: state.error!, error: true),
          const SizedBox(height: 16),
        ],
        switch (state.phase) {
          'listening' => _listening(context, state),
          'recording' => _recording(context, state),
          'transcribing' => _transcribing(context),
          'reviewing' => _reviewing(context, state),
          'ready_feedback' => _readyFeedback(context, state),
          'done' => _done(context, state),
          _ => Text(l.text('speakingPreparing')),
        },
      ],
    );
  }

  Widget _listening(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: SpeakingTaskController.retellingKind,
              label: Text(l.text('speakingModeRetelling')),
              icon: const Icon(Icons.record_voice_over_outlined),
            ),
            ButtonSegment(
              value: SpeakingTaskController.roleReplyKind,
              label: Text(l.text('speakingModeRoleReply')),
              icon: const Icon(Icons.forum_outlined),
            ),
          ],
          selected: {state.kind},
          onSelectionChanged: state.busy || state.source?.recall == 'delayed'
              ? null
              : (selected) {
                  if (selected.single == SpeakingTaskController.roleReplyKind) {
                    onShowRoleReply('full_sentence');
                  } else {
                    onShowRetelling();
                  }
                },
        ),
        if (state.kind == SpeakingTaskController.roleReplyKind) ...[
          const SizedBox(height: 16),
          Text(l.text('speakingAssistanceLabel')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final value in const [
                'full_sentence',
                'keywords',
                'no_text',
              ])
                ChoiceChip(
                  label: Text(l.text('speakingAssistance_$value')),
                  selected: state.assistance == value,
                  onSelected: state.busy ? null : (_) => onShowRoleReply(value),
                ),
            ],
          ),
          if (state.assistance != 'no_text' &&
              state.source?.promptSnapshot != null) ...[
            const SizedBox(height: 12),
            _Notice(text: state.source!.promptSnapshot!),
          ],
        ],
        const SizedBox(height: 24),
        Icon(
          Icons.headphones_rounded,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          l.text(
            state.kind == SpeakingTaskController.roleReplyKind
                ? 'speakingRoleListenTitle'
                : 'speakingListenTitle',
          ),
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l.text(
            state.kind == SpeakingTaskController.roleReplyKind
                ? 'speakingRoleListenBody'
                : 'speakingListenBody',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      controller.noteSourcePlayback();
                      await onPlaySource();
                    },
              icon: const Icon(Icons.play_arrow),
              label: Text(l.text('speakingPlaySource')),
            ),
            if (state.recording != null)
              OutlinedButton.icon(
                onPressed: onPlayRecording,
                icon: const Icon(Icons.graphic_eq),
                label: Text(l.text('speakingPlayRecording')),
              ),
            FilledButton.icon(
              key: const ValueKey('speaking-start-recording'),
              onPressed: state.busy || state.asrModelId == null
                  ? null
                  : () => controller.beginRecording(
                      acquireAudioFocus: onAcquireRecordingFocus,
                    ),
              icon: const Icon(Icons.mic),
              label: Text(l.text('speakingStartRecording')),
            ),
            OutlinedButton.icon(
              key: const ValueKey('speaking-open-realtime'),
              onPressed: state.busy || state.asrModelId == null
                  ? null
                  : onOpenRealtimeConversation,
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Realtime conversation'),
            ),
          ],
        ),
        if (state.microphonePermission != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: controller.openMicrophoneSettings,
            child: Text(l.text('speakingOpenMicSettings')),
          ),
        ],
      ],
    );
  }

  Widget _recording(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        CircleAvatar(
          radius: 58,
          backgroundColor: colors.errorContainer,
          foregroundColor: colors.onErrorContainer,
          child: const Icon(Icons.mic, size: 64),
        ),
        const SizedBox(height: 22),
        Text(
          l.text('speakingRecordingNow'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('speaking-stop-recording'),
          onPressed: state.busy ? null : () => controller.stopRecording(api),
          icon: const Icon(Icons.stop),
          label: Text(l.text('speakingStopRecording')),
        ),
        TextButton(
          onPressed: state.busy ? null : controller.cancelRecording,
          child: Text(l.text('speakingCancelRecording')),
        ),
      ],
    );
  }

  Widget _transcribing(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(l.text('speakingTranscribing')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => controller.cancelTranscription(api),
          child: Text(l.text('speakingCancelTranscription')),
        ),
      ],
    );
  }

  Widget _reviewing(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.text('speakingReviewTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(l.text('speakingReviewBody')),
        const SizedBox(height: 18),
        Text(l.text('speakingRawTranscript')),
        const SizedBox(height: 6),
        SelectableText(state.rawTranscript),
        const SizedBox(height: 18),
        TextFormField(
          key: ValueKey('corrected-${state.transcription?.id}'),
          initialValue: state.correctedTranscript,
          minLines: 3,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: l.text('speakingCorrectedTranscript'),
            border: const OutlineInputBorder(),
          ),
          onChanged: controller.updateCorrectedTranscript,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: state.asrReliability,
          decoration: InputDecoration(
            labelText: l.text('speakingAsrReliability'),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final value in const ['reliable', 'suspect', 'unreliable'])
              DropdownMenuItem(
                value: value,
                child: Text(l.text('speakingAsr_$value')),
              ),
          ],
          onChanged: (value) {
            if (value != null) controller.setAsrReliability(value);
          },
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onPlayRecording,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.text('speakingPlayRecording')),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: state.correctedTranscript.trim().isEmpty || state.busy
                  ? null
                  : () => controller.acceptTranscript(api),
              child: Text(l.text('speakingAcceptTranscript')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _readyFeedback(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    final duration = state.recording?.durationMs ?? 0;
    final latency = state.transcription?.latencyMs;
    final pauseCount = state.audioFacts?.pauses.length;
    final totalPauseMs = state.audioFacts?.totalPauseMs;
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, size: 68),
        const SizedBox(height: 16),
        Text(
          l.text('speakingSavedTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        _Notice(
          text:
              '${l.text('speakingDuration')}: ${(duration / 1000).toStringAsFixed(1)}s'
              '${pauseCount == null ? '' : ' · ${l.text('speakingPauses')}: $pauseCount / ${(totalPauseMs! / 1000).toStringAsFixed(1)}s'}'
              '${latency == null ? '' : ' · ASR ${latency}ms'} · '
              '${l.text('speakingAsr_${state.asrReliability}')} ',
        ),
        if (state.asrReliability != 'unreliable' &&
            targetCandidates.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l.text('speakingTargetPrompt')),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final target in targetCandidates)
                ActionChip(
                  avatar:
                      state.confirmedTargetIds.contains(target.lexicalEntryId)
                      ? const Icon(Icons.check, size: 16)
                      : null,
                  label: Text(target.surfaceForm),
                  onPressed:
                      state.busy ||
                          state.confirmedTargetIds.contains(
                            target.lexicalEntryId,
                          )
                      ? null
                      : () => controller.confirmSpeakingTarget(
                          api,
                          lexicalEntryId: target.lexicalEntryId,
                          surfaceForm: target.surfaceForm,
                        ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const ValueKey('speaking-finish-task'),
          onPressed: state.busy ? null : controller.finishTask,
          icon: const Icon(Icons.task_alt),
          label: Text(l.text('speakingFinishTask')),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onOpenL1Check,
          icon: const Icon(Icons.translate_outlined),
          label: Text(l.text('speakingOpenL1Check')),
        ),
        _llmFeedback(state),
      ],
    );
  }

  /// Teacher-style free-text LLM feedback (issue #9), hidden when no capable
  /// provider is configured. Ephemeral assist: nothing is stored and no
  /// verdicts are assigned.
  Widget _llmFeedback(SpeakingTaskState state) => LlmFeedbackAssist(
    visible: state.feedbackProviderId != null,
    feedback: state.llmFeedback,
    busy: state.busy,
    keyPrefix: 'speaking-task',
    onRequest: () => unawaited(controller.requestLlmFeedback(api)),
  );

  Widget _done(BuildContext context, SpeakingTaskState state) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        const Icon(Icons.task_alt, size: 72),
        const SizedBox(height: 16),
        Text(
          l.text('speakingDoneTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        _llmFeedback(state),
        if (state.source?.recall == 'delayed' &&
            !state.delayedReviewCompleted) ...[
          const SizedBox(height: 16),
          Text(l.text('speakingDelayedRatePrompt')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final rating in const ['again', 'hard', 'good'])
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.completeDelayedReview(api, rating),
                  child: Text(l.text('speakingDelayedRate_$rating')),
                ),
            ],
          ),
        ],
        if (state.delayedReviewCompleted) ...[
          const SizedBox(height: 12),
          _Notice(text: l.text('speakingDelayedReviewSaved')),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (state.canRetry)
              OutlinedButton.icon(
                onPressed: controller.retryOnce,
                icon: const Icon(Icons.replay),
                label: Text(l.text('speakingRetryOnce')),
              ),
            FilledButton(
              onPressed: onClose,
              child: Text(l.text('speakingReturnToContent')),
            ),
            if (state.source?.recall != 'delayed')
              OutlinedButton.icon(
                onPressed: state.busy || state.delayedReviewItemId != null
                    ? null
                    : () => controller.scheduleDelayedRetelling(api),
                icon: Icon(
                  state.delayedReviewItemId == null
                      ? Icons.event_repeat_outlined
                      : Icons.check,
                ),
                label: Text(
                  l.text(
                    state.delayedReviewItemId == null
                        ? 'speakingScheduleDelayed'
                        : 'speakingDelayedScheduled',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel({
    required this.index,
    required this.label,
    required this.active,
    required this.complete,
  });

  final int index;
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active || complete
              ? colors.primary
              : colors.surfaceContainerHighest,
          foregroundColor: active || complete
              ? colors.onPrimary
              : colors.onSurfaceVariant,
          child: complete
              ? const Icon(Icons.check, size: 14)
              : Text('$index', style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontWeight: active ? FontWeight.w700 : null),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          style: TextStyle(
            color: error ? colors.onErrorContainer : colors.onSurface,
          ),
        ),
      ),
    );
  }
}
