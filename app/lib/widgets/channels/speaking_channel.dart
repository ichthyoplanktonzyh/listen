import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/reading_task_controller.dart';
import '../../controllers/realtime_conversation_controller.dart';
import '../../controllers/speaking_actions_coordinator.dart';
import '../../controllers/speaking_channel_coordinator.dart';
import '../../controllers/speaking_task_controller.dart';
import '../../localization.dart';
import '../../services/api_service.dart';
import '../flows/reading_flows.dart';
import '../flows/speaking_flows.dart';
import '../panels/listening_check_panel.dart';
import '../panels/realtime_conversation_panel.dart';
import '../panels/speaking_task_studio.dart';

/// The speaking channel's immersive surface: the realtime conversation panel,
/// the L1 comprehension check, or the speaking studio, in that precedence.
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
    required this.realtimeConversationController,
  });

  final LocalApi api;
  final SpeakingChannelCoordinator speakingChannel;
  final SpeakingActionsCoordinator speakingActions;
  final SpeakingTaskController speakingTaskController;
  final ReadingTaskController readingTaskController;
  final RealtimeConversationController realtimeConversationController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([speakingChannel, speakingTaskController]),
    builder: (context, _) => _surface(context),
  );

  Widget _surface(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (speakingChannel.realtimeConversationOpen) {
      return RealtimeConversationPanel(
        controller: realtimeConversationController,
        api: api,
        source: speakingTaskController.state.source!,
        modelId: speakingTaskController.state.asrModelId!,
        acquireAudioFocus: speakingActions.acquireRecordingFocus,
        onClose: () => unawaited(speakingChannel.closeRealtimeConversation()),
      );
    }
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
      onShowRetelling: () => speakingActions.showRetelling(
        api,
        fixedRubricPoints: listeningRetellTemplate(l),
      ),
      onShowRoleReply: (assistance) => speakingActions.showRoleReply(
        api,
        assistance: assistance,
        fixedRubricPoints: roleReplyTemplate(l),
      ),
      onOpenL1Check: speakingChannel.openL1Check,
      onOpenRealtimeConversation: speakingChannel.openRealtimeConversation,
      targetCandidates: speakingChannel.targetCandidates(),
      onClose: speakingChannel.closeSurface,
    );
  }
}
