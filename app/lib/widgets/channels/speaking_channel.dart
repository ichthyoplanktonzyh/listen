import 'package:flutter/material.dart';

import '../../controllers/reading_task_controller.dart';
import '../../controllers/speaking_actions_coordinator.dart';
import '../../controllers/speaking_channel_coordinator.dart';
import '../../controllers/speaking_task_controller.dart';
import '../../services/api_service.dart';
import '../panels/listening_check_panel.dart';
import '../panels/speaking_task_studio.dart';

/// The speaking channel's immersive surface: the L1 comprehension check or
/// the speaking studio.
/// Extracted from the composition root; the order and every callback are
/// unchanged. The localized rubric templates are resolved here, so the
/// speaking channel owns its own text.
class SpeakingChannelHost extends StatelessWidget {
  const SpeakingChannelHost({
    super.key,
    required this.api,
    required this.speakingChannel,
    required this.speakingActions,
    required this.speakingTaskController,
    required this.readingTaskController,
  });

  final LocalApi api;
  final SpeakingChannelCoordinator speakingChannel;
  final SpeakingActionsCoordinator speakingActions;
  final SpeakingTaskController speakingTaskController;
  final ReadingTaskController readingTaskController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([speakingChannel, speakingTaskController]),
    builder: (context, _) => _surface(context),
  );

  Widget _surface(BuildContext context) {
    if (speakingChannel.l1CheckSource != null) {
      return ListeningCheckPanel(
        controller: readingTaskController,
        api: api,
        audioPlayCount: () => speakingChannel.l1PlayCount,
        onPlaySegment: speakingChannel.playL1Segment,
        onClose: speakingChannel.closeL1Check,
      );
    }
    return SpeakingTaskStudio(
      controller: speakingTaskController,
      api: api,
      onPlaySource: speakingActions.playSource,
      onPlayRecording: speakingActions.playRecording,
      onAcquireRecordingFocus: speakingActions.acquireRecordingFocus,
      onOpenL1Check: speakingChannel.openL1Check,
      targetCandidates: speakingChannel.targetCandidates(),
      onClose: speakingChannel.closeSurface,
    );
  }
}
