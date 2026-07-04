import 'package:flutter/material.dart';

import '../../controllers/manual_review_controller.dart';
import '../../models/timeline.dart';
import '../../theme/listen_theme.dart';

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
  String? _saveError;

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
    final errors = draft.validateCurrentSentence();
    final selectedWord = _selectedWord();
    return AlertDialog(
      title: const Text('Manual word timing review'),
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
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.onPlayRange(
                    draft.currentCue.start,
                    draft.currentCue.end,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play sentence'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: selectedWord == null
                      ? null
                      : () => widget.onPlayRange(
                          selectedWord.start,
                          selectedWord.end,
                        ),
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('Play word'),
                ),
                const Spacer(),
                Text(
                  '${draft.dirtyWords.length} edited',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (errors.isNotEmpty)
              _MessageBox(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                messages: errors,
              )
            else
              const _MessageBox(
                icon: Icons.check_circle_outline,
                color: ListenColors.primary,
                messages: ['Current sentence boundaries are valid.'],
              ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              _MessageBox(
                icon: Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error,
                messages: [_saveError!],
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: draft.currentSentenceWords.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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
          child: const Text('Cancel'),
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
                  _saveError = null;
                }),
          child: const Text('Reset sentence'),
        ),
        FilledButton(
          onPressed: _saving || !draft.dirty || draft.validateAll().isNotEmpty
              ? null
              : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save revision'),
        ),
      ],
    );
  }

  Widget _wordRow(WordTiming word) {
    final key = WordKey(word.sentenceId, word.tokenIndex);
    final selected = key == _selected;
    final dirty = draft.dirtyWords.contains(key);
    final label = wordLabel(word, draft.currentCue);
    return InkWell(
      onTap: () => setState(() => _selected = key),
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? ListenColors.selected : ListenColors.fog,
          border: Border.all(
            color: selected ? ListenColors.primary : ListenColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    const SizedBox(height: 3),
                    Text(
                      dirty ? 'user adjusted' : word.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _BoundaryEditor(
                label: 'Start',
                value: word.start,
                onStep: (delta) =>
                    _step(word, adjustStart: true, deltaMs: delta),
                onSet: (value) => _setBoundary(word, start: value),
              ),
              const SizedBox(width: 8),
              _BoundaryEditor(
                label: 'End',
                value: word.end,
                onStep: (delta) =>
                    _step(word, adjustStart: false, deltaMs: delta),
                onSet: (value) => _setBoundary(word, end: value),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: Text(
                  '${word.end.inMilliseconds - word.start.inMilliseconds} ms',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
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
      _saveError = null;
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
      _saveError = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(draft);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '$error';
        });
      }
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
      _saveError = null;
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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sentence ${cue.index + 1}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(cue.text, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${_formatMs(cue.start)} - ${_formatMs(cue.end)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Previous sentence',
        onPressed: canPrevious ? onPrevious : null,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next sentence',
        onPressed: canNext ? onNext : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _BoundaryEditor extends StatelessWidget {
  const _BoundaryEditor({
    required this.label,
    required this.value,
    required this.onStep,
    required this.onSet,
  });

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
        const SizedBox(height: 3),
        Row(
          children: [
            _StepButton(label: '-50', onPressed: () => onStep(-50)),
            _StepButton(label: '-10', onPressed: () => onStep(-10)),
            _StepButton(label: '+10', onPressed: () => onStep(10)),
            _StepButton(label: '+50', onPressed: () => onStep(50)),
          ],
        ),
        const SizedBox(height: 5),
        TextFormField(
          key: ValueKey('$label-${value.inMilliseconds}'),
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
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
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
