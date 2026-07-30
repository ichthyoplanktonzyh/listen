import 'package:flutter/material.dart';

import '../../controllers/manual_review_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../../player_adapter.dart';
import '../../services/api_service.dart';
import '../panels/manual_timeline_review_dialog.dart';

/// Opens the sentence-level manual word-timing review dialog for the active
/// WordTimeline and saves the user-adjusted revision. Extracted from the
/// composition root. The "status pristine" flag (whether the review status
/// text has not been superseded by a save result) lives entirely within one
/// flow invocation, so it is a local here rather than host state.
Future<void> openManualReviewFlow({
  required BuildContext context,
  required LocalApi? api,
  required DesktopPlayerAdapter adapter,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required ResourceActionsCoordinator resourceActions,
  required MediaSessionCoordinator mediaSession,
}) async {
  final l = AppLocalizations.of(context);
  final service = api;
  final track = subtitleController.primaryTrack;
  // Unavailable State (CONTEXT.md): manual review is a user row action; each
  // missing prerequisite names its own recovery action.
  if (service == null) {
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  if (track == null) {
    playerController.setStatus(l.text('statusActivateSubtitleFirst'));
    return;
  }
  var statusPristine = false;

  Future<void> playRange(Duration start, Duration end) async {
    if (end <= start) return;
    playerController.setSourceLoop(start, end, label: 'loopReview');
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> saveDraft(ManualReviewDraft draft) async {
    final trackId = subtitleController.primaryTrack?.id;
    if (trackId == null) {
      // A silent return here would let the dialog pop as if the save
      // succeeded; throwing surfaces the refusal in the dialog's error line
      // (the same path validation errors take).
      throw StateError(l.text('statusManualReviewTrackChanged'));
    }
    final errors = draft.validateAll();
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    playerController.setStatus(l.text('statusManualReviewSaving'));
    statusPristine = false;
    await service.createTrackWordTimeline(trackId, draft.createPayload());
    if (!context.mounted) return;
    // Reload enhancements only while the reviewed track is still current;
    // the save itself succeeded either way, so the confirmation still shows.
    if (subtitleController.primaryTrack?.id == trackId) {
      await mediaSession.loadSpeechEnhancements(trackId);
    }
    if (context.mounted) {
      playerController.setStatus(l.text('statusManualReviewSaved'));
    }
  }

  try {
    playerController.setStatus(l.text('statusManualReviewLoading'));
    statusPristine = true;
    await resourceActions.loadTimelineResource(track.id);
    final active = subtitleController.wordTimelineSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    final activeTimelineId =
        active?.id ??
        subtitleController.llTimelineDocument?.activeWordTimelineId;
    if (activeTimelineId == null) {
      if (context.mounted) {
        playerController.setStatus(l.text('statusManualReviewNoTimeline'));
      }
      return;
    }
    final timeline = await service.wordTimeline(activeTimelineId);
    final initialCue = _initialCue(subtitleController, track, timeline);
    if (initialCue == null) {
      if (context.mounted) {
        playerController.setStatus(l.text('statusManualReviewNoWords'));
      }
      return;
    }
    final draft = ManualReviewDraft(
      track: track,
      sourceTimeline: timeline,
      words: timeline.words,
      initialCue: initialCue,
    );
    if (!context.mounted) return;
    final previousLoopStart = playerController.sourceLoopStart;
    final previousLoopEnd = playerController.sourceLoopEnd;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => ManualTimelineReviewDialog(
          draft: draft,
          onPlayRange: playRange,
          onSave: saveDraft,
        ),
      );
    } finally {
      playerController.setSourceLoop(previousLoopStart, previousLoopEnd);
    }
    if (context.mounted && statusPristine) {
      playerController.setStatus(l.text('statusManualReviewClosed'));
    }
  } catch (error) {
    if (context.mounted) {
      playerController.setStatus(
        l.text('statusManualReviewFailed'),
        error: true,
        failure: describeApiFailure(error),
      );
    }
  }
}

Cue? _initialCue(
  SubtitleController subtitleController,
  SubtitleTrack track,
  WordTimeline timeline,
) {
  final sentenceIds = timeline.words.map((word) => word.sentenceId).toSet();
  final current = subtitleController.currentPrimaryCue;
  if (current != null && sentenceIds.contains(current.id)) return current;
  for (final cue in track.cues) {
    if (sentenceIds.contains(cue.id)) return cue;
  }
  return null;
}
