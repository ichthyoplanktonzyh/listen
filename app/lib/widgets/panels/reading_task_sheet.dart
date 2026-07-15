import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/reading_task_controller.dart';
import '../../localization.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';

const _verdicts = ['covered', 'partial', 'missing', 'uncertain'];

/// Reusable paragraph-task content: edit the rubric template once,
/// answer with the text visible, self-assess per point, and correct saved
/// verdicts through adjudication. Everything routes through the 3.11
/// append-only semantic family; nothing here touches word-level learning.
class ReadingTaskSheet extends StatefulWidget {
  const ReadingTaskSheet({
    super.key,
    required this.controller,
    required this.api,
    required this.audioPlayCount,
    this.onPlaySegment,
    this.onClose,
    this.expanded = false,
  });

  final ReadingTaskController controller;
  final LocalApi api;

  /// Honest replay count for the paragraph (feeds the attempt's
  /// `audio_play_count` condition). For the listening retell this counts
  /// plays started from [onPlaySegment].
  final int Function() audioPlayCount;

  /// Plays the paragraph audio (listening retell only). The reading flow
  /// leaves this null — replays there happen from the reading view chips.
  final VoidCallback? onPlaySegment;
  final VoidCallback? onClose;
  final bool expanded;

  @override
  State<ReadingTaskSheet> createState() => _ReadingTaskSheetState();
}

class _ReadingTaskSheetState extends State<ReadingTaskSheet> {
  final TextEditingController _answer = TextEditingController();

  ReadingTaskState get _state => widget.controller.state;

  @override
  void initState() {
    super.initState();
    _answer.text = _state.draftAnswer;
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final colors = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: widget.expanded ? double.infinity : 560,
            ),
            child: Column(
              mainAxisSize: widget.expanded
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      l.text('readingTaskTitle'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (_state.busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (_state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _state.error!,
                      style: TextStyle(color: colors.error, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: switch (_state.phase) {
                      'editing' => _editing(l, colors),
                      'answering' => _answering(l, colors),
                      'assessing' => _assessing(l, colors),
                      'done' => _done(l, colors),
                      _ => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  // ── editing: user trims the localized template before it becomes v1 ──

  Widget _editing(AppLocalizations l, ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l.text(
          _state.isListening
              ? 'readingTaskListenEditHint'
              : 'readingTaskEditHint',
        ),
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < _state.draftPoints.length; i++)
        _draftPointRow(l, colors, i),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _state.busy
            ? null
            : () => unawaited(widget.controller.saveRubric(widget.api)),
        icon: const Icon(Icons.save_outlined),
        label: Text(l.text('readingTaskSavePoints')),
      ),
    ],
  );

  Widget _draftPointRow(AppLocalizations l, ColorScheme colors, int index) {
    final point = _state.draftPoints[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: l.text(
              point.importance == 'required'
                  ? 'readingTaskPointRequired'
                  : 'readingTaskPointOptional',
            ),
            child: IconButton(
              icon: Icon(
                point.importance == 'required' ? Icons.star : Icons.star_border,
                size: 18,
                color: point.importance == 'required'
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              onPressed: () => widget.controller.updateDraftPoint(
                index,
                RubricPointView(
                  pointId: point.pointId,
                  importance: point.importance == 'required'
                      ? 'optional'
                      : 'required',
                  statement: point.statement,
                  acceptedParaphraseNotes: point.acceptedParaphraseNotes,
                ),
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('draft-point-${point.pointId}'),
              initialValue: point.statement,
              maxLines: null,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true),
              onChanged: (value) => widget.controller.updateDraftPoint(
                index,
                RubricPointView(
                  pointId: point.pointId,
                  importance: point.importance,
                  statement: value,
                  acceptedParaphraseNotes: point.acceptedParaphraseNotes,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: _state.draftPoints.length <= 1
                ? null
                : () => widget.controller.removeDraftPoint(index),
          ),
        ],
      ),
    );
  }

  // ── answering: reading shows the prompts; the listening retell hides
  // them (they paraphrase the content) and offers segment playback ──

  Widget _answering(AppLocalizations l, ColorScheme colors) {
    final rubric = _state.rubric!;
    final listening = _state.isListening;
    final plays = widget.audioPlayCount();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_state.pastAttemptCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l
                  .text('readingTaskPastAttempts')
                  .replaceFirst('{n}', '${_state.pastAttemptCount}'),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
        if (listening) ...[
          Text(
            l.text('readingTaskListenAnswerHint'),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ActionChip(
                key: const ValueKey('reading-task-play-segment'),
                avatar: Icon(Icons.play_arrow, size: 16, color: colors.primary),
                label: Text(l.text('readingTaskListenPlay')),
                onPressed: widget.onPlaySegment,
              ),
              if (plays > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '×$plays',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ] else
          for (final point in rubric.points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    point.importance == 'required'
                        ? Icons.star
                        : Icons.star_border,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      point.statement,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('reading-task-answer'),
          controller: _answer,
          onChanged: widget.controller.updateAnswerDraft,
          maxLines: 5,
          minLines: 3,
          decoration: InputDecoration(
            hintText: l.text(
              listening ? 'readingTaskListenTypeHint' : 'readingTaskAnswerHint',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          // A listening retell without a single play would fake its
          // conditions; require one honest listen first.
          onPressed: _state.busy || (listening && plays < 1)
              ? null
              : () => unawaited(
                  widget.controller.submitAnswer(
                    widget.api,
                    _answer.text,
                    audioPlayCount: widget.audioPlayCount(),
                  ),
                ),
          icon: const Icon(Icons.send_outlined),
          label: Text(l.text('readingTaskSubmitAnswer')),
        ),
      ],
    );
  }

  // ── assessing: per-point verdict against the visible answer ──

  Widget _assessing(AppLocalizations l, ColorScheme colors) {
    final rubric = _state.rubric!;
    final answer = _state.attempt!.responses.single.transcript;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(answer, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 6),
        Text(
          l.text('readingTaskAssessHint'),
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (final point in rubric.points) _assessRow(l, point),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _state.busy || !_state.allPointsJudged
              ? null
              : () => unawaited(
                  widget.controller.submitSelfAssessment(widget.api),
                ),
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(l.text('readingTaskSubmitAssessment')),
        ),
      ],
    );
  }

  Widget _assessRow(AppLocalizations l, RubricPointView point) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(point.statement, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 3),
        Wrap(
          spacing: 6,
          children: [
            for (final verdict in _verdicts)
              ChoiceChip(
                key: ValueKey('verdict-${point.pointId}-$verdict'),
                label: Text(_verdictLabel(l, verdict)),
                labelStyle: const TextStyle(fontSize: 12),
                selected: _state.draftVerdicts[point.pointId] == verdict,
                onSelected: (_) =>
                    widget.controller.setVerdict(point.pointId, verdict),
              ),
          ],
        ),
      ],
    ),
  );

  // ── done: saved verdicts + adjudication corrections ──

  Widget _done(AppLocalizations l, ColorScheme colors) {
    final rubric = _state.rubric!;
    final judgment = _state.judgment!;
    String effectiveVerdict(String pointId) {
      for (final adjudication in _state.adjudications.reversed) {
        if (adjudication.pointId == pointId) return adjudication.userVerdict;
      }
      return judgment.verdictFor(pointId) ?? 'uncertain';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('readingTaskDone'),
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 8),
        for (final point in rubric.points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    point.statement,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _verdictLabel(l, effectiveVerdict(point.pointId)),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: switch (effectiveVerdict(point.pointId)) {
                      'covered' => Colors.green.shade700,
                      'partial' => Colors.orange.shade800,
                      'missing' => colors.error,
                      _ => colors.onSurfaceVariant,
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('adjudicate-${point.pointId}'),
                  tooltip: l.text('readingTaskCorrect'),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  onSelected: (verdict) => unawaited(
                    widget.controller.adjudicate(
                      widget.api,
                      pointId: point.pointId,
                      userVerdict: verdict,
                    ),
                  ),
                  itemBuilder: (context) => [
                    for (final verdict in _verdicts)
                      if (verdict != effectiveVerdict(point.pointId))
                        PopupMenuItem(
                          value: verdict,
                          child: Text(_verdictLabel(l, verdict)),
                        ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            child: Text(l.text('readingTaskClose')),
          ),
        ),
      ],
    );
  }

  String _verdictLabel(AppLocalizations l, String verdict) =>
      l.text(switch (verdict) {
        'covered' => 'verdictCovered',
        'partial' => 'verdictPartial',
        'missing' => 'verdictMissing',
        _ => 'verdictUncertain',
      });
}
