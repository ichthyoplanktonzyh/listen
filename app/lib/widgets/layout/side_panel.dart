import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/practice_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/listening.dart';
import '../../models/practice.dart';
import '../../models/timeline.dart';
import '../panels/diagnosis_card.dart';
import '../panels/listening_inbox_panel.dart';
import '../panels/practice_panel.dart';
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
    required this.practiceController,
    required this.settingsController,
    required this.resourceActions,
    required this.mediaSession,
    required this.playbackActions,
    required this.transcriptController,
    required this.transcriptItemExtent,
    required this.onOpenWord,
    required this.onSeekCue,
    required this.onSetSelectedWordStatus,
    required this.onSaveSelectedLearningContent,
    required this.onObserveSelected,
    required this.onManualReviewTimeline,
    required this.onDeleteSubtitle,
    required this.onExportSubtitle,
    required this.onAnalyzePhonetics,
    required this.onStartClozePractice,
    required this.onStartChunkDictationPractice,
    required this.onStartSentenceDictationPractice,
    required this.onMarkStuckPoint,
    required this.onSkipStuckPoint,
    required this.onReplayPracticeWindow,
    required this.onSubmitPractice,
    required this.onSavePracticeReview,
    required this.onCompletePracticeSession,
    required this.onReplayStuckPoint,
    required this.onCloseStuckPoint,
    required this.onOpenDiagnosisView,
    required this.onRefreshListeningInbox,
    required this.onReplayListeningInboxItem,
    required this.onProcessListeningInboxItem,
    required this.timingQuality,
  });

  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
  final ExtensiveListeningController extensiveListeningController;
  final PracticeController practiceController;
  final SettingsController settingsController;
  final ResourceActionsCoordinator resourceActions;
  final MediaSessionCoordinator mediaSession;
  final PlaybackActionsCoordinator playbackActions;
  final ScrollController transcriptController;
  final double transcriptItemExtent;
  final Future<void> Function(SubtitleToken token, Cue cue) onOpenWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function(String? selected) onSetSelectedWordStatus;
  final Future<void> Function(String? definition, String? note)
  onSaveSelectedLearningContent;
  final Future<void> Function(bool heard) onObserveSelected;
  final Future<void> Function() onManualReviewTimeline;
  final Future<void> Function(SubtitleTrack track) onDeleteSubtitle;
  final Future<void> Function(SubtitleTrack track) onExportSubtitle;
  final Future<void> Function({required bool wholeTrack}) onAnalyzePhonetics;
  final Future<void> Function() onStartClozePractice;
  final Future<void> Function() onStartChunkDictationPractice;
  final Future<void> Function() onStartSentenceDictationPractice;
  final Future<void> Function() onMarkStuckPoint;
  final Future<void> Function() onSkipStuckPoint;
  final Future<void> Function() onReplayPracticeWindow;
  final Future<void> Function() onSubmitPractice;
  final Future<void> Function() onSavePracticeReview;
  final Future<void> Function() onCompletePracticeSession;
  final Future<void> Function(StuckPointSummary point) onReplayStuckPoint;
  final Future<void> Function(StuckPointSummary point) onCloseStuckPoint;
  final Future<void> Function() onOpenDiagnosisView;
  final Future<void> Function() onRefreshListeningInbox;
  final Future<void> Function(ListeningInboxItem item)
  onReplayListeningInboxItem;
  final Future<void> Function(ListeningInboxItem item, String resolution)
  onProcessListeningInboxItem;
  final String Function(String sentenceId) timingQuality;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  PlayerController get playerController => widget.playerController;
  SubtitleController get subtitleController => widget.subtitleController;
  LearningController get learningController => widget.learningController;
  ExtensiveListeningController get extensiveListeningController =>
      widget.extensiveListeningController;
  PracticeController get practiceController => widget.practiceController;
  SettingsController get settingsController => widget.settingsController;
  ResourceActionsCoordinator get resourceActions => widget.resourceActions;
  MediaSessionCoordinator get mediaSession => widget.mediaSession;
  PlaybackActionsCoordinator get playbackActions => widget.playbackActions;
  ScrollController get transcriptController => widget.transcriptController;
  double get transcriptItemExtent => widget.transcriptItemExtent;
  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _openWord(SubtitleToken token, Cue cue) =>
      widget.onOpenWord(token, cue);
  Future<void> _seekCue(Cue? cue) => widget.onSeekCue(cue);
  Future<void> _setSelectedWordStatus(String? selected) =>
      widget.onSetSelectedWordStatus(selected);
  Future<void> _saveSelectedLearningContent(String? definition, String? note) =>
      widget.onSaveSelectedLearningContent(definition, note);
  Future<void> _observeSelected(bool heard) => widget.onObserveSelected(heard);
  Future<void> _openManualReviewTimeline() => widget.onManualReviewTimeline();
  Future<void> _deleteSubtitleResource(SubtitleTrack track) =>
      widget.onDeleteSubtitle(track);
  Future<void> _exportSubtitleResource(SubtitleTrack track) =>
      widget.onExportSubtitle(track);
  Future<void> _analyzePhonetics({required bool wholeTrack}) =>
      widget.onAnalyzePhonetics(wholeTrack: wholeTrack);
  Future<void> _startClozePractice() => widget.onStartClozePractice();
  Future<void> _startChunkDictationPractice() =>
      widget.onStartChunkDictationPractice();
  Future<void> _startSentenceDictationPractice() =>
      widget.onStartSentenceDictationPractice();
  Future<void> _markStuckPoint() => widget.onMarkStuckPoint();
  Future<void> _skipStuckPoint() => widget.onSkipStuckPoint();
  Future<void> _replayPracticeWindow() => widget.onReplayPracticeWindow();
  Future<void> _submitPractice() => widget.onSubmitPractice();
  Future<void> _savePracticeReview() => widget.onSavePracticeReview();
  Future<void> _completePracticeSession() => widget.onCompletePracticeSession();
  Future<void> _replayStuckPoint(StuckPointSummary point) =>
      widget.onReplayStuckPoint(point);
  Future<void> _closeStuckPoint(StuckPointSummary point) =>
      widget.onCloseStuckPoint(point);
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

  bool get _hasEstimatedWordTiming {
    final cue = subtitleController.currentPrimaryCue;
    if (cue == null) return false;
    return (subtitleController.timingsBySentence[cue.id] ?? const []).any(
      (value) => value.source == 'estimated',
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

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      children: [
        _panelNavigation(),
        _postureActions(),
        Expanded(
          child: switch (learningController.sidePanel) {
            1 => _subtitleResources(),
            2 =>
              learningController.selectedLexicalDetails == null
                  ? Center(child: Text(l.text('noWordSelected')))
                  : WordLearningPanel(
                      details: learningController.selectedLexicalDetails!,
                      dictionary: learningController.selectedDictionary,
                      pronunciation: learningController.selectedPronunciation,
                      languageProfile:
                          learningController.currentLanguageProfile,
                      onStatus: _setSelectedWordStatus,
                      onSave: _saveSelectedLearningContent,
                      onSource: playbackActions.playOccurrence,
                      onHeard: () => _observeSelected(true),
                      onNotHeard: () => _observeSelected(false),
                    ),
            3 =>
              learningController.diagnosis == null
                  ? Center(child: Text(l.text('diagnosis')))
                  : _diagnosisCard(),
            4 => _practicePanel(),
            5 => ListeningInboxPanel(
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
      (Icons.analytics_outlined, l.text('diagnosis')),
      (Icons.fact_check_outlined, l.text('practice')),
      (Icons.inbox_outlined, l.text('listeningInbox')),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: Tooltip(
                  message: destinations[index].$2,
                  child: InkWell(
                    onTap: () {
                      if (index == 3) {
                        unawaited(_openDiagnosisView());
                      } else {
                        learningController.selectSidePanel(index);
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: learningController.sidePanel == index
                            ? colors.primaryContainer
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: learningController.sidePanel == index
                                ? colors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          destinations[index].$1,
                          size: 21,
                          color: learningController.sidePanel == index
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _transcript() => TranscriptPanel(
    track: subtitleController.primaryTrack,
    scrollController: transcriptController,
    itemExtent: transcriptItemExtent,
    currentCue: subtitleController.currentPrimaryCue,
    wordEntries: learningController.wordEntries,
    showStyles: subtitleController.statusStylesVisible,
    baseColor: settingsController.primaryColor,
    onWord: _openWord,
    onSeekCue: _seekCue,
  );

  Widget _subtitleResources() => SubtitleResourceManagerPanel(
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
    onAnalyzePhonetics: settingsController.phoneticAnalysisPreference == 'off'
        ? null
        : () => unawaited(_analyzePhonetics(wholeTrack: false)),
    onAnalyzeTrackPhonetics:
        settingsController.phoneticAnalysisPreference == 'off'
        ? null
        : () => unawaited(_analyzePhonetics(wholeTrack: true)),
    onLoopDetectedPhone: (phone) => unawaited(
      playbackActions.loopRange(
        phone.start.inMilliseconds,
        phone.end.inMilliseconds,
        'Looping detected phone ${phone.displayIpa}',
      ),
    ),
    onLoopHotspot: (hotspot) => unawaited(
      playbackActions.loopRange(
        hotspot.start.inMilliseconds,
        hotspot.end.inMilliseconds,
        'Looping listening hotspot ${hotspot.label}',
      ),
    ),
    onLoopFinding: (finding) => unawaited(
      playbackActions.loopRange(
        finding.audioStartMs,
        finding.audioEndMs,
        'Looping audio finding evidence',
      ),
    ),
    onFindingFeedback: (finding, value) =>
        unawaited(playbackActions.savePhoneticFindingFeedback(finding, value)),
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
              learningController.selectSidePanel(4);
              switch (value) {
                case 'cloze':
                  unawaited(_startClozePractice());
                case 'chunk':
                  unawaited(_startChunkDictationPractice());
                case 'sentence':
                  unawaited(_startSentenceDictationPractice());
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
            child: Chip(
              avatar: Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: hasCue ? null : Theme.of(context).disabledColor,
              ),
              label: Text(
                l.text('testPosture'),
                style: TextStyle(
                  color: hasCue ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
          ),
          Tooltip(
            message: l.text('shadowingPlannedTooltip'),
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.mic_none),
              label: Text(l.text('shadowPosture')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _practicePanel() => PracticePanel(
    controller: practiceController,
    currentCue: subtitleController.currentPrimaryCue,
    diagnosis: learningController.diagnosis,
    canCloze: _canCloze,
    canChunkDictation: _canChunkDictation,
    hasEstimatedWordTiming: _hasEstimatedWordTiming,
    onStartCloze: _startClozePractice,
    onStartChunkDictation: _startChunkDictationPractice,
    onStartSentenceDictation: _startSentenceDictationPractice,
    onMarkStuckPoint: _markStuckPoint,
    onSkipStuckPoint: _skipStuckPoint,
    onReplay: _replayPracticeWindow,
    onSubmit: _submitPractice,
    onSaveReview: _savePracticeReview,
    onCompleteSession: _completePracticeSession,
    onReplayStuckPoint: _replayStuckPoint,
    onCloseStuckPoint: _closeStuckPoint,
    onOpenDiagnosis: _openDiagnosisView,
  );
}
