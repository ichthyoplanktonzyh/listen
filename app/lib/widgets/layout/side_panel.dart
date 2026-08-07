import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/listening.dart';
import '../../models/timeline.dart';
import '../../models/workbench_study_mode.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/transcript_translation.dart';
import '../panels/content_fit_card.dart';
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
    required this.transcriptController,
    required this.onOpenWord,
    required this.onSeekCue,
    required this.onSetSelectedWordStatus,
    required this.onSetCapabilityOverride,
    required this.onSaveSelectedLearningContent,
    required this.onObserveSelected,
    required this.onOpenSlicePlayback,
    this.onOpenListeningDictionary,
    this.onPlayPronunciationAudio,
    this.onCorrectLemma,
    required this.onRefreshListeningInbox,
    required this.onReplayListeningInboxItem,
    required this.onProcessListeningInboxItem,
    this.onStartColdStart,
    this.onRecordCurrentSource,
    this.onReadingMark,
    this.studyMode = WorkbenchStudyMode.normal,
  });

  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
  final ExtensiveListeningController extensiveListeningController;
  final SettingsController settingsController;
  final MediaSessionCoordinator mediaSession;
  final ScrollController transcriptController;
  final Future<void> Function(SubtitleToken token, Cue cue) onOpenWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function(String? selected) onSetSelectedWordStatus;
  final Future<void> Function(String capability, String? conclusion)
  onSetCapabilityOverride;
  final Future<void> Function(String? definition, String? note)
  onSaveSelectedLearningContent;
  final Future<void> Function(bool heard) onObserveSelected;

  final Future<void> Function(Map<String, dynamic> occurrence)
  onOpenSlicePlayback;
  final Future<void> Function(String lexicalEntryId)? onOpenListeningDictionary;
  final ValueChanged<String>? onPlayPronunciationAudio;

  /// Corrects the lemma of the currently selected token (#16 moved this out
  /// of the global AppBar menu, where it had no context to act on).
  final VoidCallback? onCorrectLemma;
  final Future<void> Function() onRefreshListeningInbox;
  final Future<void> Function(ListeningInboxItem item)
  onReplayListeningInboxItem;
  final Future<void> Function(ListeningInboxItem item, String resolution)
  onProcessListeningInboxItem;
  final VoidCallback? onStartColdStart;
  final VoidCallback? onRecordCurrentSource;

  /// Explicit reading mark for the selected word; non-null only while the
  /// reading posture is open (Phase 3.13 Slice 5).
  final void Function(bool understood)? onReadingMark;

  /// How the transcript presents itself — read-through, blind, or word-select.
  final WorkbenchStudyMode studyMode;

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

  /// The secondary-track line for [cue]. The two tracks carry independent
  /// offsets, so both are applied before the overlap is taken.
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

  /// Opens or closes the floating analysis window. The window itself fetches
  /// the diagnosis when its voice layer is opened, so opening it need only flip
  /// the flag [SentenceAnalysisWindow] reads.
  void _toggleAnalysis() =>
      learningController.setDiagnosisExpanded(!learningController.diagnosisExpanded);

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
    studyMode: widget.studyMode,
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
    translationMode: settingsController.transcriptTranslation,
    hasTranslationTrack: subtitleController.secondaryTrack != null,
    translationFor: _translationFor,
    onImportTranslation: playerController.mediaId == null
        ? null
        : () => unawaited(mediaSession.openSubtitle(secondary: true)),
    onToggleAnalysis: subtitleController.currentPrimaryCue == null
        ? null
        : _toggleAnalysis,
    analysisExpanded: learningController.diagnosisExpanded,
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
            onOpenListeningDictionary: widget.onOpenListeningDictionary == null
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
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
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
