import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/practice_file_service.dart';
import 'learning_controller.dart';
import 'playback_actions_coordinator.dart';
import 'player_controller.dart';
import 'practice_controller.dart';
import 'settings_controller.dart';
import 'slice_player_controller.dart';
import 'subtitle_controller.dart';

/// Owns the intensive-practice and shadowing actions: starting the four
/// practice modes, looping the practice window, submitting attempts, the
/// shadowing record/playback/ABA flow, rate/step control, external and
/// slice-window shadowing, review capture, sentence navigation and teardown.
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
    required this.slicePlayer,
    required this.playbackActions,
    required this.settings,
    required this.adapter,
    required this.recordingAdapter,
    this.fileService = const LocalPracticeFileService(),
    this.stopAuxiliaryAudio,
  });

  final PracticeController practice;
  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final SlicePlayerController slicePlayer;
  final PlaybackActionsCoordinator playbackActions;
  final SettingsController settings;
  final DesktopPlayerAdapter adapter;
  final DesktopPlayerAdapter recordingAdapter;
  final PracticeFileService fileService;
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

  Future<void> startShadowingPractice() async {
    await practice.startShadowing(
      cue: subtitle.currentPrimaryCue,
      chunk: playbackActions.currentPracticeChunk(),
      chunks: playbackActions.currentPracticeChunks(),
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
      mediaTimeMs: playbackActions.mediaTimeMs,
    );
    if (practice.item != null) {
      await adapter.setRate(practice.state.shadowingRate);
      await replayPracticeWindow();
    }
  }

  Future<void> replayPracticeWindow() async {
    final draft = practice.draft;
    if (draft == null) return;
    await stopAuxiliaryAudio?.call();
    if (draft.referenceMediaPath != null) {
      await adapter.pause();
      await slicePlayer.open(
        path: draft.referenceMediaPath!,
        occurrence: {
          'start_ms_snapshot': draft.playbackStartMs,
          'end_ms_snapshot': draft.playbackEndMs,
          'sentence_text_snapshot': draft.expectedText,
          'media_title_snapshot': fileService.basename(
            draft.referenceMediaPath!,
          ),
          'original_form': draft.focusLabel,
        },
      );
      await slicePlayer.setRate(practice.state.shadowingRate);
      slicePlayer.setLooping(true);
      return;
    }
    await slicePlayer.pause();
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

  Future<void> beginShadowingRecording() async {
    await practice.beginShadowingRecording(
      acquireAudioFocus: () async {
        await stopAuxiliaryAudio?.call();
        await adapter.pause();
        await recordingAdapter.pause();
        await slicePlayer.pause();
      },
    );
  }

  Future<void> stopShadowingRecording() async {
    final path = practice.draft?.referenceMediaPath ?? player.mediaPath;
    final draft = practice.draft;
    if (path == null || draft == null) return;
    await practice.stopShadowingRecording(
      language: settings.resolveLearningLanguage(
        subtitle.primaryTrack?.language,
      ),
      mediaId: draft.sourceMediaId ?? player.mediaId,
      extractReferenceWav: () => fileService.extractReferenceWav(
        path,
        startMs: draft.playbackStartMs,
        endMs: draft.playbackEndMs,
        ffmpegPath: settings.ffmpegPath,
        ffprobePath: settings.ffprobePath,
        ytDlpPath: settings.ytDlpPath,
      ),
    );
  }

  Future<void> playShadowingReferenceOnce() async {
    final draft = practice.draft;
    if (draft == null) return;
    await stopAuxiliaryAudio?.call();
    await recordingAdapter.pause();
    if (draft.referenceMediaPath != null) {
      slicePlayer.setLooping(false);
      await slicePlayer.replay();
      final durationMs =
          ((draft.playbackEndMs - draft.playbackStartMs) /
                  practice.state.shadowingRate)
              .ceil();
      await Future<void>.delayed(Duration(milliseconds: durationMs + 80));
      await slicePlayer.pause();
      slicePlayer.setLooping(true);
      return;
    }
    player.setSourceLoop(null, null);
    await adapter.pause();
    await adapter.setRate(practice.state.shadowingRate);
    await adapter.seek(Duration(milliseconds: draft.playbackStartMs));
    await adapter.play();
    final durationMs =
        ((draft.playbackEndMs - draft.playbackStartMs) /
                practice.state.shadowingRate)
            .ceil();
    await Future<void>.delayed(Duration(milliseconds: durationMs + 80));
    await adapter.pause();
  }

  Future<void> playShadowingRecording() async {
    final asset = practice.recordingAsset;
    if (asset == null) return;
    await stopAuxiliaryAudio?.call();
    await adapter.pause();
    await slicePlayer.pause();
    await recordingAdapter.open(asset.filePath);
    await Future<void>.delayed(Duration(milliseconds: asset.durationMs + 80));
    await recordingAdapter.pause();
  }

  Future<void> playShadowingAba() async {
    if (practice.recordingAsset == null) return;
    await playShadowingReferenceOnce();
    await playShadowingRecording();
    await playShadowingReferenceOnce();
  }

  Future<void> setShadowingRate(double rate) async {
    practice.setShadowingRate(rate);
    if (practice.draft?.referenceMediaPath != null) {
      await slicePlayer.setRate(rate);
    } else {
      await adapter.setRate(rate);
    }
    if (player.sourceLoopLabel == 'loopPractice') {
      await replayPracticeWindow();
    }
  }

  Future<void> setShadowingStep(int index) async {
    await practice.selectShadowingStep(
      index: index,
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
    );
    if (practice.item != null) await replayPracticeWindow();
  }

  Future<void> togglePracticePlayback() async {
    if (practice.draft?.referenceMediaPath != null) {
      await slicePlayer.togglePlayback();
      return;
    }
    await adapter.playOrPause();
  }

  Future<void> startExternalShadowing(
    String path,
    Map<String, dynamic> occurrence,
  ) async {
    final startMs = occurrence['start_ms_snapshot'];
    final endMs = occurrence['end_ms_snapshot'];
    final prompt = occurrence['sentence_text_snapshot'];
    if (startMs is! int || endMs is! int || prompt is! String) return;
    await practice.startExternalShadowing(
      mediaPath: path,
      mediaId: occurrence['media_id'] as String?,
      trackId: occurrence['track_id'] as String?,
      sentenceId: occurrence['sentence_id'] as String?,
      promptText: prompt,
      startMs: startMs,
      endMs: endMs,
    );
    if (practice.item != null) await replayPracticeWindow();
  }

  Future<void> startSliceWindowShadowing(SlicePlayerState state) async {
    final path = state.path;
    final sentence = state.sentence;
    if (path == null || sentence == null) return;
    await startExternalShadowing(path, {
      'media_id': state.mediaId,
      'track_id': state.trackId,
      'sentence_id': state.sentenceId,
      'sentence_text_snapshot': sentence,
      'start_ms_snapshot': state.start.inMilliseconds,
      'end_ms_snapshot': state.end.inMilliseconds,
    });
  }

  Future<void> savePracticeReview() async {
    await practice.saveCurrentFailureToReview();
    if (practice.attempt?.generatedReviewItemIds.isNotEmpty == true &&
        isMounted()) {
      player.setStatus(_t('statusPracticeFailureSaved'));
    }
  }

  Future<void> navigatePracticeSentence(int delta) async {
    // Review/dictionary shadowing owns one resolved source clip. It must never
    // navigate the primary subtitle cursor, whether invoked by the UI or a
    // global arrow shortcut.
    if (practice.draft?.referenceMediaPath != null) return;
    final current = subtitle.currentPrimaryCue;
    final target = delta < 0
        ? subtitle.primaryCursor.previous(current)
        : subtitle.primaryCursor.next(current);
    if (target == null) return;
    final draft = practice.draft;
    await seekCue(target);
    if (draft == null) return;
    if (draft.kind == 'shadowing') {
      await startShadowingPractice();
    } else if (draft.kind == 'cloze') {
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
    await recordingAdapter.pause();
    if (practice.recordingActive) {
      await practice.cancelShadowingRecording();
    }
    if (practice.draft?.referenceMediaPath != null) {
      await slicePlayer.close();
    }
    await adapter.setRate(player.rate);
    practice.clear();
  }
}
