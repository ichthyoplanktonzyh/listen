import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/listening.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../panels/content_fit_card.dart';
import '../panels/diagnosis_card.dart';
import '../panels/listening_inbox_panel.dart';
import '../panels/subtitle_resource_manager_panel.dart';
import '../panels/transcript_panel.dart';
import '../panels/word_learning_panel.dart';

/// The right-hand side panel: transcript, subtitle resources, word learning,
/// and diagnosis views behind a segmented selector. Extracted from the
/// composition root; getter names mirror the host's controller fields so the
/// panel tree reads identically at both sites.
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.playerController,
    required this.subtitleController,
    required this.learningController,
    required this.extensiveListeningController,
    required this.settingsController,
    required this.resourceActions,
    required this.mediaSession,
    required this.playbackActions,
    required this.transcriptController,
    required this.onOpenWord,
    required this.onSeekCue,
    required this.onSetSelectedWordStatus,
    required this.onSetCapabilityOverride,
    required this.onSaveSelectedLearningContent,
    required this.onObserveSelected,
    required this.onManualReviewTimeline,
    required this.onDeleteSubtitle,
    required this.onExportSubtitle,
    required this.onStartClozePractice,
    required this.onStartChunkDictationPractice,
    required this.onStartSentenceDictationPractice,
    required this.onStartShadowingPractice,
    this.onOpenReading,
    required this.onOpenDiagnosisView,
    required this.onOpenSlicePlayback,
    this.onOpenListeningDictionary,
    this.onOpenL1Specialty,
    required this.onRefreshListeningInbox,
    required this.onReplayListeningInboxItem,
    required this.onProcessListeningInboxItem,
    required this.timingQuality,
    this.onStartColdStart,
    this.onRecordCurrentSource,
  });

  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
  final ExtensiveListeningController extensiveListeningController;
  final SettingsController settingsController;
  final ResourceActionsCoordinator resourceActions;
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
  final Future<void> Function() onManualReviewTimeline;
  final Future<void> Function(SubtitleTrack track) onDeleteSubtitle;
  final Future<void> Function(SubtitleTrack track) onExportSubtitle;
  final Future<void> Function() onStartClozePractice;
  final Future<void> Function() onStartChunkDictationPractice;
  final Future<void> Function() onStartSentenceDictationPractice;
  final Future<void> Function() onStartShadowingPractice;

  /// Enters the reading posture (Phase 3.13); available whenever a transcript
  /// is loaded — reading does not need a current sentence.
  final VoidCallback? onOpenReading;
  final Future<void> Function() onOpenDiagnosisView;
  final Future<void> Function(Map<String, dynamic> occurrence)
  onOpenSlicePlayback;
  final Future<void> Function(String lexicalEntryId)? onOpenListeningDictionary;
  final Future<void> Function(L1DiagnosisHint hint)? onOpenL1Specialty;
  final Future<void> Function() onRefreshListeningInbox;
  final Future<void> Function(ListeningInboxItem item)
  onReplayListeningInboxItem;
  final Future<void> Function(ListeningInboxItem item, String resolution)
  onProcessListeningInboxItem;
  final String Function(String sentenceId) timingQuality;
  final VoidCallback? onStartColdStart;
  final VoidCallback? onRecordCurrentSource;

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
  ResourceActionsCoordinator get resourceActions => widget.resourceActions;
  MediaSessionCoordinator get mediaSession => widget.mediaSession;
  PlaybackActionsCoordinator get playbackActions => widget.playbackActions;
  ScrollController get transcriptController => widget.transcriptController;
  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _openWord(SubtitleToken token, Cue cue) =>
      widget.onOpenWord(token, cue);
  Future<void> _seekCue(Cue? cue) => widget.onSeekCue(cue);
  Future<void> _setSelectedWordStatus(String? selected) =>
      widget.onSetSelectedWordStatus(selected);
  Future<void> _saveSelectedLearningContent(String? definition, String? note) =>
      widget.onSaveSelectedLearningContent(definition, note);
  Future<void> _observeSelected(bool heard) => widget.onObserveSelected(heard);
  Future<void> _setCapabilityOverride(String capability, String? conclusion) =>
      widget.onSetCapabilityOverride(capability, conclusion);
  Future<void> _openManualReviewTimeline() => widget.onManualReviewTimeline();
  Future<void> _deleteSubtitleResource(SubtitleTrack track) =>
      widget.onDeleteSubtitle(track);
  Future<void> _exportSubtitleResource(SubtitleTrack track) =>
      widget.onExportSubtitle(track);
  Future<void> _openDiagnosisView() => widget.onOpenDiagnosisView();
  Future<void> _refreshListeningInbox() => widget.onRefreshListeningInbox();
  Future<void> _replayListeningInboxItem(ListeningInboxItem item) =>
      widget.onReplayListeningInboxItem(item);
  Future<void> _processListeningInboxItem(
    ListeningInboxItem item,
    String resolution,
  ) => widget.onProcessListeningInboxItem(item, resolution);
  String _timingQuality(String sentenceId) => widget.timingQuality(sentenceId);

  bool get _canCloze {
    final cue = subtitleController.currentPrimaryCue;
    return cue != null &&
        (subtitleController.timingsBySentence[cue.id] ?? const []).isNotEmpty;
  }

  bool get _canChunkDictation {
    final cue = subtitleController.currentPrimaryCue;
    return cue != null &&
        (subtitleController
                .chunkPartitionsBySentence[cue.id]
                ?.chunks
                .isNotEmpty ??
            false);
  }

  // Transcript (0), word learning (2), and diagnosis (3) act on the current
  // sentence; subtitle resources (1) and inbox (4) do not.
  bool get _showsPostureActions =>
      const {0, 2, 3}.contains(learningController.sidePanel);

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

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      children: [
        _panelNavigation(),
        // Posture actions belong to the current sentence; hide them on the
        // resource manager and inbox tabs so they are contextual, not a
        // permanent button wall.
        if (_showsPostureActions) _postureActions(),
        // Content fit is a media-level "should I watch this, and how" signal, so
        // it belongs on the transcript tab (the browse/decide surface) rather
        // than buried in the technical subtitle-resources panel. Showing the
        // full card here surfaces the cold-start prompt and intensive-listening
        // hint that a one-line summary would drop.
        if (learningController.sidePanel == 0 &&
            subtitleController.contentFit != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: ContentFitCard(
              profile: subtitleController.contentFit!,
              onStartColdStart: widget.onStartColdStart,
            ),
          ),
        Expanded(
          child: switch (learningController.sidePanel) {
            1 => _subtitleResources(),
            2 =>
              learningController.selectedLexicalDetails == null
                  ? _PanelEmptyState(
                      icon: Icons.menu_book_outlined,
                      title: l.text('noWordSelected'),
                      message: l.text('selectWordFromTranscript'),
                    )
                  : WordLearningPanel(
                      details: learningController.selectedLexicalDetails!,
                      dictionary: learningController.selectedDictionary,
                      pronunciation: learningController.selectedPronunciation,
                      languageProfile:
                          learningController.currentLanguageProfile,
                      onStatus: _setSelectedWordStatus,
                      onSave: _saveSelectedLearningContent,
                      onSource: widget.onOpenSlicePlayback,
                      onHeard: () => _observeSelected(true),
                      onNotHeard: () => _observeSelected(false),
                      onCapabilityOverride: _setCapabilityOverride,
                      onRecordSource: widget.onRecordCurrentSource,
                      onOpenListeningDictionary:
                          widget.onOpenListeningDictionary == null
                          ? null
                          : () => unawaited(
                              widget.onOpenListeningDictionary!(
                                learningController
                                    .selectedLexicalDetails!
                                    .entry
                                    .id,
                              ),
                            ),
                      hasSelectedCue:
                          subtitleController.currentPrimaryCue != null,
                    ),
            3 =>
              learningController.diagnosis == null
                  ? _PanelEmptyState(
                      icon: Icons.analytics_outlined,
                      title: l.text('diagnosisUnavailable'),
                      message: l.text('openSentenceDiagnosisHint'),
                      actionLabel: l.text('openDiagnosis'),
                      onAction: subtitleController.currentPrimaryCue == null
                          ? null
                          : () => unawaited(_openDiagnosisView()),
                    )
                  : _diagnosisCard(),
            4 => ListeningInboxPanel(
              controller: extensiveListeningController,
              onRefresh: _refreshListeningInbox,
              onReplay: _replayListeningInboxItem,
              onProcess: _processListeningInboxItem,
            ),
            _ => _transcript(),
          },
        ),
      ],
    ),
  );

  Widget _panelNavigation() {
    final colors = Theme.of(context).colorScheme;
    final destinations = [
      (Icons.subtitles_outlined, l.text('transcript')),
      (Icons.inventory_2_outlined, l.text('subtitleResources')),
      (Icons.menu_book_outlined, l.text('wordLearning')),
      (Icons.analytics_outlined, l.text('understandPosture')),
      (Icons.inbox_outlined, l.text('listeningInbox')),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = constraints.maxWidth >= 520;
          return SizedBox(
            height: showLabels ? 58 : 52,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: _PanelTab(
                      icon: destinations[index].$1,
                      label: destinations[index].$2,
                      selected: learningController.sidePanel == index,
                      showLabel: showLabels,
                      onTap: () {
                        if (index == 3) {
                          unawaited(_openDiagnosisView());
                        } else {
                          learningController.selectSidePanel(index);
                        }
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

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
  );

  Widget _subtitleResources() => SubtitleResourceManagerPanel(
    contentFit: subtitleController.contentFit,
    mediaId: playerController.mediaId,
    resources: subtitleController.subtitleResources,
    capabilities: subtitleController.subtitleResourceCapabilities,
    activeTrack: subtitleController.primaryTrack,
    timelineDocument: subtitleController.llTimelineDocument,
    wordTimelineSummaries: subtitleController.wordTimelineSummaries,
    phoneTimelineSummaries: subtitleController.phoneTimelineSummaries,
    chunkTimelineSummaries: subtitleController.chunkTimelineSummaries,
    activeWordTimingCount: subtitleController.activeWordTimingCount,
    timelineResourceError: subtitleController.timelineResourceError,
    onImportSubtitle: () async => mediaSession.openSubtitle(secondary: false),
    onImportLLTimeline: mediaSession.openLLTimelineResource,
    onRefreshResources: resourceActions.refreshSubtitleResources,
    onActivateSubtitle: resourceActions.activateSubtitleResource,
    onArchiveSubtitle: resourceActions.archiveSubtitleResource,
    onRestoreSubtitle: resourceActions.restoreSubtitleResource,
    onDeleteSubtitle: _deleteSubtitleResource,
    onExportSubtitle: _exportSubtitleResource,
    onLanguageChanged: resourceActions.changeTrackLanguage,
    availableLanguages: learningController.availableLanguages,
    onExportLLTimeline: resourceActions.exportLLTimelineResource,
    onActivateWordTimeline: resourceActions.activateWordTimeline,
    onManualReviewTimeline: _openManualReviewTimeline,
    onActivatePhoneTimeline: resourceActions.activatePhoneTimeline,
    onArchivePhoneTimeline: resourceActions.archivePhoneTimeline,
    onDeletePhoneTimeline: resourceActions.deletePhoneTimeline,
    onGenerateChunkTimeline: resourceActions.generateChunkTimeline,
    onActivateChunkTimeline: resourceActions.activateChunkTimeline,
    onArchiveChunkTimeline: resourceActions.archiveChunkTimeline,
    onDeleteChunkTimeline: resourceActions.deleteChunkTimeline,
    onStartColdStart: widget.onStartColdStart,
  );

  Widget _diagnosisCard() => DiagnosisCard(
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
    currentDetectedPhone: subtitleController.currentDetectedPhone,
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
    onFindingFeedback: (finding, value) =>
        unawaited(playbackActions.savePhoneticFindingFeedback(finding, value)),
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
  );

  Widget _postureActions() {
    final hasCue = subtitleController.currentPrimaryCue != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          OutlinedButton.icon(
            onPressed: hasCue ? () => unawaited(_openDiagnosisView()) : null,
            icon: const Icon(Icons.analytics_outlined),
            label: Text(l.text('understandPosture')),
          ),
          PopupMenuButton<String>(
            enabled: hasCue,
            tooltip: l.text('testPosture'),
            onSelected: (value) {
              switch (value) {
                case 'cloze':
                  unawaited(widget.onStartClozePractice());
                case 'chunk':
                  unawaited(widget.onStartChunkDictationPractice());
                case 'sentence':
                  unawaited(widget.onStartSentenceDictationPractice());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'cloze',
                enabled: _canCloze,
                child: ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: Text(l.text('clozePractice')),
                  subtitle: Text(
                    _canCloze
                        ? l.text('practiceClozeTooltip')
                        : l.text('practiceClozeUnavailable'),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'chunk',
                child: ListTile(
                  leading: const Icon(Icons.segment),
                  title: Text(l.text('chunkDictation')),
                  subtitle: Text(
                    _canChunkDictation
                        ? l.text('practiceChunkTooltip')
                        : l.text('practiceChunkFallbackTooltip'),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'sentence',
                child: ListTile(
                  leading: const Icon(Icons.short_text),
                  title: Text(l.text('sentenceDictation')),
                ),
              ),
            ],
            child: _MenuTriggerButton(
              icon: Icons.fact_check_outlined,
              label: l.text('testPosture'),
              enabled: hasCue,
            ),
          ),
          Tooltip(
            message: l.text('shadowingReadyTooltip'),
            child: OutlinedButton.icon(
              onPressed: hasCue
                  ? () => unawaited(widget.onStartShadowingPractice())
                  : null,
              icon: const Icon(Icons.mic_none),
              label: Text(l.text('shadowPosture')),
            ),
          ),
          if (widget.onOpenReading != null)
            OutlinedButton.icon(
              onPressed: subtitleController.primaryTrack == null
                  ? null
                  : widget.onOpenReading,
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              label: Text(l.text('readPosture')),
            ),
        ],
      ),
    );
  }
}

/// Outlined dropdown trigger styled to match the sibling [OutlinedButton]
/// posture actions, so the Test menu no longer reads as a stray chip. The
/// button itself stays inert; the enclosing [PopupMenuButton] opens the menu.
class _MenuTriggerButton extends StatelessWidget {
  const _MenuTriggerButton({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled
        ? colors.primary
        : Theme.of(context).disabledColor;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? colors.outline : colors.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 20, color: foreground),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: showLabel
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    icon,
                    size: 21,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
          ),
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
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: colors.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
