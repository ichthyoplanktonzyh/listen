import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/task_status.dart';
import '../../models/timeline.dart';
import '../../phonetic_analysis_ui.dart';
import '../../screens/subtitle_resources_screen.dart';
import '../../services/api_service.dart';
import '../../transcription_ui.dart';
import '../panels/cold_start_marking_sheet.dart';

/// Dialog-driven subtitle-resource flows extracted from the composition root:
/// delete/export confirmation, subtitle generation, transcription and
/// phonetic-analysis centers, the resources screen, and cold-start marking.
/// Parameter names mirror the host's controller fields.

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
  required LocalApi? api,
  required PlayerController playerController,
  required ResourceActionsCoordinator resourceActions,
  required SubtitleTrack track,
}) async {
  final l = AppLocalizations.of(context);
  if (api == null) {
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
  required LocalApi? api,
  required PlayerController playerController,
  required SettingsController settingsController,
  required bool secondary,
  required void Function(UserTaskStatus value) recordTaskStatus,
}) async {
  final l = AppLocalizations.of(context);
  if (api == null || playerController.mediaId == null) {
    playerController.setStatus(l.text('statusOpenMediaAndCoreFirst'));
    return;
  }
  final created = await showGenerateSubtitles(
    context: context,
    api: api,
    mediaId: playerController.mediaId!,
    secondary: secondary,
    preferredQuality: settingsController.transcriptionQuality,
    preferredLanguage: settingsController.transcriptionLanguage,
  );
  if (created && context.mounted) {
    playerController.setStatus(
      secondary
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
  required LocalApi? api,
  required PlayerController playerController,
  required LoadGeneratedTrack loadTrack,
}) async {
  if (api == null) {
    // Unavailable State (CONTEXT.md): the transcription center is a user menu
    // entry; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TranscriptionCenter(api: api, loadTrack: loadTrack),
    ),
  );
}

Future<void> openPhoneticAnalysisCenterFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
}) async {
  if (api == null) {
    // Unavailable State (CONTEXT.md): the analysis center is a user menu
    // entry; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => PhoneticAnalysisCenter(api: api)),
  );
}

void openColdStartMarkingFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required ResourceActionsCoordinator resourceActions,
}) {
  final l = AppLocalizations.of(context);
  final service = api;
  final trackId = subtitleController.primaryTrack?.id;
  final language = subtitleController.primaryTrack?.language;
  // Unavailable State (CONTEXT.md): the cold-start button renders whenever
  // the content-fit card does, so each missing prerequisite names its own
  // recovery action instead of leaving a dead button.
  if (service == null) {
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
  showDialog<void>(
    context: context,
    builder: (_) => ColdStartMarkingSheet(
      api: service,
      trackId: trackId,
      language: language,
      onDone: () => resourceActions.loadContentFit(trackId),
    ),
  );
}

Future<void> openSubtitleResourcesFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required LearningController learningController,
  required ResourceActionsCoordinator resourceActions,
  required MediaSessionCoordinator mediaSession,
  required Future<void> Function() onManualReviewTimeline,
}) async {
  if (api == null) {
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
          api: api,
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
          api: api,
          playerController: playerController,
          subtitleController: subtitleController,
          resourceActions: resourceActions,
        ),
      ),
    ),
  );
}
