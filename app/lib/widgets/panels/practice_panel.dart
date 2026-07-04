import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/practice_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';

class PracticePanel extends StatefulWidget {
  const PracticePanel({
    super.key,
    required this.controller,
    required this.currentCue,
    required this.diagnosis,
    required this.canCloze,
    required this.canChunkDictation,
    required this.hasEstimatedWordTiming,
    required this.onStartCloze,
    required this.onStartChunkDictation,
    required this.onStartSentenceDictation,
    required this.onMarkStuckPoint,
    required this.onSkipStuckPoint,
    required this.onReplay,
    required this.onSubmit,
    required this.onSaveReview,
    required this.onCompleteSession,
    required this.onReplayStuckPoint,
    required this.onCloseStuckPoint,
    required this.onOpenDiagnosis,
  });

  final PracticeController controller;
  final Cue? currentCue;
  final Diagnosis? diagnosis;
  final bool canCloze;
  final bool canChunkDictation;
  final bool hasEstimatedWordTiming;
  final Future<void> Function() onStartCloze;
  final Future<void> Function() onStartChunkDictation;
  final Future<void> Function() onStartSentenceDictation;
  final Future<void> Function() onMarkStuckPoint;
  final Future<void> Function() onSkipStuckPoint;
  final Future<void> Function() onReplay;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSaveReview;
  final Future<void> Function() onCompleteSession;
  final Future<void> Function(StuckPointSummary point) onReplayStuckPoint;
  final Future<void> Function(StuckPointSummary point) onCloseStuckPoint;
  final Future<void> Function() onOpenDiagnosis;

  @override
  State<PracticePanel> createState() => _PracticePanelState();
}

class _PracticePanelState extends State<PracticePanel> {
  late final TextEditingController _answerController;

  PracticeController get controller => widget.controller;
  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController(text: controller.answer);
  }

  @override
  void didUpdateWidget(covariant PracticePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_answerController.text != controller.answer) {
      _answerController.value = TextEditingValue(
        text: controller.answer,
        selection: TextSelection.collapsed(offset: controller.answer.length),
      );
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Material(
      color: const Color(0xff151a20),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _practiceLaunchers(),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (state.busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 14),
          if (state.draft == null || state.item == null)
            _emptyState()
          else if (state.attempt == null)
            _prompt(state)
          else
            _result(state),
          _summary(state),
        ],
      ),
    );
  }

  Widget _practiceLaunchers() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      Tooltip(
        message: widget.canCloze
            ? l.text('practiceClozeTooltip')
            : l.text('practiceClozeUnavailable'),
        child: FilledButton.tonalIcon(
          onPressed:
              controller.busy || widget.currentCue == null || !widget.canCloze
              ? null
              : () => unawaited(widget.onStartCloze()),
          icon: const Icon(Icons.text_fields),
          label: Text(l.text('clozePractice')),
        ),
      ),
      Tooltip(
        message: widget.canChunkDictation
            ? l.text('practiceChunkTooltip')
            : l.text('practiceChunkFallbackTooltip'),
        child: OutlinedButton.icon(
          onPressed: controller.busy || widget.currentCue == null
              ? null
              : () => unawaited(widget.onStartChunkDictation()),
          icon: const Icon(Icons.segment),
          label: Text(l.text('chunkDictation')),
        ),
      ),
      OutlinedButton.icon(
        onPressed: controller.busy || widget.currentCue == null
            ? null
            : () => unawaited(widget.onStartSentenceDictation()),
        icon: const Icon(Icons.short_text),
        label: Text(l.text('sentenceDictation')),
      ),
      OutlinedButton.icon(
        onPressed: controller.busy || widget.currentCue == null
            ? null
            : () => unawaited(widget.onMarkStuckPoint()),
        icon: const Icon(Icons.flag_outlined),
        label: Text(l.text('markStuckPoint')),
      ),
      OutlinedButton.icon(
        onPressed: controller.busy || widget.currentCue == null
            ? null
            : () => unawaited(widget.onSkipStuckPoint()),
        icon: const Icon(Icons.skip_next),
        label: Text(l.text('skipStuckPoint')),
      ),
    ],
  );

  Widget _emptyState() => Text(
    widget.currentCue == null
        ? l.text('practiceNeedsSentence')
        : l.text('practiceChoosePrompt'),
    style: const TextStyle(color: Color(0xffaab4c0)),
  );

  Widget _prompt(PracticeState state) {
    final draft = state.draft!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(draft),
        if (draft.degradedMessage != null || widget.hasEstimatedWordTiming)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              draft.degradedMessage ?? l.text('practiceEstimatedTiming'),
              style: const TextStyle(fontSize: 12, color: Color(0xffffc857)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            draft.kind == 'cloze'
                ? draft.promptText
                : l.text('practiceListenThenType'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (draft.kind != 'cloze')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.text('practiceHiddenText'),
              style: const TextStyle(fontSize: 12, color: Color(0xffaab4c0)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: TextField(
            controller: _answerController,
            minLines: draft.kind == 'cloze' ? 1 : 3,
            maxLines: draft.kind == 'cloze' ? 1 : 5,
            enabled: !controller.busy,
            decoration: InputDecoration(
              labelText: l.text('practiceAnswer'),
              border: const OutlineInputBorder(),
            ),
            onChanged: controller.setAnswer,
            onSubmitted: (_) => unawaited(widget.onSubmit()),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: controller.createReviewOnFailure,
          onChanged: controller.busy
              ? null
              : (value) => controller.setCreateReviewOnFailure(value ?? true),
          title: Text(l.text('createReviewOnFailure')),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => unawaited(widget.onReplay()),
              icon: const Icon(Icons.replay),
              label: Text(l.text('replay')),
            ),
            FilledButton.icon(
              onPressed:
                  controller.busy || _answerController.text.trim().isEmpty
                  ? null
                  : () => unawaited(widget.onSubmit()),
              icon: const Icon(Icons.check),
              label: Text(l.text('submit')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _result(PracticeState state) {
    final attempt = state.attempt!;
    final correct = attempt.result == 'correct';
    final reviewSaved = attempt.generatedReviewItemIds.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(state.draft!),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '${l.text('practiceResult')}: ${_resultLabel(attempt.result)}'
            '${attempt.score == null ? '' : ' · ${(attempt.score! * 100).round()}%'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            attempt.evaluation.summary,
            style: const TextStyle(color: Color(0xffaab4c0)),
          ),
        ),
        if (attempt.evaluation.tokenResults.isNotEmpty) _diff(attempt),
        if (widget.diagnosis?.hints.isNotEmpty ?? false) _diagnosisSummary(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => unawaited(widget.onReplay()),
              icon: const Icon(Icons.replay),
              label: Text(l.text('replay')),
            ),
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : controller.clearResultForRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.text('retryPractice')),
            ),
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => unawaited(widget.onOpenDiagnosis()),
              icon: const Icon(Icons.analytics_outlined),
              label: Text(l.text('openDiagnosis')),
            ),
            FilledButton.tonalIcon(
              onPressed: correct || reviewSaved || controller.busy
                  ? null
                  : () => unawaited(widget.onSaveReview()),
              icon: Icon(
                reviewSaved ? Icons.bookmark_added : Icons.bookmark_add,
              ),
              label: Text(
                reviewSaved ? l.text('savedToReview') : l.text('saveToReview'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary(PracticeState state) {
    final summary = state.summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    final openPoints = summary.stuckPoints
        .where(
          (point) => point.status == 'unexplained' || point.status == 'marked',
        )
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xff2e3742)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.summarize_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.text('sessionSummary'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => unawaited(widget.onCompleteSession()),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text(
                      summary.session.endedAtMs == null
                          ? l.text('finishIntensive')
                          : l.text('intensiveFinished'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _countChip(l.text('summaryStuck'), summary.stuckCount),
                  _countChip(l.text('summaryResolved'), summary.resolvedCount),
                  _countChip(
                    l.text('summaryVerified'),
                    summary.activeVerifiedCount,
                  ),
                  _countChip(l.text('summaryReview'), summary.reviewCount),
                  _countChip(
                    l.text('summaryUnexplained'),
                    summary.unexplainedCount,
                  ),
                ],
              ),
              if (summary.attributionCounts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in summary.attributionCounts.take(3))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${l.diagnosisReason(item.reason ?? item.kind)} · ${item.count}',
                        ),
                      ),
                  ],
                ),
              ],
              if (openPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l.text('openStuckPoints'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                for (final point in openPoints) _openPointRow(point),
              ],
              if (summary.familiarMaterialMarked)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    l.text('familiarMaterialMarked'),
                    style: const TextStyle(color: Color(0xff7bd88f)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String label, int value) =>
      Chip(visualDensity: VisualDensity.compact, label: Text('$label $value'));

  Widget _openPointRow(StuckPointSummary point) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            point.label ?? point.targetKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xffd7dee8)),
          ),
        ),
        IconButton(
          tooltip: l.text('replay'),
          onPressed:
              point.playbackStartMs == null || point.playbackEndMs == null
              ? null
              : () => unawaited(widget.onReplayStuckPoint(point)),
          icon: const Icon(Icons.replay),
        ),
        IconButton(
          tooltip: l.text('closeStuckPoint'),
          onPressed: controller.busy
              ? null
              : () => unawaited(widget.onCloseStuckPoint(point)),
          icon: const Icon(Icons.check_circle_outline),
        ),
      ],
    ),
  );

  Widget _header(PracticeDraft draft) => Row(
    children: [
      Icon(draft.kind == 'cloze' ? Icons.text_fields : Icons.keyboard),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          draft.kind == 'cloze'
              ? l.text('clozePractice')
              : draft.targetKind == 'chunk'
              ? l.text('chunkDictation')
              : l.text('sentenceDictation'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      if (draft.focusLabel != null)
        Text(
          draft.focusLabel!,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xffaab4c0)),
        ),
    ],
  );

  Widget _diff(PracticeAttempt attempt) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final token in attempt.evaluation.tokenResults)
          Tooltip(
            message:
                '${l.text('expected')}: ${token.expected ?? '(empty)'}\n'
                '${l.text('youTyped')}: ${token.actual ?? '(empty)'}',
            child: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: _resultColor(
                token.result,
              ).withValues(alpha: 0.18),
              side: BorderSide(
                color: _resultColor(token.result).withValues(alpha: 0.48),
              ),
              label: Text(_diffLabel(token)),
            ),
          ),
      ],
    ),
  );

  Widget _diagnosisSummary() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('possibleWhy'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final hint in widget.diagnosis!.hints.take(3))
          Text(
            '• ${l.diagnosis(hint.kind)}',
            style: const TextStyle(color: Color(0xffaab4c0)),
          ),
      ],
    ),
  );

  String _resultLabel(String result) => switch (result) {
    'correct' => l.text('practiceCorrect'),
    'partial' => l.text('practicePartial'),
    'incorrect' => l.text('practiceIncorrect'),
    'skipped' => l.text('practiceSkipped'),
    _ => result,
  };

  String _diffLabel(PracticeTokenEvaluation token) => switch (token.result) {
    'correct' => token.expected ?? token.actual ?? '',
    'missing' => '- ${token.expected ?? ''}',
    'extra' => '+ ${token.actual ?? ''}',
    'mismatch' =>
      '${token.expected ?? '(empty)'} -> ${token.actual ?? '(empty)'}',
    _ => token.actual ?? token.expected ?? '',
  };

  Color _resultColor(String result) => switch (result) {
    'correct' => Colors.greenAccent,
    'missing' => Colors.orangeAccent,
    'extra' => Colors.lightBlueAccent,
    'mismatch' => Colors.redAccent,
    _ => Colors.white70,
  };
}
