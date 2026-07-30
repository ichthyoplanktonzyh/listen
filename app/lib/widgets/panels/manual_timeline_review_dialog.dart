import 'package:flutter/material.dart';

import '../../controllers/manual_review_controller.dart';
import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../services/api_service.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';

/// Why a revision did not get saved — a *named state*, never the exception.
///
/// This dialog used to hold `String? _saveError` and fill it with `'$error'`,
/// which put an `HttpException` (internal error code, `correlation_id`,
/// loopback port, internal route) straight into the message box. Charter P4
/// asks for an honest instrument, not debug output: the two cases a learner can
/// tell apart get a sentence each, and the transport's own text travels beside
/// them on an [ApiFailure] that is never rendered.
enum ManualTimingSaveFailure {
  /// The backend refused these boundaries — a validation answer, so re-editing
  /// is the way forward.
  rejected,

  /// Anything else: the request did not complete. Nothing about *why* is
  /// useful to a learner, so it does not get a second sentence.
  notSaved;

  /// Classifies a caught save error. Only a `validation_error` envelope counts
  /// as a rejection; every other body — including one this client cannot type
  /// at all — degrades to [notSaved] rather than guessing.
  static ManualTimingSaveFailure of(ApiFailure failure) =>
      failure.code == 'validation_error' ? rejected : notSaved;

  String key() => switch (this) {
    rejected => 'manualTimingSaveRejected',
    notSaved => 'manualTimingSaveFailed',
  };
}

class ManualTimelineReviewDialog extends StatefulWidget {
  const ManualTimelineReviewDialog({
    super.key,
    required this.draft,
    required this.onPlayRange,
    required this.onSave,
  });

  final ManualReviewDraft draft;
  final Future<void> Function(Duration start, Duration end) onPlayRange;
  final Future<void> Function(ManualReviewDraft draft) onSave;

  @override
  State<ManualTimelineReviewDialog> createState() =>
      _ManualTimelineReviewDialogState();
}

class _ManualTimelineReviewDialogState
    extends State<ManualTimelineReviewDialog> {
  WordKey? _selected;
  bool _saving = false;

  /// The named state of the last failed save, and the diagnostics that came
  /// with it. [_saveDetail] is never rendered — it is here so the reference id
  /// can be shown, and so the rest stays reachable for a log.
  ManualTimingSaveFailure? _saveFailure;
  ApiFailure? _saveDetail;

  ManualReviewDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    final words = draft.currentSentenceWords;
    if (words.isNotEmpty) {
      _selected = WordKey(words.first.sentenceId, words.first.tokenIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final errors = draft.validateCurrentSentence();
    final selectedWord = _selectedWord();
    return AlertDialog(
      title: Text(l.text('manualTimingTitle')),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              cue: draft.currentCue,
              canPrevious: _previousCue() != null,
              canNext: _nextCue() != null,
              onPrevious: () => _selectCue(_previousCue()),
              onNext: () => _selectCue(_nextCue()),
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.onPlayRange(
                    draft.currentCue.start,
                    draft.currentCue.end,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.text('manualTimingPlaySentence')),
                ),
                const SizedBox(width: ListenSpacing.gap8),
                FilledButton.tonalIcon(
                  onPressed: selectedWord == null
                      ? null
                      : () => widget.onPlayRange(
                          selectedWord.start,
                          selectedWord.end,
                        ),
                  icon: const Icon(Icons.volume_up_outlined),
                  label: Text(l.text('manualTimingPlayWord')),
                ),
                const Spacer(),
                Text(
                  l
                      .text('manualTimingEditedCount')
                      .replaceAll('{count}', '${draft.dirtyWords.length}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap8),
            if (errors.isNotEmpty)
              _MessageBox(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                messages: errors,
              )
            else
              _MessageBox(
                icon: Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
                messages: [l.text('manualTimingBoundariesValid')],
              ),
            if (_saveFailure != null) ...[
              const SizedBox(height: ListenSpacing.gap8),
              _MessageBox(
                icon: Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error,
                // One sentence, plus the id that ties a bug report to a
                // backend log line. The error code, the operator-facing
                // message and `ApiFailure.raw` stay off screen entirely.
                messages: [
                  l.text(_saveFailure!.key()),
                  if (_saveDetail?.correlationId case final id?)
                    l.text('failureReference').replaceAll('{id}', id),
                ],
              ),
            ],
            const SizedBox(height: ListenSpacing.gap8),
            Expanded(
              child: ListView.separated(
                itemCount: draft.currentSentenceWords.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ListenSpacing.gap8),
                itemBuilder: (context, index) =>
                    _wordRow(draft.currentSentenceWords[index]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l.text('cancel')),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                  draft.resetCurrentSentence();
                  final words = draft.currentSentenceWords;
                  _selected = words.isEmpty
                      ? null
                      : WordKey(words.first.sentenceId, words.first.tokenIndex);
                  _clearSaveFailure();
                }),
          child: Text(l.text('manualTimingResetSentence')),
        ),
        FilledButton(
          onPressed: _saving || !draft.dirty || draft.validateAll().isNotEmpty
              ? null
              : _save,
          child: _saving
              ? const ListenLoading.inline(size: 16)
              : Text(l.text('manualTimingSaveRevision')),
        ),
      ],
    );
  }

  Widget _wordRow(WordTiming word) {
    final l = AppLocalizations.of(context);
    final key = WordKey(word.sentenceId, word.tokenIndex);
    final selected = key == _selected;
    final dirty = draft.dirtyWords.contains(key);
    final label = wordLabel(word, draft.currentCue);
    return InkWell(
      onTap: () => setState(() => _selected = key),
      borderRadius: ListenRadii.controlBorder,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: ListenPadding.row,
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      dirty ? l.text('manualTimingUserAdjusted') : word.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              _BoundaryEditor(
                slot: 'start',
                label: l.text('manualTimingStart'),
                value: word.start,
                onStep: (delta) =>
                    _step(word, adjustStart: true, deltaMs: delta),
                onSet: (value) => _setBoundary(word, start: value),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              _BoundaryEditor(
                slot: 'end',
                label: l.text('manualTimingEnd'),
                value: word.end,
                onStep: (delta) =>
                    _step(word, adjustStart: false, deltaMs: delta),
                onSet: (value) => _setBoundary(word, end: value),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              SizedBox(
                width: 88,
                child: Text(
                  '${word.end.inMilliseconds - word.start.inMilliseconds} ms',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  [
                    word.provider,
                    if (word.providerVersion.isNotEmpty) word.providerVersion,
                    if (word.confidence != null)
                      '${(word.confidence! * 100).round()}%',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setBoundary(WordTiming word, {Duration? start, Duration? end}) {
    setState(() {
      _selected = WordKey(word.sentenceId, word.tokenIndex);
      draft.updateWordBoundary(
        sentenceId: word.sentenceId,
        tokenIndex: word.tokenIndex,
        start: start,
        end: end,
      );
      _clearSaveFailure();
    });
  }

  void _step(
    WordTiming word, {
    required bool adjustStart,
    required int deltaMs,
  }) {
    setState(() {
      _selected = WordKey(word.sentenceId, word.tokenIndex);
      draft.stepWordBoundary(
        sentenceId: word.sentenceId,
        tokenIndex: word.tokenIndex,
        adjustStart: adjustStart,
        deltaMs: deltaMs,
      );
      _clearSaveFailure();
    });
  }

  /// Clears a stale failure. Any edit invalidates it: the message named a
  /// state of the *last save attempt*, and the boundaries it referred to no
  /// longer exist.
  ///
  /// Must be called from inside a `setState`.
  void _clearSaveFailure() {
    _saveFailure = null;
    _saveDetail = null;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _clearSaveFailure();
    });
    try {
      await widget.onSave(draft);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      // The exception becomes a typed diagnostic and a named state. Nothing
      // from `describeApiFailure`'s result is rendered except the reference id.
      final detail = describeApiFailure(error);
      setState(() {
        _saving = false;
        _saveFailure = ManualTimingSaveFailure.of(detail);
        _saveDetail = detail;
      });
    }
  }

  void _selectCue(Cue? cue) {
    if (cue == null) return;
    setState(() {
      draft.selectCue(cue);
      final words = draft.currentSentenceWords;
      _selected = words.isEmpty
          ? null
          : WordKey(words.first.sentenceId, words.first.tokenIndex);
      _clearSaveFailure();
    });
  }

  Cue? _previousCue() {
    final index = draft.track.cues.indexWhere(
      (cue) => cue.id == draft.currentCue.id,
    );
    if (index <= 0) return null;
    return draft.track.cues[index - 1];
  }

  Cue? _nextCue() {
    final index = draft.track.cues.indexWhere(
      (cue) => cue.id == draft.currentCue.id,
    );
    if (index < 0 || index >= draft.track.cues.length - 1) return null;
    return draft.track.cues[index + 1];
  }

  WordTiming? _selectedWord() {
    final selected = _selected;
    if (selected == null) return null;
    final values = draft.currentSentenceWords.where(
      (word) =>
          word.sentenceId == selected.sentenceId &&
          word.tokenIndex == selected.tokenIndex,
    );
    return values.isEmpty ? null : values.first;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.cue,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
  });

  final Cue cue;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l
                    .text('manualTimingSentence')
                    .replaceAll('{index}', '${cue.index + 1}'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: ListenSpacing.gap4),
              Text(cue.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: ListenSpacing.gap4),
              Text(
                '${_formatMs(cue.start)} - ${_formatMs(cue.end)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l.text('manualTimingPreviousSentence'),
          onPressed: canPrevious ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: l.text('manualTimingNextSentence'),
          onPressed: canNext ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _BoundaryEditor extends StatelessWidget {
  const _BoundaryEditor({
    required this.slot,
    required this.label,
    required this.value,
    required this.onStep,
    required this.onSet,
  });

  /// Which boundary this edits (`start` / `end`). Identifies the field for its
  /// `ValueKey` so the key does not change with the interface language —
  /// [label] is copy, and a key built from copy resets the field on a locale
  /// switch.
  final String slot;
  final String label;
  final Duration value;
  final void Function(int deltaMs) onStep;
  final void Function(Duration value) onSet;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 176,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: ListenSpacing.gap2),
        Row(
          children: [
            _StepButton(label: '-50', onPressed: () => onStep(-50)),
            _StepButton(label: '-10', onPressed: () => onStep(-10)),
            _StepButton(label: '+10', onPressed: () => onStep(10)),
            _StepButton(label: '+50', onPressed: () => onStep(50)),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap4),
        TextFormField(
          key: ValueKey('$slot-${value.inMilliseconds}'),
          initialValue: value.inMilliseconds.toString(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            suffixText: 'ms',
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (raw) {
            final parsed = int.tryParse(raw.trim());
            if (parsed != null) onSet(Duration(milliseconds: parsed));
          },
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 28,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
      child: Text(label),
    ),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.icon,
    required this.color,
    required this.messages,
  });

  final IconData icon;
  final Color color;
  final List<String> messages;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.42)),
      borderRadius: ListenRadii.controlBorder,
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: ListenIconSize.control),
          const SizedBox(width: ListenSpacing.gap8),
          Expanded(
            child: Text(
              messages.take(3).join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatMs(Duration value) {
  final total = value.inMilliseconds;
  final minutes = (total ~/ 60000).toString().padLeft(2, '0');
  final seconds = ((total ~/ 1000) % 60).toString().padLeft(2, '0');
  final millis = (total % 1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$millis';
}
