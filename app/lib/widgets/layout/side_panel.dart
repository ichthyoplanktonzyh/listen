import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../models/timeline.dart';
import '../panels/transcript_panel.dart';
import '../panels/timeline_resource_summary_panel.dart';
import '../panels/word_learning_panel.dart';
import '../panels/diagnosis_card.dart';

/// The right-side panel with tabbed content: Transcript, Resources, Word, Diagnosis.
///
/// Extracted from the monolithic `_sidePanel()` in main.dart
/// to reduce the orchestrator's build method complexity.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.learningController,
    required this.subtitleController,
    required this.transcriptController,
    required this.transcriptItemExtent,
    required this.wordProfiles,
    required this.showStyles,
    required this.baseColor,
    required this.languageProfile,
    required this.onWord,
    required this.onSeekCue,
    required this.onSetWordStatus,
    required this.onSaveWordContent,
    required this.onPlayOccurrence,
    required this.onObserveHeard,
    required this.onObserveNotHeard,
    required this.onAnalyzePhonetics,
    required this.onAnalyzeTrackPhonetics,
    required this.onLoopDetectedPhone,
    required this.onLoopPhoneticFinding,
    required this.onPhoneticFindingFeedback,
    required this.onImportTimeline,
    required this.onRefreshTimeline,
    required this.onActivateWordTimeline,
    required this.onManualReview,
    required this.onActivatePhoneTimeline,
    required this.onArchivePhoneTimeline,
    required this.onDeletePhoneTimeline,
    required this.onGenerateChunkTimeline,
    required this.onActivateChunkTimeline,
    required this.onArchiveChunkTimeline,
    required this.onDeleteChunkTimeline,
    required this.onExportLLTimeline,
  });

  final LearningController learningController;
  final SubtitleController subtitleController;
  final ScrollController transcriptController;
  final double transcriptItemExtent;
  final Map<String, Map<String, dynamic>> wordProfiles;
  final bool showStyles;
  final Color baseColor;
  final Map<String, dynamic>? languageProfile;

  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;

  // Word panel callbacks
  final ValueChanged<String?> onSetWordStatus;
  final Future<void> Function(String?, String?) onSaveWordContent;
  final ValueChanged<Map<String, dynamic>> onPlayOccurrence;
  final VoidCallback onObserveHeard;
  final VoidCallback onObserveNotHeard;

  // Diagnosis callbacks
  final VoidCallback? onAnalyzePhonetics;
  final VoidCallback? onAnalyzeTrackPhonetics;
  final ValueChanged<DetectedPhone>? onLoopDetectedPhone;
  final ValueChanged<Map<String, dynamic>>? onLoopPhoneticFinding;
  final void Function(Map<String, dynamic> finding, String value)?
  onPhoneticFindingFeedback;

  // Timeline resource callbacks
  final Future<void> Function() onImportTimeline;
  final Future<void> Function() onRefreshTimeline;
  final Future<void> Function(String timelineId) onActivateWordTimeline;
  final Future<void> Function() onManualReview;
  final Future<void> Function(String timelineId) onActivatePhoneTimeline;
  final Future<void> Function(String timelineId) onArchivePhoneTimeline;
  final Future<void> Function(String timelineId) onDeletePhoneTimeline;
  final Future<void> Function() onGenerateChunkTimeline;
  final Future<void> Function(String timelineId) onActivateChunkTimeline;
  final Future<void> Function(String timelineId) onArchiveChunkTimeline;
  final Future<void> Function(String timelineId) onDeleteChunkTimeline;
  final Future<void> Function()? onExportLLTimeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lc = learningController;

    return Material(
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
            selected: {lc.sidePanel},
            onSelectionChanged: (value) => lc.selectSidePanel(value.first),
            showSelectedIcon: false,
          ),
          Expanded(
            child: _panelContent(context, l),
          ),
        ],
      ),
    );
  }

  Widget _panelContent(BuildContext context, AppLocalizations l) {
    final lc = learningController;
    final sc = subtitleController;

    switch (lc.sidePanel) {
      case 1:
        return TimelineResourceSummaryPanel(
          document: sc.llTimelineDocument,
          summaries: sc.wordTimelineSummaries,
          phoneSummaries: sc.phoneTimelineSummaries,
          chunkSummaries: sc.chunkTimelineSummaries,
          error: sc.timelineResourceError,
          onImport: onImportTimeline,
          onRefresh: onRefreshTimeline,
          onActivate: onActivateWordTimeline,
          onManualReview: onManualReview,
          onActivatePhoneTimeline: onActivatePhoneTimeline,
          onArchivePhoneTimeline: onArchivePhoneTimeline,
          onDeletePhoneTimeline: onDeletePhoneTimeline,
          onGenerateChunkTimeline: onGenerateChunkTimeline,
          onActivateChunkTimeline: onActivateChunkTimeline,
          onArchiveChunkTimeline: onArchiveChunkTimeline,
          onDeleteChunkTimeline: onDeleteChunkTimeline,
          onExportLLTimeline: onExportLLTimeline,
        );
      case 2:
        final details = lc.selectedWordDetails;
        if (details == null) {
          return Center(child: Text(l.text('noWordSelected')));
        }
        return WordLearningPanel(
          details: details,
          dictionary: lc.selectedDictionary,
          pronunciation: lc.selectedPronunciation,
          languageProfile: languageProfile,
          onStatus: onSetWordStatus,
          onSave: onSaveWordContent,
          onSource: onPlayOccurrence,
          onHeard: onObserveHeard,
          onNotHeard: onObserveNotHeard,
        );
      case 3:
        final diagnosis = lc.diagnosis;
        if (diagnosis == null) {
          return Center(child: Text(l.text('diagnosis')));
        }
        final cue = sc.currentPrimaryCue;
        final timingQuality = cue != null && sc.timingsBySentence.containsKey(cue.id)
            ? '${sc.timingsBySentence[cue.id]!.first.source.replaceAll('_', ' ')} · ${sc.timingsBySentence[cue.id]!.first.provider}'
            : null;
        return DiagnosisCard(
          diagnosis: diagnosis,
          pronunciation: sc.pronunciationBySentence[cue?.id],
          ruleHintsLevel: 'likely',  // from settings
          pronunciationProviders: sc.pronunciationProviders,
          timingQuality: timingQuality,
          phoneticAnalysis: sc.phoneticAnalysisBySentence[cue?.id],
          currentDetectedPhone: sc.currentDetectedPhone,
          onAnalyzePhonetics: onAnalyzePhonetics,
          onAnalyzeTrackPhonetics: onAnalyzeTrackPhonetics,
          onLoopDetectedPhone: onLoopDetectedPhone,
          onLoopFinding: onLoopPhoneticFinding,
          onFindingFeedback: onPhoneticFindingFeedback,
        );
      default:
        return TranscriptPanel(
          track: sc.primaryTrack,
          scrollController: transcriptController,
          itemExtent: transcriptItemExtent,
          currentCue: sc.currentPrimaryCue,
          wordProfiles: wordProfiles,
          showStyles: showStyles,
          baseColor: baseColor,
          onWord: onWord,
          onSeekCue: onSeekCue,
        );
    }
  }
}
