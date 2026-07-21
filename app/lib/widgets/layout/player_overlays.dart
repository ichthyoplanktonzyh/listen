import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/hunting_actions_coordinator.dart';
import '../../controllers/hunting_session_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/practice_actions_coordinator.dart';
import '../../controllers/practice_controller.dart';
import '../../controllers/slice_player_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../services/api_service.dart';
import '../panels/hunting_prompt_card.dart';
import '../panels/intensive_practice_window.dart';
import '../panels/slice_playback_window.dart';

/// The windows that float over whatever content channel is on the stage:
/// the intensive-practice window, the hunting prompt, and the slice player.
/// Extracted from the composition root; they are independent of the channel
/// machinery, so they subscribe to their own controllers here rather than
/// riding the root's aggregate notification.
///
/// Returns a [Positioned.fill] wrapping its own [Stack] so it stays a direct
/// child of the workbench Stack and spans exactly the same box. Both windows
/// return a [Positioned] whose parent data is only valid against an immediate
/// Stack parent (see [IntensivePracticeWindow.build]), and a Stack holding
/// nothing but positioned children collapses under the loose constraints a
/// Stack gives its non-positioned children — filling is what preserves the
/// pre-extraction geometry.
class PlayerOverlays extends StatelessWidget {
  const PlayerOverlays({
    super.key,
    required this.api,
    required this.practiceController,
    required this.slicePlayerController,
    required this.huntingSessionController,
    required this.subtitleController,
    required this.playerController,
    required this.practiceActions,
    required this.huntingActions,
    required this.onCloseSlicePlayback,
  });

  final LocalApi? api;
  final PracticeController practiceController;
  final SlicePlayerController slicePlayerController;
  final HuntingSessionController huntingSessionController;
  final SubtitleController subtitleController;
  final PlayerController playerController;
  final PracticeActionsCoordinator practiceActions;
  final HuntingActionsCoordinator huntingActions;
  final Future<void> Function() onCloseSlicePlayback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      practiceController,
      slicePlayerController,
      subtitleController,
      playerController,
    ]),
    builder: (context, _) => Positioned.fill(
      child: Stack(
        children: [
          // Keep the window mounted while a neighbouring sentence's item is
          // still being created (draft is set synchronously; item is null in
          // flight), so sentence navigation never unmounts the panel.
          if (practiceController.item != null ||
              practiceController.draft != null)
            _practiceWindow(),
          Positioned(
            top: 18,
            left: 24,
            right: 24,
            child: Center(
              child: HuntingPromptCard(
                controller: huntingSessionController,
                onAnswer: (answer) =>
                    unawaited(huntingActions.answerHuntingCheck(answer)),
                onReindex: () =>
                    unawaited(huntingActions.reindexHuntingCorpus()),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: slicePlayerController.store,
            builder: (context, _) => slicePlayerController.state.open
                ? SlicePlaybackWindow(
                    controller: slicePlayerController,
                    onClose: onCloseSlicePlayback,
                    onShadowing: practiceActions.startSliceWindowShadowing,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );

  Widget _practiceWindow() => IntensivePracticeWindow(
    controller: practiceController,
    currentSentence: (subtitleController.currentPrimaryCue?.index ?? 0) + 1,
    totalSentences: subtitleController.primaryTrack?.cues.length ?? 0,
    canGoPrevious:
        subtitleController.primaryCursor.previous(
          subtitleController.currentPrimaryCue,
        ) !=
        null,
    canGoNext:
        subtitleController.primaryCursor.next(
          subtitleController.currentPrimaryCue,
        ) !=
        null,
    showSentenceNavigation:
        practiceController.draft?.referenceMediaPath == null,
    isPlaying: practiceController.draft?.referenceMediaPath != null
        ? slicePlayerController.state.playing
        : playerController.playing,
    onReplay: practiceActions.replayPracticeWindow,
    onTogglePlayback: practiceActions.togglePracticePlayback,
    onNavigate: practiceActions.navigatePracticeSentence,
    onSubmit: practiceActions.submitPractice,
    onSaveReview: practiceActions.savePracticeReview,
    onStartRecording: practiceActions.beginShadowingRecording,
    onStopRecording: practiceActions.stopShadowingRecording,
    onCancelRecording: practiceController.cancelShadowingRecording,
    onOpenMicrophoneSettings: practiceController.openMicrophoneSettings,
    onPlayReference: practiceActions.playShadowingReferenceOnce,
    onPlayRecording: practiceActions.playShadowingRecording,
    onPlayAba: practiceActions.playShadowingAba,
    onDeleteRecording: () => practiceController.deleteCurrentRecording(api),
    onShadowingRateChanged: practiceActions.setShadowingRate,
    onShadowingStepChanged: practiceActions.setShadowingStep,
    onClose: practiceActions.closePracticeWindow,
  );
}
