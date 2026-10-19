import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/writing_channel_coordinator.dart';
import '../../controllers/writing_task_controller.dart';
import '../../localization.dart';
import '../flows/writing_flows.dart';
import '../panels/writing_task_studio.dart';

/// The writing channel's immersive surface. Extracted from the composition
/// root; the studio and every callback are unchanged. The localized prompt and
/// rubric template are resolved here rather than passed down, so the writing
/// channel owns its own text.
class WritingChannelHost extends StatelessWidget {
  const WritingChannelHost({
    super.key,
    required this.writingChannel,
    required this.writingTaskController,
  });

  final WritingChannelCoordinator writingChannel;
  final WritingTaskController writingTaskController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: writingChannel,
    builder: (context, _) => WritingTaskStudio(
      controller: writingTaskController,
      audioPlayCount: () => writingChannel.playCount,
      onKindChanged: (kind) => unawaited(_openKind(context, kind)),
      onPlaySource: writingChannel.playSource,
      onSpeakText: (text) => unawaited(_speakText(context, text)),
      onClose: () => unawaited(writingChannel.close()),
    ),
  );

  Future<void> _speakText(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final unavailable = AppLocalizations.of(context).text('ttsUnavailable');
    if (await writingChannel.speakText(text)) return;
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(unavailable)));
  }

  /// Switching the writing kind re-opens the studio on the same segment with
  /// that kind's localized prompt and rubric template.
  Future<void> _openKind(BuildContext context, String kind) {
    final l = AppLocalizations.of(context);
    return writingChannel.openTask(
      kind,
      promptSnapshot: writingPrompt(l, kind),
      fixedRubricPoints: writingTaskTemplate(l),
    );
  }
}
