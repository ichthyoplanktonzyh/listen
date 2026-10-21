import '../models/timeline.dart';
import '../player_adapter.dart';
import 'learning_controller.dart';
import 'playback_actions_coordinator.dart';
import 'player_controller.dart';
import 'practice_controller.dart';
import 'subtitle_controller.dart';

/// Owns direct listening practice: cloze and dictation, replay, review capture,
/// sentence navigation and teardown.
///
/// Extracted verbatim from `_PlayerScreenState` (main.dart decomposition);
/// context-free, driving everything through the injected controllers/adapters
/// and callbacks so it stays testable in isolation.
class PracticeActionsCoordinator {
  PracticeActionsCoordinator({
    required this.practice,
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.playbackActions,
    required this.adapter,
    this.stopAuxiliaryAudio,
  });

  final PracticeController practice;
  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final PlaybackActionsCoordinator playbackActions;
  final DesktopPlayerAdapter adapter;
  final Future<void> Function()? stopAuxiliaryAudio;

  late bool Function() isMounted;
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;
  late Future<void> Function() refreshDiagnosis;
  late Future<void> Function(Cue? cue) seekCue;

  void bind({
    required bool Function() isMounted,
    String Function(String key)? text,
    required Future<void> Function() refreshDiagnosis,
    required Future<void> Function(Cue? cue) seekCue,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.refreshDiagnosis = refreshDiagnosis;
    this.seekCue = seekCue;
  }

  Future<void> startClozePractice() async {
    final cue = subtitle.currentPrimaryCue;
    await practice.startCloze(
      cue: cue,
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
      wordTimings: cue == null
          ? const []
          : subtitle.timingsBySentence[cue.id] ?? const [],
      wordEntries: learning.wordEntries,
      mediaTimeMs: playbackActions.mediaTimeMs,
    );
    if (practice.item != null) {
      await replayPracticeWindow();
    }
  }

  Future<void> startChunkDictationPractice() async {
    await practice.startChunkDictation(
      cue: subtitle.currentPrimaryCue,
      chunk: playbackActions.currentPracticeChunk(),
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
      mediaTimeMs: playbackActions.mediaTimeMs,
    );
    if (practice.item != null) {
      await replayPracticeWindow();
    }
  }

  Future<void> startSentenceDictationPractice() async {
    await practice.startSentenceDictation(
      cue: subtitle.currentPrimaryCue,
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
      mediaTimeMs: playbackActions.mediaTimeMs,
    );
    if (practice.item != null) {
      await replayPracticeWindow();
    }
  }

  Future<void> replayPracticeWindow() async {
    final draft = practice.draft;
    if (draft == null) return;
    await stopAuxiliaryAudio?.call();
    await playbackActions.loopRange(
      draft.playbackStartMs,
      draft.playbackEndMs,
      'Looping practice window',
      labelKey: 'loopPractice',
    );
  }

  Future<void> submitPractice() async {
    await practice.submit();
    final attempt = practice.attempt;
    if (attempt != null && isMounted()) {
      player.setStatus(
        _t('statusPracticeResult')
            .replaceAll('{result}', attempt.result)
            .replaceAll('{summary}', attempt.evaluation.summary),
      );
    }
    await refreshDiagnosis();
  }

  Future<void> togglePracticePlayback() async {
    await adapter.playOrPause();
  }

  Future<void> savePracticeReview() async {
    await practice.saveCurrentFailureToReview();
    if (practice.attempt?.generatedReviewItemIds.isNotEmpty == true &&
        isMounted()) {
      player.setStatus(_t('statusPracticeFailureSaved'));
    }
  }

  Future<void> navigatePracticeSentence(int delta) async {
    final current = subtitle.currentPrimaryCue;
    final target = delta < 0
        ? subtitle.primaryCursor.previous(current)
        : subtitle.primaryCursor.next(current);
    if (target == null) return;
    final draft = practice.draft;
    await seekCue(target);
    if (draft == null) return;
    if (draft.kind == 'cloze') {
      await startClozePractice();
    } else if (draft.targetKind == 'chunk') {
      await startChunkDictationPractice();
    } else {
      await startSentenceDictationPractice();
    }
  }

  Future<void> closePracticeWindow() async {
    if (player.sourceLoopLabel == 'loopPractice') {
      player.setSourceLoop(null, null);
    }
    await adapter.setRate(player.rate);
    practice.clear();
  }
}
