import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/cold_start_marking_view_model.dart';
import '../../controllers/phonetic_analysis_view_model.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/subtitle_controller.dart';
import '../../controllers/transcription_view_models.dart';
import '../../localization.dart';
import '../../models/task_status.dart';
import '../../models/timeline.dart';
import '../../models/runtime_resources.dart';
import '../../phonetic_analysis_ui.dart';
import '../../screens/subtitle_resources_screen.dart';
import '../../transcription_ui.dart';
import '../panels/cold_start_marking_sheet.dart';

/// Dialog-driven subtitle-resource flows extracted from the composition root:
/// delete/export confirmation, subtitle generation, transcription and
/// phonetic-analysis centers, the resources screen, and cold-start marking.
/// Parameter names mirror the host's controller fields.

typedef ColdStartMarkingViewModelFactory =
    ColdStartMarkingViewModel Function({
      required String trackId,
      required String language,
    });
typedef RegenerateSubtitlesViewModelFactory =
    GenerateSubtitlesViewModel Function(TranscriptionJobView job);

class _OwnedNotifierRoute extends StatefulWidget {
  const _OwnedNotifierRoute({required this.notifier, required this.child});

  final ChangeNotifier notifier;
  final Widget child;

  @override
  State<_OwnedNotifierRoute> createState() => _OwnedNotifierRouteState();
}

class _OwnedNotifierRouteState extends State<_OwnedNotifierRoute> {
  @override
  void dispose() {
    widget.notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> deleteSubtitleResourceFlow({
  required BuildContext context,
  required ResourceActionsCoordinator resourceActions,
  required SubtitleTrack track,
}) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.text('deleteResource')),
      content: Text(l.text('deleteSubtitleResourceBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.text('deleteResource')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await resourceActions.deleteSubtitleResource(track);
}

Future<void> exportSubtitleResourceFlow({
  required BuildContext context,
  required PlayerController playerController,
  required ResourceActionsCoordinator resourceActions,
  required SubtitleTrack track,
}) async {
  final l = AppLocalizations.of(context);
  if (!resourceActions.repository.isAvailable) {
    // Unavailable State (CONTEXT.md): exporting is a user row action; report
    // the missing core instead of swallowing the click.
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  final format = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l.text('exportSubtitleFormat')),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'srt'),
          child: ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: Text(l.text('exportSrt')),
            subtitle: const Text('.srt'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'lltimeline'),
          child: ListTile(
            leading: const Icon(Icons.timeline),
            title: Text(l.text('exportLLTimelineJson')),
            subtitle: const Text('.lltimeline.json'),
          ),
        ),
      ],
    ),
  );
  // Legitimate silence: the user dismissed the format chooser themselves.
  if (format == null) return;
  if (format == 'lltimeline') {
    await resourceActions.exportLLTimelineResource(track);
  } else {
    await resourceActions.exportSubtitleSrt(track);
  }
}

Future<void> generateSubtitlesFlow({
  required BuildContext context,
  required GenerateSubtitlesViewModel? viewModel,
  required PlayerController playerController,
  required void Function(UserTaskStatus value) recordTaskStatus,
}) async {
  final l = AppLocalizations.of(context);
  if (viewModel == null || playerController.mediaId == null) {
    viewModel?.dispose();
    playerController.setStatus(l.text('statusOpenMediaAndCoreFirst'));
    return;
  }
  bool created;
  try {
    created = await showGenerateSubtitles(
      context: context,
      viewModel: viewModel,
    );
  } finally {
    viewModel.dispose();
  }
  if (created && context.mounted) {
    playerController.setStatus(
      viewModel.secondary
          ? l.text('secondarySubtitleGenerationStarted')
          : l.text('primarySubtitleGenerationStarted'),
    );
    recordTaskStatus(
      UserTaskStatus(
        kind: UserTaskKind.subtitleGeneration,
        state: UserTaskState.working,
        rawStatus: 'queued',
        progress: 0,
        targetId: playerController.mediaId,
      ),
    );
  }
}

Future<void> openTranscriptionCenterFlow({
  required BuildContext context,
  required TranscriptionCenterViewModel? viewModel,
  required RegenerateSubtitlesViewModelFactory createRegenerateViewModel,
  required PlayerController playerController,
}) async {
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): the transcription center is a user menu
    // entry; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) {
        Future<void> regenerate(TranscriptionJobView job) async {
          final regenerateViewModel = createRegenerateViewModel(job);
          bool created;
          try {
            created = await showGenerateSubtitles(
              context: routeContext,
              viewModel: regenerateViewModel,
            );
          } finally {
            regenerateViewModel.dispose();
          }
          if (created) await viewModel.refresh();
        }

        return _OwnedNotifierRoute(
          notifier: viewModel,
          child: TranscriptionCenter(
            viewModel: viewModel,
            onRegenerate: regenerate,
          ),
        );
      },
    ),
  );
}

Future<void> openPhoneticAnalysisCenterFlow({
  required BuildContext context,
  required PhoneticAnalysisViewModel? viewModel,
  required PlayerController playerController,
}) async {
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): the analysis center is a user menu
    // entry; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _OwnedNotifierRoute(
        notifier: viewModel,
        child: PhoneticAnalysisCenter(viewModel: viewModel),
      ),
    ),
  );
}

void openColdStartMarkingFlow({
  required BuildContext context,
  required ColdStartMarkingViewModelFactory? createViewModel,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required ResourceActionsCoordinator resourceActions,
}) {
  final l = AppLocalizations.of(context);
  final trackId = subtitleController.primaryTrack?.id;
  final language = subtitleController.primaryTrack?.language;
  // Unavailable State (CONTEXT.md): the cold-start button renders whenever
  // the content-fit card does, so each missing prerequisite names its own
  // recovery action instead of leaving a dead button.
  if (createViewModel == null) {
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  if (trackId == null) {
    playerController.setStatus(l.text('statusActivateSubtitleFirst'));
    return;
  }
  if (language == null) {
    playerController.setStatus(l.text('statusSetSubtitleLanguageFirst'));
    return;
  }
  final viewModel = createViewModel(trackId: trackId, language: language);
  showDialog<void>(
    context: context,
    builder: (_) => ColdStartMarkingSheet(
      viewModel: viewModel,
      onDone: () => resourceActions.loadContentFit(trackId),
    ),
  ).whenComplete(viewModel.dispose);
}

Future<void> openSubtitleResourcesFlow({
  required BuildContext context,
  required bool backendAvailable,
  required ColdStartMarkingViewModelFactory? createColdStartViewModel,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required LearningController learningController,
  required ResourceActionsCoordinator resourceActions,
  required MediaSessionCoordinator mediaSession,
  required Future<void> Function() onManualReviewTimeline,
}) async {
  if (!backendAvailable) {
    // Unavailable State (CONTEXT.md): the resources screen is a user
    // destination; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await resourceActions.loadSubtitleResources(updateStatus: false);
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SubtitleResourcesScreen(
        playerController: playerController,
        subtitleController: subtitleController,
        onImportSubtitle: () => mediaSession.openSubtitle(secondary: false),
        onImportLLTimeline: mediaSession.openLLTimelineResource,
        onRefreshResources: resourceActions.refreshSubtitleResources,
        onActivateSubtitle: resourceActions.activateSubtitleResource,
        onArchiveSubtitle: resourceActions.archiveSubtitleResource,
        onRestoreSubtitle: resourceActions.restoreSubtitleResource,
        onDeleteSubtitle: (track) => deleteSubtitleResourceFlow(
          context: context,
          resourceActions: resourceActions,
          track: track,
        ),
        onExportSubtitle: (track) => exportSubtitleResourceFlow(
          context: context,
          playerController: playerController,
          resourceActions: resourceActions,
          track: track,
        ),
        onLanguageChanged: resourceActions.changeTrackLanguage,
        availableLanguages: learningController.availableLanguages,
        onExportLLTimeline: resourceActions.exportLLTimelineResource,
        onActivateWordTimeline: resourceActions.activateWordTimeline,
        onManualReviewTimeline: onManualReviewTimeline,
        onActivatePhoneTimeline: resourceActions.activatePhoneTimeline,
        onArchivePhoneTimeline: resourceActions.archivePhoneTimeline,
        onDeletePhoneTimeline: resourceActions.deletePhoneTimeline,
        onGenerateChunkTimeline: resourceActions.generateChunkTimeline,
        onActivateChunkTimeline: resourceActions.activateChunkTimeline,
        onArchiveChunkTimeline: resourceActions.archiveChunkTimeline,
        onDeleteChunkTimeline: resourceActions.deleteChunkTimeline,
        onStartColdStart: () => openColdStartMarkingFlow(
          context: context,
          createViewModel: createColdStartViewModel,
          playerController: playerController,
          subtitleController: subtitleController,
          resourceActions: resourceActions,
        ),
      ),
    ),
  );
}
