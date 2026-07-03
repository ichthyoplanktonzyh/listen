import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../panels/diagnosis_card.dart';
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
    required this.timingQuality,
  });

  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
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
  final String Function(String sentenceId) timingQuality;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  PlayerController get playerController => widget.playerController;
  SubtitleController get subtitleController => widget.subtitleController;
  LearningController get learningController => widget.learningController;
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
  String _timingQuality(String sentenceId) => widget.timingQuality(sentenceId);

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff151a20),
    child: Column(
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.subtitles),
              label: Text(l.text('transcript')),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(l.text('subtitleResources')),
            ),
            ButtonSegment(
              value: 2,
              icon: const Icon(Icons.menu_book),
              label: Text(l.text('wordLearning')),
            ),
            ButtonSegment(
              value: 3,
              icon: const Icon(Icons.analytics_outlined),
              label: Text(l.text('diagnosis')),
            ),
          ],
          selected: {learningController.sidePanel},
          onSelectionChanged: (value) =>
              learningController.selectSidePanel(value.first),
          showSelectedIcon: false,
        ),
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
            _ => _transcript(),
          },
        ),
      ],
    ),
  );

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
}
