import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/writing_task_controller.dart';
import '../../localization.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';
import 'llm_judgment_assist.dart';

class WritingTaskStudio extends StatefulWidget {
  const WritingTaskStudio({
    super.key,
    required this.controller,
    required this.api,
    required this.audioPlayCount,
    required this.onKindChanged,
    required this.onPlaySource,
    this.onSpeakText,
    required this.onClose,
  });

  final WritingTaskController controller;
  final LocalApi api;
  final int Function() audioPlayCount;
  final ValueChanged<String> onKindChanged;
  final VoidCallback onPlaySource;
  final ValueChanged<String>? onSpeakText;
  final VoidCallback onClose;

  @override
  State<WritingTaskStudio> createState() => _WritingTaskStudioState();
}

class _WritingTaskStudioState extends State<WritingTaskStudio> {
  final _editor = TextEditingController();
  bool _sourceExpanded = true;
  String _lastPhase = '';

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _syncEditor(WritingTaskState state) {
    if (_lastPhase == state.phase) return;
    _lastPhase = state.phase;
    final value = state.phase == 'drafting' ? state.draft : state.revisionDraft;
    _editor.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final state = widget.controller.state;
      _syncEditor(state);
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  phase: state.phase,
                  kind: state.kind,
                  historyCount: state.pastAttemptCount,
                  onKindChanged: widget.onKindChanged,
                  onClose: widget.onClose,
                ),
                const SizedBox(height: 12),
                _SourceCard(
                  expanded: _sourceExpanded,
                  prompt: state.promptSnapshot,
                  source: state.kind == WritingTaskController.dictoglossKind
                      ? null
                      : state.source?.transcriptSnapshot,
                  previousText: state.pastAttempts.isEmpty
                      ? null
                      : state.pastAttempts.last.responses.last.transcript,
                  onPlaySource:
                      state.kind == WritingTaskController.dictoglossKind
                      ? widget.onPlaySource
                      : null,
                  onToggle: () =>
                      setState(() => _sourceExpanded = !_sourceExpanded),
                ),
                const SizedBox(height: 12),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: switch (state.phase) {
                    'idle' => const Center(child: CircularProgressIndicator()),
                    'drafting' => _editorBody(l, state, revising: false),
                    'submitted' => _submittedBody(l, state),
                    'revising' => _editorBody(l, state, revising: true),
                    'done' => _doneBody(l, state),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _editorBody(
    AppLocalizations l,
    WritingTaskState state, {
    required bool revising,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.text(revising ? 'writingYourRevision' : 'writingYourDraft'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                key: const Key('writing-editor'),
                controller: _editor,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: l.text('writingEditorHint'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: revising
                    ? widget.controller.updateRevision
                    : widget.controller.updateDraft,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('writing-read-aloud'),
                  onPressed:
                      _editor.text.trim().isEmpty || widget.onSpeakText == null
                      ? null
                      : () => widget.onSpeakText!(_editor.text.trim()),
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(l.text('readAloudSynthetic')),
                ),
                FilledButton.icon(
                  onPressed:
                      state.busy ||
                          _editor.text.trim().isEmpty ||
                          (!revising &&
                              state.kind ==
                                  WritingTaskController.dictoglossKind &&
                              widget.audioPlayCount() == 0)
                      ? null
                      : () => revising
                            ? widget.controller.submitRevision(
                                widget.api,
                                audioPlayCount: widget.audioPlayCount(),
                              )
                            : widget.controller.submitDraft(
                                widget.api,
                                audioPlayCount: widget.audioPlayCount(),
                              ),
                  icon: state.busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    l.text(
                      revising ? 'writingSubmitRevision' : 'writingSubmitDraft',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (revising) ...[
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: _FeedbackList(controller: widget.controller, api: widget.api),
        ),
      ],
    ],
  );

  Widget _submittedBody(AppLocalizations l, WritingTaskState state) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 46),
          const SizedBox(height: 12),
          Text(
            l.text('writingDraftSaved'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l.text('writingFeedbackOnRequest'), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('writing-read-saved-draft'),
                onPressed:
                    state.draft.trim().isEmpty || widget.onSpeakText == null
                    ? null
                    : () => widget.onSpeakText!(state.draft),
                icon: const Icon(Icons.record_voice_over_outlined),
                label: Text(l.text('readAloudSynthetic')),
              ),
              FilledButton.icon(
                key: const Key('writing-request-feedback'),
                onPressed: state.busy
                    ? null
                    : () => widget.controller.requestLocalFeedback(widget.api),
                icon: const Icon(Icons.rule),
                label: Text(l.text('writingRequestFeedback')),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : widget.controller.startRevisionWithoutFeedback,
                child: Text(l.text('writingReviseMyself')),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _doneBody(AppLocalizations l, WritingTaskState state) => ListView(
    children: [
      Text(
        l.text('writingRevisionSaved'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      _VersionCard(
        label: l.text('writingOriginal'),
        text: state.draft,
        onSpeak: widget.onSpeakText == null
            ? null
            : () => widget.onSpeakText!(state.draft),
      ),
      const SizedBox(height: 12),
      _VersionCard(
        label: l.text('writingRevised'),
        text: state.revisionDraft,
        onSpeak: widget.onSpeakText == null
            ? null
            : () => widget.onSpeakText!(state.revisionDraft),
      ),
      const SizedBox(height: 12),
      _RevisionDiff(original: state.draft, revised: state.revisionDraft),
      const SizedBox(height: 12),
      Text(l.text('writingEvidenceNotice')),
      _WritingLlmAssist(controller: widget.controller, api: widget.api),
    ],
  );
}

/// LLM assist (Phase 3.12.2): shared correctable content/organization block,
/// hidden when no judgment-capable provider is configured. Distinct from the
/// Harper surface findings and from the learner meaning check.
class _WritingLlmAssist extends StatelessWidget {
  const _WritingLlmAssist({required this.controller, required this.api});

  final WritingTaskController controller;
  final LocalApi api;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return LlmJudgmentAssist(
      visible: state.judgeProviderId != null,
      points: state.rubric?.points ?? const [],
      judgment: state.llmJudgment,
      adjudications: state.llmAdjudications,
      busy: state.busy,
      keyPrefix: 'writing-task',
      onRequest: () => unawaited(controller.requestLlmJudgment(api)),
      onCorrect: (pointId, userVerdict) => unawaited(
        controller.adjudicateLlm(
          api,
          pointId: pointId,
          userVerdict: userVerdict,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.phase,
    required this.kind,
    required this.historyCount,
    required this.onKindChanged,
    required this.onClose,
  });

  final String phase;
  final String kind;
  final int historyCount;
  final ValueChanged<String> onKindChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.edit_note),
        Text(
          l.text('writingStudioTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Chip(label: Text(l.text('writingPhase_$phase'))),
        DropdownButton<String>(
          value: kind,
          onChanged: phase == 'drafting'
              ? (value) {
                  if (value != null && value != kind) onKindChanged(value);
                }
              : null,
          items:
              const [
                    WritingTaskController.oneSentenceSummaryKind,
                    WritingTaskController.summaryKind,
                    WritingTaskController.opinionKind,
                    WritingTaskController.dictoglossKind,
                  ]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(l.text('writingKind_$value')),
                    ),
                  )
                  .toList(growable: false),
        ),
        if (historyCount > 0)
          Text('${l.text('writingEarlierAttempts')}: $historyCount'),
        IconButton(
          tooltip: l.text('close'),
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.expanded,
    required this.prompt,
    required this.source,
    required this.previousText,
    required this.onPlaySource,
    required this.onToggle,
  });

  final bool expanded;
  final String prompt;
  final String? source;
  final String? previousText;
  final VoidCallback? onPlaySource;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      prompt,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                if (source != null)
                  Text(source!)
                else
                  Row(
                    children: [
                      Expanded(child: Text(l.text('writingSourceHidden'))),
                      OutlinedButton.icon(
                        onPressed: onPlaySource,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l.text('writingPlaySource')),
                      ),
                    ],
                  ),
                if (previousText != null) ...[
                  const Divider(height: 24),
                  Text(
                    l.text('writingPreviousVersion'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(previousText!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackList extends StatelessWidget {
  const _FeedbackList({required this.controller, required this.api});

  final WritingTaskController controller;
  final LocalApi api;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = controller.state;
    return ListView(
      children: [
        Text(
          l.text('writingMeaningCheck'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l.text('writingMeaningCheckHint'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final point in state.rubric?.points ?? const <RubricPointView>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.statement),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'covered',
                      label: Text(l.text('writingCovered')),
                    ),
                    ButtonSegment(
                      value: 'partial',
                      label: Text(l.text('writingPartial')),
                    ),
                    ButtonSegment(
                      value: 'missing',
                      label: Text(l.text('writingMissing')),
                    ),
                  ],
                  selected: state.selfVerdicts[point.pointId] == null
                      ? const {}
                      : {state.selfVerdicts[point.pointId]!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (values) {
                    if (values.isNotEmpty) {
                      controller.setSelfVerdict(point.pointId, values.single);
                    }
                  },
                ),
              ],
            ),
          ),
        const Divider(height: 20),
        Text(
          l.text('writingFeedback'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l.text('writingSuggestionNotice'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (state.findings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(l.text('writingNoLocalFindings'))),
          )
        else
          for (final finding in state.findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(finding.message),
                      if (finding.suggestedReplacement != null) ...[
                        const SizedBox(height: 6),
                        SelectableText('→ ${finding.suggestedReplacement}'),
                      ],
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'accepted',
                            label: Text(l.text('writingUseIdea')),
                          ),
                          ButtonSegment(
                            value: 'rejected',
                            label: Text(l.text('writingKeepMine')),
                          ),
                        ],
                        selected: state.decisions[finding.id] == null
                            ? const {}
                            : {state.decisions[finding.id]!},
                        emptySelectionAllowed: true,
                        onSelectionChanged: (values) {
                          if (values.isNotEmpty) {
                            controller.decide(finding.id, values.single);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        _WritingLlmAssist(controller: controller, api: api),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.label, required this.text, this.onSpeak});

  final String label;
  final String text;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(
                  context,
                ).text('readAloudSynthetic'),
                onPressed: text.trim().isEmpty ? null : onSpeak,
                icon: const Icon(Icons.record_voice_over_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(text),
        ],
      ),
    ),
  );
}

class _RevisionDiff extends StatelessWidget {
  const _RevisionDiff({required this.original, required this.revised});

  final String original;
  final String revised;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final originalRunes = original.runes.toList(growable: false);
    final revisedRunes = revised.runes.toList(growable: false);
    final prefixLength = _commonPrefix(originalRunes, revisedRunes);
    final suffixLength = _commonSuffix(
      originalRunes.sublist(prefixLength),
      revisedRunes.sublist(prefixLength),
    );
    final oldEnd = originalRunes.length - suffixLength;
    final newEnd = revisedRunes.length - suffixLength;
    String slice(List<int> values, int start, int end) =>
        String.fromCharCodes(values.sublist(start, end));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('writingChanges'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SelectableText.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(text: slice(revisedRunes, 0, prefixLength)),
                  if (oldEnd > prefixLength)
                    TextSpan(
                      text: slice(originalRunes, prefixLength, oldEnd),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  if (newEnd > prefixLength)
                    TextSpan(
                      text: slice(revisedRunes, prefixLength, newEnd),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  TextSpan(
                    text: slice(revisedRunes, newEnd, revisedRunes.length),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _commonPrefix(List<int> a, List<int> b) {
    var index = 0;
    while (index < a.length && index < b.length && a[index] == b[index]) {
      index++;
    }
    return index;
  }

  static int _commonSuffix(List<int> a, List<int> b) {
    var count = 0;
    while (count < a.length &&
        count < b.length &&
        a[a.length - count - 1] == b[b.length - count - 1]) {
      count++;
    }
    return count;
  }
}
