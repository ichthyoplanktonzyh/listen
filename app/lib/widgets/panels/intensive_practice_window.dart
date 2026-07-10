import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/practice_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../theme/listen_theme.dart';

/// A transient practice surface for one intensive-listening prompt.
///
/// It deliberately owns no learning data: [PracticeController] remains the
/// source for prompt, attempt and review state while this window only arranges
/// the focused interaction and local playback controls.
class IntensivePracticeWindow extends StatefulWidget {
  const IntensivePracticeWindow({
    super.key,
    required this.controller,
    required this.currentSentence,
    required this.totalSentences,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.isPlaying,
    required this.onReplay,
    required this.onTogglePlayback,
    required this.onNavigate,
    required this.onSubmit,
    required this.onSaveReview,
    required this.onClose,
  });

  final PracticeController controller;
  final int currentSentence;
  final int totalSentences;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool isPlaying;
  final Future<void> Function() onReplay;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function(int delta) onNavigate;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSaveReview;
  final Future<void> Function() onClose;

  @override
  State<IntensivePracticeWindow> createState() =>
      _IntensivePracticeWindowState();
}

class _IntensivePracticeWindowState extends State<IntensivePracticeWindow> {
  late final TextEditingController _answerController;
  Offset _offset = const Offset(32, 28);
  bool _showMiniPlayer = true;

  PracticeController get controller => widget.controller;
  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController(text: controller.answer);
  }

  @override
  void didUpdateWidget(covariant IntensivePracticeWindow oldWidget) {
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
    // This widget is mounted directly in the workbench [Stack].  Reading the
    // available viewport here keeps [Positioned] as that Stack's direct child,
    // which is required for its parent data to be valid.
    final size = MediaQuery.sizeOf(context);
    final constraints = BoxConstraints.tight(size);
    final width = math.min(860.0, math.max(320.0, constraints.maxWidth - 32));
    final height = math.min(560.0, math.max(360.0, constraints.maxHeight - 32));
    final left = _offset.dx.clamp(
      16.0,
      math.max(16.0, constraints.maxWidth - width - 16),
    );
    final top = _offset.dy.clamp(
      16.0,
      math.max(16.0, constraints.maxHeight - height - 16),
    );
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width,
      height: height,
      child: Material(
        elevation: 18,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        color: ListenColors.surface,
        child: Column(
          children: [
            _titleBar(constraints, width, height),
            const Divider(height: 1),
            Expanded(child: _body(width)),
            const Divider(height: 1),
            _progress(),
          ],
        ),
      ),
    );
  }

  Widget _titleBar(BoxConstraints constraints, double width, double height) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => setState(() {
          _offset += details.delta;
          _offset = Offset(
            _offset.dx.clamp(
              16.0,
              math.max(16.0, constraints.maxWidth - width - 16),
            ),
            _offset.dy.clamp(
              16.0,
              math.max(16.0, constraints.maxHeight - height - 16),
            ),
          );
        }),
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: Row(
              children: [
                const Icon(Icons.fact_check_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.text('practiceWindow'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Tooltip(
                  message: _showMiniPlayer
                      ? l.text('hidePracticePlayer')
                      : l.text('showPracticePlayer'),
                  child: IconButton(
                    onPressed: () =>
                        setState(() => _showMiniPlayer = !_showMiniPlayer),
                    icon: Icon(
                      _showMiniPlayer
                          ? Icons.picture_in_picture_alt_outlined
                          : Icons.picture_in_picture_outlined,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.text('close'),
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(widget.onClose()),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _body(double width) {
    final content = _practiceContent();
    if (!_showMiniPlayer) {
      return Padding(padding: const EdgeInsets.all(18), child: content);
    }
    if (width < 620) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [content, const SizedBox(height: 16), _miniPlayer()],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: content),
          const SizedBox(width: 18),
          SizedBox(width: 238, child: _miniPlayer()),
        ],
      ),
    );
  }

  Widget _practiceContent() {
    final state = controller.state;
    if (state.draft == null || state.item == null) {
      return Center(
        child: Text(
          l.text('practiceChoosePrompt'),
          style: const TextStyle(color: ListenColors.muted),
        ),
      );
    }
    return SingleChildScrollView(
      child: state.attempt == null ? _prompt(state) : _result(state),
    );
  }

  Widget _prompt(PracticeState state) {
    final draft = state.draft!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _practiceHeader(draft),
        if (draft.degradedMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              draft.degradedMessage!,
              style: const TextStyle(fontSize: 12, color: ListenColors.accent),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
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
              style: const TextStyle(fontSize: 12, color: ListenColors.muted),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextField(
            controller: _answerController,
            autofocus: true,
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
          runSpacing: 8,
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
    final reviewSaved = attempt.generatedReviewItemIds.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _practiceHeader(state.draft!),
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
            style: const TextStyle(color: ListenColors.muted),
          ),
        ),
        if (attempt.evaluation.tokenResults.isNotEmpty) _diff(attempt),
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
            FilledButton.tonalIcon(
              onPressed:
                  attempt.result == 'correct' || reviewSaved || controller.busy
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

  Widget _miniPlayer() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF1D2430),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.isPlaying ? Icons.graphic_eq : Icons.play_circle_outline,
            color: Colors.white,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            l.text('practicePlayer'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.text('practicePlayerHint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD0D8E8), fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l.text('previousSentence'),
                onPressed: controller.busy || !widget.canGoPrevious
                    ? null
                    : () => unawaited(widget.onNavigate(-1)),
                icon: const Icon(Icons.skip_previous, color: Colors.white),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1D2430),
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onTogglePlayback()),
                child: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: l.text('nextSentence'),
                onPressed: controller.busy || !widget.canGoNext
                    ? null
                    : () => unawaited(widget.onNavigate(1)),
                icon: const Icon(Icons.skip_next, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _progress() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.format_list_numbered, size: 18),
        const SizedBox(width: 8),
        Text(
          l
              .text('practiceProgress')
              .replaceFirst('{current}', '${widget.currentSentence}')
              .replaceFirst('{total}', '${widget.totalSentences}'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _practiceHeader(PracticeDraft draft) => Row(
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
          style: const TextStyle(color: ListenColors.muted),
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
    'correct' => ListenColors.primary,
    'missing' => ListenColors.accent,
    'extra' => ListenColors.info,
    'mismatch' => ListenColors.error,
    _ => ListenColors.muted,
  };
}
