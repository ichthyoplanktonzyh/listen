import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/transcript_translation.dart';
import 'diagnosis_card.dart';

/// Which layer of sentence analysis is on show.
///
/// The reference app's `解析` is a text/grammar breakdown; ours does not have
/// that AI contract yet, so [text] is an honest "not ready" placeholder while
/// [voice] carries the pronunciation/listening evidence we do produce
/// ([DiagnosisCard]). The toggle keeps both reachable without pretending the
/// text layer is populated.
enum _AnalysisLayer { text, voice }

/// The per-sentence analysis surface, drawn as a draggable window that floats
/// over the workbench stage rather than replacing the transcript.
///
/// It owns no learning data: [SubtitleController]/[LearningController] remain
/// the source for the current sentence and its diagnosis; this window only
/// arranges the layer toggle, the honest text-layer placeholder, and the
/// existing [DiagnosisCard]. Visibility is driven by
/// [LearningController.diagnosisExpanded] at the mount site — closing the
/// window there is the same gesture the transcript's `解析` entry toggles.
class SentenceAnalysisWindow extends StatefulWidget {
  const SentenceAnalysisWindow({
    super.key,
    required this.subtitleController,
    required this.learningController,
    required this.settingsController,
    required this.playbackActions,
    required this.onRequestDiagnosis,
    required this.onClose,
    this.onOpenListeningDictionary,
    this.onOpenL1Specialty,
  });

  final SubtitleController subtitleController;
  final LearningController learningController;
  final SettingsController settingsController;
  final PlaybackActionsCoordinator playbackActions;

  /// Fetches the diagnosis for the current sentence when the voice layer is
  /// opened on a sentence that has none loaded yet.
  final Future<void> Function() onRequestDiagnosis;

  /// Closes the window. Wired to clear [LearningController.diagnosisExpanded].
  final VoidCallback onClose;

  final Future<void> Function(String lexicalEntryId)? onOpenListeningDictionary;
  final Future<void> Function(L1DiagnosisHint hint)? onOpenL1Specialty;

  @override
  State<SentenceAnalysisWindow> createState() => _SentenceAnalysisWindowState();
}

class _SentenceAnalysisWindowState extends State<SentenceAnalysisWindow> {
  /// Null until the window is dragged, so it opens centred over the stage and
  /// only pins to an absolute spot once the reader has moved it.
  Offset? _offset;
  _AnalysisLayer _layer = _AnalysisLayer.text;

  SubtitleController get subtitleController => widget.subtitleController;
  LearningController get learningController => widget.learningController;
  SettingsController get settingsController => widget.settingsController;
  PlaybackActionsCoordinator get playbackActions => widget.playbackActions;
  AppLocalizations get l => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    // Mounted directly in the workbench [Stack], so reading the viewport here
    // keeps this a direct [Positioned] child, which its parent data requires.
    final size = MediaQuery.sizeOf(context);
    final width = math.min(720.0, math.max(320.0, size.width - 32));
    final height = math.min(560.0, math.max(360.0, size.height - 32));
    final maxLeft = math.max(16.0, size.width - width - 16);
    final maxTop = math.max(16.0, size.height - height - 16);
    final offset = _offset ?? Offset((size.width - width) / 2, (size.height - height) / 2);
    final left = offset.dx.clamp(16.0, maxLeft);
    final top = offset.dy.clamp(16.0, maxTop);
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
        child: Column(
          children: [
            _titleBar(size, width, height, offset),
            _layerToggle(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _titleBar(Size size, double width, double height, Offset offset) {
    final maxLeft = math.max(16.0, size.width - width - 16);
    final maxTop = math.max(16.0, size.height - height - 16);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => setState(() {
        final moved = offset + details.delta;
        _offset = Offset(
          moved.dx.clamp(16.0, maxLeft),
          moved.dy.clamp(16.0, maxTop),
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
                l.text('aiAnalysis'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const Key('analysis-window-close'),
              tooltip: l.text('close'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerToggle() => Padding(
    padding: const EdgeInsets.fromLTRB(
      ListenSpacing.gap16,
      0,
      ListenSpacing.gap16,
      ListenSpacing.gap12,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<_AnalysisLayer>(
        segments: [
          ButtonSegment(
            value: _AnalysisLayer.text,
            label: Text(l.text('analysisLayerText')),
          ),
          ButtonSegment(
            value: _AnalysisLayer.voice,
            label: Text(l.text('analysisLayerVoice')),
          ),
        ],
        selected: {_layer},
        showSelectedIcon: false,
        onSelectionChanged: (values) {
          setState(() => _layer = values.first);
          if (_layer == _AnalysisLayer.voice &&
              learningController.diagnosis == null) {
            unawaited(widget.onRequestDiagnosis());
          }
        },
      ),
    ),
  );

  Widget _body() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ListenBreakpoints.contentColumnMax,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ListenSpacing.gap24,
          0,
          ListenSpacing.gap24,
          ListenSpacing.gap24,
        ),
        child: switch (_layer) {
          _AnalysisLayer.text => _textLayer(),
          _AnalysisLayer.voice => _voiceLayer(),
        },
      ),
    ),
  );

  /// The reference's grammar/collocation breakdown lives here — but the AI
  /// contract that would fill it is not wired, so this states that honestly and
  /// points at the voice layer rather than faking a result.
  Widget _textLayer() {
    final cue = subtitleController.currentPrimaryCue;
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    if (cue == null) {
      return Center(
        child: Text(
          l.text('selectWordFromTranscript'),
          style: theme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }
    final translation = _translationFor(cue);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cue.text,
            style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (translation != null && translation.isNotEmpty) ...[
            const SizedBox(height: ListenSpacing.gap6),
            Text(
              translation,
              style: theme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: ListenSpacing.gap16),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: ListenSpacing.gap16),
          Text(l.text('analysisGrammarSection'), style: theme.titleSmall),
          const SizedBox(height: ListenSpacing.gap8),
          Text(l.text('analysisCollocationSection'), style: theme.titleSmall),
          const SizedBox(height: ListenSpacing.gap16),
          _UnavailableNotice(
            title: l.text('analysisTextUnavailableTitle'),
            body: l.text('analysisTextUnavailableBody'),
          ),
        ],
      ),
    );
  }

  Widget _voiceLayer() {
    if (learningController.diagnosis == null) {
      return SingleChildScrollView(
        child: _AnalysisPending(
          message: l.text('openSentenceDiagnosisHint'),
          actionLabel: l.text('openDiagnosis'),
          onAction: () => unawaited(widget.onRequestDiagnosis()),
        ),
      );
    }
    return SingleChildScrollView(child: _diagnosisCard());
  }

  String? _translationFor(Cue cue) {
    final secondary = subtitleController.secondaryTrack;
    if (secondary == null) return null;
    return translationForCue(
      cue: cue,
      secondaryCues: secondary.cues,
      primaryOffset: subtitleController.primarySubtitleOffset,
      secondaryOffset: subtitleController.secondarySubtitleOffset,
    );
  }

  RhythmFrame? get _currentRhythmFrame {
    final cue = subtitleController.currentPrimaryCue;
    if (cue == null) return null;
    return subtitleController.llTimelineDocument?.rhythmFrameForSentence(
          cue.id,
        ) ??
        subtitleController
            .phoneticAnalysisBySentence[cue.id]
            ?.soundAnalysis
            ?.rhythmFrame;
  }

  String? _timingQuality(String sentenceId) {
    final timings = subtitleController.timingsBySentence[sentenceId];
    if (timings == null || timings.isEmpty) return null;
    final first = timings.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _diagnosisCard() => ValueListenableBuilder<DetectedPhone?>(
    valueListenable: subtitleController.currentDetectedPhoneListenable,
    builder: (context, currentDetectedPhone, _) => DiagnosisCard(
      diagnosis: learningController.diagnosis!,
      pronunciation: subtitleController.currentPrimaryCue == null
          ? null
          : subtitleController.pronunciationBySentence[subtitleController
                .currentPrimaryCue!
                .id],
      ruleHintsLevel: settingsController.ruleHintsLevel,
      pronunciationProviders: subtitleController.pronunciationProviders,
      timingQuality: subtitleController.currentPrimaryCue == null
          ? null
          : _timingQuality(subtitleController.currentPrimaryCue!.id),
      rhythmFrame: _currentRhythmFrame,
      phoneticAnalysis: subtitleController.currentPrimaryCue == null
          ? null
          : subtitleController.phoneticAnalysisBySentence[subtitleController
                .currentPrimaryCue!
                .id],
      currentDetectedPhone: currentDetectedPhone,
      onLoopDetectedPhone: (phone) => unawaited(
        playbackActions.loopRange(
          phone.start.inMilliseconds,
          phone.end.inMilliseconds,
          'Looping detected phone ${phone.displayIpa}',
          labelKey: 'loopPhone',
        ),
      ),
      onLoopHotspot: (hotspot) => unawaited(
        playbackActions.loopRange(
          hotspot.start.inMilliseconds,
          hotspot.end.inMilliseconds,
          'Looping listening hotspot ${hotspot.label}',
          labelKey: 'loopHotspot',
        ),
      ),
      onLoopFinding: (finding) => unawaited(
        playbackActions.loopRange(
          finding.audioStartMs,
          finding.audioEndMs,
          'Looping audio finding evidence',
          labelKey: 'loopEvidence',
        ),
      ),
      onFindingFeedback: (finding, value) => unawaited(
        playbackActions.savePhoneticFindingFeedback(finding, value),
      ),
      onOpenListeningDictionary: widget.onOpenListeningDictionary,
      onLoopL1Span: (span) => unawaited(
        playbackActions.loopRange(
          span.startMs,
          span.endMs,
          'Looping L1 difficulty evidence ${span.label}',
          labelKey: 'l1ListenAgain',
        ),
      ),
      onOpenL1Specialty: widget.onOpenL1Specialty == null
          ? null
          : (hint) => unawaited(widget.onOpenL1Specialty!(hint)),
    ),
  );
}

/// The honest "this layer isn't ready" card for the text analysis layer.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      key: const Key('analysis-text-unavailable'),
      decoration: BoxDecoration(
        borderRadius: ListenRadii.controlBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.titleSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: ListenSpacing.gap6),
            Text(
              body,
              style: theme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the voice layer shows before a diagnosis has been loaded.
class _AnalysisPending extends StatelessWidget {
  const _AnalysisPending({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('transcript-analysis-pending'),
      decoration: BoxDecoration(
        borderRadius: ListenRadii.controlBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: ListenSpacing.gap8),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
