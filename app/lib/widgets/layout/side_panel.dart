import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/listening.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../panels/content_fit_card.dart';
import '../panels/diagnosis_card.dart';
import '../panels/listening_inbox_panel.dart';
import '../panels/transcript_panel.dart';
import '../panels/word_bubble.dart';
import '../panels/word_learning_panel.dart';
import 'side_panel_tabs.dart';

/// The right-hand panel: the transcript, and what this session has produced.
///
/// It used to be a five-way router — transcript, subtitle resources, word,
/// diagnosis, inbox — where four of the five replaced the transcript. That is
/// what made the workbench feel broken: every word lookup and every analysis
/// took the text off screen, and coming back meant hunting for the line again.
///
/// So the transcript is now the floor. Word lookups open as a bubble over the
/// word ([showWordBubble]); analysis expands inside the sentence it describes;
/// subtitle and timeline resources moved to the session header, where the rest
/// of the actions on *this media* already live. What is left is two panes:
/// the text, and the notes it produced.
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.playerController,
    required this.subtitleController,
    required this.learningController,
    required this.extensiveListeningController,
    required this.settingsController,
    required this.mediaSession,
    required this.playbackActions,
    required this.transcriptController,
    required this.onOpenWord,
    required this.onSeekCue,
    required this.onSetSelectedWordStatus,
    required this.onSetCapabilityOverride,
    required this.onSaveSelectedLearningContent,
    required this.onObserveSelected,
    required this.onRequestDiagnosis,
    required this.onOpenSlicePlayback,
    this.onOpenListeningDictionary,
    this.onPlayPronunciationAudio,
    this.onOpenL1Specialty,
    this.onCorrectLemma,
    required this.onRefreshListeningInbox,
    required this.onReplayListeningInboxItem,
    required this.onProcessListeningInboxItem,
    required this.timingQuality,
    this.onStartColdStart,
    this.onRecordCurrentSource,
    this.onReadingMark,
  });

  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
  final ExtensiveListeningController extensiveListeningController;
  final SettingsController settingsController;
  final MediaSessionCoordinator mediaSession;
  final PlaybackActionsCoordinator playbackActions;
  final ScrollController transcriptController;
  final Future<void> Function(SubtitleToken token, Cue cue) onOpenWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function(String? selected) onSetSelectedWordStatus;
  final Future<void> Function(String capability, String? conclusion)
  onSetCapabilityOverride;
  final Future<void> Function(String? definition, String? note)
  onSaveSelectedLearningContent;
  final Future<void> Function(bool heard) onObserveSelected;

  /// Loads the analysis for the current sentence. Called when the reader
  /// expands it and nothing has been loaded yet.
  final Future<void> Function() onRequestDiagnosis;
  final Future<void> Function(Map<String, dynamic> occurrence)
  onOpenSlicePlayback;
  final Future<void> Function(String lexicalEntryId)? onOpenListeningDictionary;
  final ValueChanged<String>? onPlayPronunciationAudio;
  final Future<void> Function(L1DiagnosisHint hint)? onOpenL1Specialty;

  /// Corrects the lemma of the currently selected token (#16 moved this out
  /// of the global AppBar menu, where it had no context to act on).
  final VoidCallback? onCorrectLemma;
  final Future<void> Function() onRefreshListeningInbox;
  final Future<void> Function(ListeningInboxItem item)
  onReplayListeningInboxItem;
  final Future<void> Function(ListeningInboxItem item, String resolution)
  onProcessListeningInboxItem;
  final String Function(String sentenceId) timingQuality;
  final VoidCallback? onStartColdStart;
  final VoidCallback? onRecordCurrentSource;

  /// Explicit reading mark for the selected word; non-null only while the
  /// reading posture is open (Phase 3.13 Slice 5).
  final void Function(bool understood)? onReadingMark;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  PlayerController get playerController => widget.playerController;
  SubtitleController get subtitleController => widget.subtitleController;
  LearningController get learningController => widget.learningController;
  ExtensiveListeningController get extensiveListeningController =>
      widget.extensiveListeningController;
  SettingsController get settingsController => widget.settingsController;
  MediaSessionCoordinator get mediaSession => widget.mediaSession;
  PlaybackActionsCoordinator get playbackActions => widget.playbackActions;
  ScrollController get transcriptController => widget.transcriptController;
  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _seekCue(Cue? cue) => widget.onSeekCue(cue);
  Future<void> _setSelectedWordStatus(String? selected) =>
      widget.onSetSelectedWordStatus(selected);
  Future<void> _saveSelectedLearningContent(String? definition, String? note) =>
      widget.onSaveSelectedLearningContent(definition, note);
  Future<void> _observeSelected(bool heard) => widget.onObserveSelected(heard);
  Future<void> _setCapabilityOverride(String capability, String? conclusion) =>
      widget.onSetCapabilityOverride(capability, conclusion);
  Future<void> _refreshListeningInbox() => widget.onRefreshListeningInbox();
  Future<void> _replayListeningInboxItem(ListeningInboxItem item) =>
      widget.onReplayListeningInboxItem(item);
  Future<void> _processListeningInboxItem(
    ListeningInboxItem item,
    String resolution,
  ) => widget.onProcessListeningInboxItem(item, resolution);
  String _timingQuality(String sentenceId) => widget.timingQuality(sentenceId);

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

  /// Looks the word up and shows the result over the word, not instead of it.
  ///
  /// The lookup and the bubble start together on purpose: the bubble opens
  /// immediately in its waiting state and fills in as the entry and then the
  /// dictionary arrive, so a slow provider delays the definition rather than
  /// the feedback that the click landed.
  Future<void> _openWord(SubtitleToken token, Cue cue, Offset anchor) async {
    unawaited(widget.onOpenWord(token, cue));
    await showWordBubble(
      context: context,
      anchor: anchor,
      learning: learningController,
      onStatus: (value) => unawaited(_setSelectedWordStatus(value)),
      onOpenDetails: () => learningController.selectTab(SidePanelTab.notes),
      onPlayPronunciationAudio: widget.onPlayPronunciationAudio,
    );
  }

  void _toggleAnalysis() {
    final expanded = !learningController.diagnosisExpanded;
    learningController.setDiagnosisExpanded(expanded);
    if (expanded && learningController.diagnosis == null) {
      unawaited(widget.onRequestDiagnosis());
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      children: [
        SidePanelTabs(
          selected: learningController.tab,
          onSelected: learningController.selectTab,
        ),
        // Content fit is a media-level "should I watch this, and how" signal,
        // so it belongs over the transcript — the browse/decide surface —
        // rather than buried in the technical resource manager.
        if (learningController.tab == SidePanelTab.transcript &&
            subtitleController.contentFit != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ListenSpacing.gap12,
              ListenSpacing.gap8,
              ListenSpacing.gap12,
              ListenSpacing.gap8,
            ),
            child: ContentFitCard(
              profile: subtitleController.contentFit!,
              onStartColdStart: widget.onStartColdStart,
            ),
          ),
        Expanded(
          child: switch (learningController.tab) {
            SidePanelTab.notes => _notes(),
            SidePanelTab.transcript => _transcript(),
          },
        ),
      ],
    ),
  );

  Widget _transcript() => TranscriptPanel(
    track: subtitleController.primaryTrack,
    scrollController: transcriptController,
    currentCue: subtitleController.currentPrimaryCue,
    wordEntries: learningController.wordEntries,
    capabilityProfiles: learningController.capabilityProfiles,
    showStyles: subtitleController.statusStylesVisible,
    baseColor: settingsController.primaryColor,
    onWord: _openWord,
    onSeekCue: _seekCue,
    onImportSubtitle: playerController.mediaId == null
        ? null
        : () async => mediaSession.openSubtitle(secondary: false),
    groupingMode: settingsController.groupingMode,
    chunkDisplayStyle: settingsController.chunkDisplayStyle,
    // Both grouping layers flow in independently (ADR 0016); the transcript's
    // TokenLine honors the same mode as the on-video subtitle.
    chunkPartitionsBySentence: subtitleController.chunkPartitionsBySentence,
    senseGroupsBySentence: subtitleController.senseGroupsBySentence,
    onToggleAnalysis: subtitleController.currentPrimaryCue == null
        ? null
        : _toggleAnalysis,
    analysisExpanded: learningController.diagnosisExpanded,
    analysis: learningController.diagnosis == null
        ? _AnalysisPending(
            message: l.text('openSentenceDiagnosisHint'),
            actionLabel: l.text('openDiagnosis'),
            onAction: () => unawaited(widget.onRequestDiagnosis()),
          )
        : _diagnosisCard(),
  );

  /// The session's own notes: the word being studied in full, and — while an
  /// extensive-listening session is running or has left captures behind — the
  /// inbox those captures land in.
  ///
  /// The inbox is not given a permanent split of this pane. When there is
  /// nothing in it and no session running, the word takes the whole tab
  /// instead of sharing it with an empty box.
  Widget _notes() {
    final word = learningController.selectedLexicalDetails == null
        ? _PanelEmptyState(
            icon: Icons.menu_book_outlined,
            title: l.text('noWordSelected'),
            message: l.text('selectWordFromTranscript'),
          )
        : WordLearningPanel(
            details: learningController.selectedLexicalDetails!,
            dictionary: learningController.selectedDictionary,
            pronunciation: learningController.selectedPronunciation,
            languageProfile: learningController.currentLanguageProfile,
            onStatus: _setSelectedWordStatus,
            onSave: _saveSelectedLearningContent,
            onSource: widget.onOpenSlicePlayback,
            onHeard: () => _observeSelected(true),
            onNotHeard: () => _observeSelected(false),
            onCapabilityOverride: _setCapabilityOverride,
            onRecordSource: widget.onRecordCurrentSource,
            onReadingMark: widget.onReadingMark,
            onCorrectLemma: widget.onCorrectLemma,
            onOpenListeningDictionary:
                widget.onOpenListeningDictionary == null
                ? null
                : () => unawaited(
                    widget.onOpenListeningDictionary!(
                      learningController.selectedLexicalDetails!.entry.id,
                    ),
                  ),
            onPlayPronunciationAudio: widget.onPlayPronunciationAudio,
            hasSelectedCue: subtitleController.currentPrimaryCue != null,
          );

    final showInbox =
        extensiveListeningController.active ||
        extensiveListeningController.activeItemCount > 0;
    if (!showInbox) return word;
    return Column(
      children: [
        Expanded(flex: 3, child: word),
        Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(
          flex: 2,
          child: ListeningInboxPanel(
            controller: extensiveListeningController,
            onRefresh: _refreshListeningInbox,
            onReplay: _replayListeningInboxItem,
            onProcess: _processListeningInboxItem,
          ),
        ),
      ],
    );
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
      timingQuality:
          subtitleController.currentPrimaryCue == null ||
              (subtitleController.timingsBySentence[subtitleController
                          .currentPrimaryCue!
                          .id] ??
                      const [])
                  .isEmpty
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

/// What the expanded analysis shows before anything has been loaded.
///
/// It states that there is nothing yet and offers to fetch it, rather than
/// rendering an empty box that reads as "this sentence has no findings".
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

class _PanelEmptyState extends StatelessWidget {
  const _PanelEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: ListenPadding.pageCompact,
        child: ConstrainedBox(
          // Same centred-notice measure as the transcript panel's empty state —
          // the two are the same shape and must not drift apart again.
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.noticeColumnMax,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: ListenIconSize.illustration,
                color: colors.primary,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
