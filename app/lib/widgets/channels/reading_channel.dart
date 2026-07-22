import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/reading_channel_coordinator.dart';
import '../../controllers/reading_controller.dart';
import '../../controllers/reading_diff_controller.dart';
import '../../controllers/reading_task_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../controllers/vocabulary_actions_coordinator.dart';
import '../../localization.dart';
import '../../models/personal_expression.dart';
import '../../services/api_service.dart';
import '../flows/reading_flows.dart';
import '../panels/listening_check_panel.dart';
import '../panels/reading_diff_panel.dart';
import '../panels/reading_task_studio.dart';
import '../panels/reading_view.dart';
import '../panels/reading_word_inspector.dart';

/// The reading channel's immersive surface: whichever of the reader, the
/// paragraph-task studio, the read-listen diff card, or the listening-retell
/// panel [readingChannel] currently has open. Extracted from the composition
/// root; the surface order and every callback are unchanged, so the tree
/// reads identically at both sites.
///
/// The host subscribes to exactly the controllers this subtree reads, which
/// is what lets the composition root's aggregate `Listenable.merge` shed
/// `readingChannel` entirely.
class ReadingChannelHost extends StatelessWidget {
  const ReadingChannelHost({
    super.key,
    required this.api,
    required this.readingChannel,
    required this.readingController,
    required this.readingTaskController,
    required this.readingDiffController,
    required this.learningController,
    required this.settingsController,
    required this.subtitleController,
    required this.playerController,
    required this.vocabularyActions,
    required this.onSaveSentencePattern,
    required this.onOpenSlicePlayback,
    required this.onRecordReadingMark,
    required this.onOpenListeningDictionary,
    required this.onPlayPronunciationAudio,
    required this.onCorrectLemma,
  });

  final LocalApi api;
  final ReadingChannelCoordinator readingChannel;
  final ReadingController readingController;
  final ReadingTaskController readingTaskController;
  final ReadingDiffController readingDiffController;
  final LearningController learningController;
  final SettingsController settingsController;
  final SubtitleController subtitleController;
  final PlayerController playerController;
  final VocabularyActionsCoordinator vocabularyActions;

  /// Hands one reading sentence to the personal-expression flow, which is a
  /// dialog the composition root owns.
  final Future<void> Function(PersonalExpressionSourceView source)
  onSaveSentencePattern;
  final Future<void> Function(Map<String, dynamic> occurrence)
  onOpenSlicePlayback;
  final Future<void> Function(bool understood) onRecordReadingMark;
  final Future<void> Function(String entryId) onOpenListeningDictionary;
  final void Function(String url) onPlayPronunciationAudio;
  final VoidCallback onCorrectLemma;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      readingChannel,
      readingController,
      learningController,
      settingsController,
      subtitleController,
    ]),
    builder: (context, _) => _surface(context),
  );

  Widget _surface(BuildContext context) {
    final l = AppLocalizations.of(context);
    final taskSource = readingChannel.taskStudioSource;
    if (taskSource != null) {
      return ReadingTaskStudio(
        controller: readingTaskController,
        api: api,
        source: taskSource,
        audioPlayCount: () =>
            readingController.slicePlayCount(taskSource.anchorCueId),
        onClose: readingChannel.closeTaskStudio,
      );
    }
    final diffSource = readingChannel.diffSource;
    final diffParagraph = readingChannel.diffParagraph;
    if (diffSource != null && diffParagraph != null) {
      return ReadingDiffPanel(
        controller: readingDiffController,
        onOpenReadingTask: () {
          readingChannel.closeDiff();
          unawaited(
            readingChannel.openTask(
              diffParagraph,
              templatePoints: readingTaskTemplate(l),
            ),
          );
        },
        onOpenListeningCheck: () {
          readingChannel.closeDiff();
          readingChannel.openListeningCheck(
            diffSource,
            fallbackTemplatePoints: listeningRetellTemplate(l),
          );
        },
        onClose: readingChannel.closeDiff,
      );
    }
    if (readingChannel.listeningCheckSource != null) {
      return ListeningCheckPanel(
        controller: readingTaskController,
        api: api,
        audioPlayCount: () => readingChannel.listeningPlayCount,
        onPlaySegment: readingChannel.playListeningCheckSegment,
        onClose: readingChannel.closeListeningCheck,
      );
    }
    final reader = ReadingView(
      controller: readingController,
      wordEntries: learningController.wordEntries,
      capabilityProfiles: learningController.capabilityProfiles,
      showStyles: settingsController.statusStylesVisible,
      onWord: readingChannel.openWord,
      onPlaySentence: (sentence) => readingChannel.playRange(
        sentence.start,
        sentence.end,
        sentence.cues.first.id,
        sentence.text,
      ),
      onPlayParagraph: (paragraph) => readingChannel.playRange(
        paragraph.start,
        paragraph.end,
        paragraph.anchorCueId,
        paragraph.sentences.first.text,
      ),
      onStartTask: (paragraph) => readingChannel.openTask(
        paragraph,
        templatePoints: readingTaskTemplate(l),
      ),
      onSaveSentencePattern: (sentence) => onSaveSentencePattern(
        PersonalExpressionSourceView(
          kind: 'reading',
          text: sentence.text,
          title: playerController.mediaTitle,
          mediaId: playerController.mediaId,
          mediaFingerprint: playerController.mediaFingerprint,
          trackId: subtitleController.primaryTrack?.id,
          sentenceId: sentence.cues.first.id,
          startMs: sentence.start.inMilliseconds,
          endMs: sentence.end.inMilliseconds,
        ),
      ),
      onOpenDiff: readingChannel.openDiff,
      onClose: () => unawaited(readingChannel.close()),
    );
    return ReadingContextLayout(
      reader: reader,
      inspectorOpen: readingChannel.wordInspectorOpen,
      inspector: ReadingWordInspector(
        learningController: learningController,
        onClose: readingChannel.closeWordInspector,
        onStatus: (selected) =>
            unawaited(vocabularyActions.setSelectedWordStatus(selected)),
        onSave: vocabularyActions.saveSelectedLearningContent,
        onSource: (occurrence) => unawaited(onOpenSlicePlayback(occurrence)),
        onHeard: () => unawaited(vocabularyActions.observeSelected(true)),
        onNotHeard: () => unawaited(vocabularyActions.observeSelected(false)),
        onCapabilityOverride: vocabularyActions.setCapabilityOverride,
        onRecordSource: () =>
            unawaited(vocabularyActions.recordCurrentSource()),
        onReadingMark: (understood) =>
            unawaited(onRecordReadingMark(understood)),
        onOpenListeningDictionary: () {
          final entry = learningController.selectedLexicalDetails?.entry;
          if (entry != null) unawaited(onOpenListeningDictionary(entry.id));
        },
        onPlayPronunciationAudio: onPlayPronunciationAudio,
        onCorrectLemma: onCorrectLemma,
        hasSelectedCue: subtitleController.currentPrimaryCue != null,
      ),
    );
  }
}
