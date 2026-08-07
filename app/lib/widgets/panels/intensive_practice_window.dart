import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/practice_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

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
    this.showSentenceNavigation = true,
    required this.isPlaying,
    required this.onReplay,
    required this.onTogglePlayback,
    required this.onNavigate,
    required this.onSubmit,
    required this.onSaveReview,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onOpenMicrophoneSettings,
    required this.onPlayReference,
    required this.onPlayRecording,
    required this.onPlayAba,
    required this.onDeleteRecording,
    required this.onShadowingRateChanged,
    required this.onShadowingStepChanged,
    required this.onClose,
  });

  final PracticeController controller;
  final int currentSentence;
  final int totalSentences;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool showSentenceNavigation;
  final bool isPlaying;
  final Future<void> Function() onReplay;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function(int delta) onNavigate;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSaveReview;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onCancelRecording;
  final Future<void> Function() onOpenMicrophoneSettings;
  final Future<void> Function() onPlayReference;
  final Future<void> Function() onPlayRecording;
  final Future<void> Function() onPlayAba;
  final Future<void> Function() onDeleteRecording;
  final Future<void> Function(double rate) onShadowingRateChanged;
  final Future<void> Function(int index) onShadowingStepChanged;
  final Future<void> Function() onClose;

  @override
  State<IntensivePracticeWindow> createState() =>
      _IntensivePracticeWindowState();
}

class _IntensivePracticeWindowState extends State<IntensivePracticeWindow> {
  late final TextEditingController _answerController;
  Offset _offset = const Offset(32, 28);

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
    // A draggable floating window — repositionable by its title bar — that
    // floats over the workbench stage rather than covering it (the reference
    // keeps the video visible around it). Mounted directly in the workbench
    // [Stack], so reading the viewport here keeps [Positioned] that Stack's
    // direct child, which its parent data requires. The consistent chrome
    // (progress · settings · keyboard hints) wraps whichever practice body
    // [PracticeController] is driving.
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
        borderRadius: ListenRadii.panelBorder,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surface,
        // ⌘P / ⌘R mirror the keyboard hints at the foot of the window. They
        // resolve from whatever descendant holds focus (e.g. the answer field),
        // so they work while typing without the window stealing focus itself.
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () {
              if (!controller.busy) unawaited(widget.onTogglePlayback());
            },
            const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
              if (!controller.busy) unawaited(widget.onReplay());
            },
          },
          child: Column(
            children: [
              _titleBar(constraints, width, height),
              _metaRow(),
              Expanded(child: _body()),
              _keyboardHintBar(),
            ],
          ),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ListenSpacing.gap16,
            ListenSpacing.gap12,
            ListenSpacing.gap8,
            ListenSpacing.gap8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.text('practiceWindow'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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
      );

  // The prompt/answer/result renderers already scroll and size themselves; the
  // window only centres them in a readable measure.
  Widget _body() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ListenBreakpoints.contentColumnMax,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap24),
        child: _practiceContent(),
      ),
    ),
  );

  Widget _practiceContent() {
    final state = controller.state;
    // Only the draft is required: while a neighbouring sentence's item is
    // still being created the draft already carries the new prompt, and
    // [PracticeController.busy] keeps submission disabled until it resolves.
    if (state.draft == null) {
      return Center(
        child: Text(
          l.text('practiceChoosePrompt'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: state.draft!.kind == 'shadowing'
          ? _shadowing(state)
          : state.attempt == null
          ? _prompt(state)
          : _result(state),
    );
  }

  Widget _shadowing(PracticeState state) {
    final draft = state.draft!;
    final asset = state.recordingAsset;
    final comparison = state.comparison;
    final permissionBlocked =
        state.microphonePermission == MicrophonePermissionStatus.denied ||
        state.microphonePermission == MicrophonePermissionStatus.restricted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _practiceHeader(draft),
        if (draft.degradedMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              draft.degradedMessage!,
              style: ListenType.body.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        const SizedBox(height: ListenSpacing.gap12),
        Text(draft.promptText, style: Theme.of(context).textTheme.titleMedium),
        if (draft.shadowingSteps.length > 1) ...[
          const SizedBox(height: ListenSpacing.gap12),
          SegmentedButton<int>(
            segments: [
              for (final entry in draft.shadowingSteps.indexed)
                ButtonSegment(value: entry.$1, label: Text(entry.$2.label)),
            ],
            selected: {draft.shadowingStepIndex},
            onSelectionChanged:
                controller.busy || state.recordingActive || asset != null
                ? null
                : (values) =>
                      unawaited(widget.onShadowingStepChanged(values.single)),
          ),
        ],
        const SizedBox(height: ListenSpacing.gap12),
        Text(
          l.text('shadowingSpeed'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ListenSpacing.gap6),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 0.75, label: Text('0.75×')),
            ButtonSegment(value: 0.9, label: Text('0.9×')),
            ButtonSegment(value: 1.0, label: Text('1.0×')),
          ],
          selected: {state.shadowingRate},
          onSelectionChanged: controller.busy || state.recordingActive
              ? null
              : (values) =>
                    unawaited(widget.onShadowingRateChanged(values.single)),
        ),
        const SizedBox(height: ListenSpacing.gap12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller.busy || state.recordingActive
                  ? null
                  : () => unawaited(widget.onPlayReference()),
              icon: const Icon(Icons.hearing),
              label: Text(l.text('shadowingPlayOriginal')),
            ),
            if (!state.recordingActive)
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(() async {
                        if (asset != null) await widget.onDeleteRecording();
                        await widget.onStartRecording();
                      }()),
                icon: const Icon(Icons.mic),
                label: Text(
                  asset == null
                      ? l.text('shadowingStartRecording')
                      : l.text('shadowingRecordAgain'),
                ),
              )
            else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onStopRecording()),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l.text('shadowingStopRecording')),
              ),
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onCancelRecording()),
                child: Text(l.text('cancel')),
              ),
            ],
          ],
        ),
        if (state.recordingActive)
          Padding(
            padding: const EdgeInsets.only(top: ListenSpacing.gap8),
            child: Row(
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  size: ListenIconSize.inline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: ListenSpacing.gap6),
                Text(l.text('shadowingRecordingActive')),
              ],
            ),
          ),
        if (permissionBlocked)
          Padding(
            padding: const EdgeInsets.only(top: ListenSpacing.gap8),
            child: Row(
              children: [
                Expanded(child: Text(l.text('shadowingPermissionDenied'))),
                TextButton(
                  onPressed: () => unawaited(widget.onOpenMicrophoneSettings()),
                  child: Text(l.text('openSystemSettings')),
                ),
              ],
            ),
          ),
        if (asset != null) ...[
          const Divider(height: 28),
          Text(
            l.text('shadowingComparison'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onPlayRecording()),
                icon: const Icon(Icons.person),
                label: Text(l.text('shadowingPlayMine')),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onPlayAba()),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('A / B / A'),
              ),
              TextButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(widget.onDeleteRecording()),
                icon: const Icon(Icons.delete_outline),
                label: Text(l.text('delete')),
              ),
            ],
          ),
          if (comparison != null) ...[
            const SizedBox(height: ListenSpacing.gap12),
            _comparisonMetrics(comparison),
            const SizedBox(height: ListenSpacing.gap12),
            _waveformRow(
              l.text('shadowingOriginal'),
              comparison.referenceWaveform,
              Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            _waveformRow(
              l.text('shadowingMine'),
              comparison.recordingWaveform,
              Theme.of(context).colorScheme.secondary,
            ),
          ],
          if (state.comparisonWarning != null)
            Padding(
              padding: const EdgeInsets.only(top: ListenSpacing.gap8),
              child: Text(
                state.comparisonWarning!,
                style: ListenType.body.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
        ],
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: ListenSpacing.gap8),
            child: Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _comparisonMetrics(ShadowingComparison comparison) {
    final delta = comparison.durationDeltaMs;
    final durationText = delta == 0
        ? l.text('shadowingSameDuration')
        : delta > 0
        ? '+$delta ms'
        : '$delta ms';
    final pauseOffset = comparison.meanAbsolutePauseOffsetMs;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('${l.text('shadowingDurationDelta')}: $durationText')),
        Chip(
          label: Text(
            '${l.text('shadowingPauseCount')}: '
            '${comparison.referencePauses.length} / ${comparison.recordingPauses.length}',
          ),
        ),
        if (pauseOffset != null)
          Chip(
            label: Text('${l.text('shadowingPauseOffset')}: $pauseOffset ms'),
          ),
      ],
    );
  }

  Widget _waveformRow(
    String label,
    AudioWaveformSummary waveform,
    Color color,
  ) => Row(
    children: [
      SizedBox(width: 54, child: Text(label, style: ListenType.body)),
      Expanded(
        child: SizedBox(
          height: 42,
          child: CustomPaint(painter: _WaveformPainter(waveform.peaks, color)),
        ),
      ),
      const SizedBox(width: ListenSpacing.gap8),
      Text('${waveform.durationMs} ms', style: ListenType.caption),
    ],
  );

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
              style: ListenType.body.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
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
              style: ListenType.body.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: ListenSpacing.gap8),
            child: Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (attempt.evaluation.tokenResults.isNotEmpty) _diff(attempt),
        const SizedBox(height: ListenSpacing.gap12),
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

  // The window's second row: sentence progress on the left, the auto-replay
  // settings preview on the right — the `N/total · rate | reps | gap` band the
  // reference app carries above the focused sentence.
  Widget _metaRow() => Padding(
    padding: const EdgeInsets.fromLTRB(
      ListenSpacing.gap16,
      0,
      ListenSpacing.gap16,
      ListenSpacing.gap8,
    ),
    child: Row(
      children: [
        if (widget.showSentenceNavigation) _progressPill(),
        const Spacer(),
        _settingsPill(),
      ],
    ),
  );

  Widget _progressPill() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: ListenPadding.tight,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: ListenRadii.pillBorder,
      ),
      child: Text(
        l
            .text('practiceProgress')
            .replaceFirst('{current}', '${widget.currentSentence}')
            .replaceFirst('{total}', '${widget.totalSentences}'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  // Honest placeholder: the "replay N times at rate R with a gap of I" auto-
  // listen loop is not built yet, so this pill previews the intended settings
  // without wiring them to practice state. Non-interactive on purpose; the gap
  // is logged in docs/product/workbench-backend-gaps.md.
  Widget _settingsPill() {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: l.text('intensiveSettingsPreview'),
      child: Container(
        padding: ListenPadding.tight,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: ListenRadii.pillBorder,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('1×'),
              _pillDivider(colors),
              Text(l.text('intensiveRepeatCount').replaceFirst('{count}', '3')),
              _pillDivider(colors),
              Text(l.text('intensiveInterval').replaceFirst('{seconds}', '5')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillDivider(ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
    child: Text('|', style: TextStyle(color: colors.outlineVariant)),
  );

  // The foot of the window: prev · play/pause · replay · next, styled as the
  // reference's keyboard-hint strip. Each control is tappable (so it works
  // without a keyboard) and carries its ⌘-shortcut cap as a legend.
  Widget _keyboardHintBar() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ListenSpacing.gap16,
        vertical: ListenSpacing.gap8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.showSentenceNavigation)
            IconButton(
              tooltip: l.text('previousSentence'),
              onPressed: controller.busy || !widget.canGoPrevious
                  ? null
                  : () => unawaited(widget.onNavigate(-1)),
              icon: const Icon(Icons.chevron_left),
            ),
          _hintAction(
            keyCap: '⌘P',
            label: l.text('practicePlayPause'),
            onPressed: controller.busy
                ? null
                : () => unawaited(widget.onTogglePlayback()),
          ),
          const SizedBox(width: ListenSpacing.gap16),
          _hintAction(
            keyCap: '⌘R',
            label: l.text('replay'),
            onPressed: controller.busy
                ? null
                : () => unawaited(widget.onReplay()),
          ),
          if (widget.showSentenceNavigation)
            IconButton(
              tooltip: l.text('nextSentence'),
              onPressed: controller.busy || !widget.canGoNext
                  ? null
                  : () => unawaited(widget.onNavigate(1)),
              icon: const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }

  Widget _hintAction({
    required String keyCap,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap6,
              vertical: ListenSpacing.gap2,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: ListenRadii.tightBorder,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              keyCap,
              style: ListenType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: ListenSpacing.gap6),
          Text(label),
        ],
      ),
    );
  }

  Widget _practiceHeader(PracticeDraft draft) => Row(
    children: [
      Icon(
        draft.kind == 'shadowing'
            ? Icons.mic_none
            : draft.kind == 'cloze'
            ? Icons.text_fields
            : Icons.keyboard,
      ),
      const SizedBox(width: ListenSpacing.gap8),
      Expanded(
        child: Text(
          draft.kind == 'shadowing'
              ? l.text('shadowingPractice')
              : draft.kind == 'cloze'
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
    'equivalent' => '${token.actual ?? ''} ≈ ${token.expected ?? ''}',
    'missing' => '- ${token.expected ?? ''}',
    'extra' => '+ ${token.actual ?? ''}',
    'mismatch' =>
      '${token.expected ?? '(empty)'} -> ${token.actual ?? '(empty)'}',
    _ => token.actual ?? token.expected ?? '',
  };

  Color _resultColor(String result) => switch (result) {
    'correct' => Theme.of(context).colorScheme.primary,
    'equivalent' => Theme.of(context).colorScheme.primary,
    'missing' => Theme.of(context).colorScheme.secondary,
    'extra' => Theme.of(context).colorScheme.tertiary,
    'mismatch' => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.peaks, this.color);

  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1, size.width / peaks.length * 0.65)
      ..strokeCap = StrokeCap.round;
    final center = size.height / 2;
    final step = size.width / peaks.length;
    for (var index = 0; index < peaks.length; index++) {
      final amplitude = peaks[index].clamp(0.0, 1.0) * center;
      final x = (index + 0.5) * step;
      canvas.drawLine(
        Offset(x, center - amplitude),
        Offset(x, center + amplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.peaks != peaks || oldDelegate.color != color;
}
