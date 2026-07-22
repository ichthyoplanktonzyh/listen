import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/personal_expression.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../widgets/panels/speaking_task_studio.dart'
    show SpeakingTargetCandidate;
import 'learning_controller.dart';
import 'player_controller.dart';
import 'reading_task_controller.dart';
import 'speaking_actions_coordinator.dart';
import 'speaking_task_controller.dart';

/// Owns the speaking channel's page state: which surface sits on top of the
/// speaking session (studio or L1 comprehension check)
/// and which personal-expression pattern the session was launched from.
/// Extracted from the composition root; getter names mirror the host's former
/// field names.
///
/// Session and audio-focus rules stay in [SpeakingActionsCoordinator]; this
/// coordinator sits one level up and only sequences surfaces and the
/// end-of-session handoff.
class SpeakingChannelCoordinator extends ChangeNotifier {
  SpeakingChannelCoordinator({
    required this.actions,
    required this.task,
    required this.readingTask,
    required this.learning,
    required this.player,
  });

  final SpeakingActionsCoordinator actions;
  final SpeakingTaskController task;
  final ReadingTaskController readingTask;
  final LearningController learning;
  final PlayerController player;

  /// Localization seam; falls back to raw keys when unbound (tests).
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;

  LocalApi? Function()? _getApi;
  bool Function()? _isMounted;
  Future<String?> Function()? _askPersonalExpressionAssessment;
  void Function()? _onReturnToReview;
  void Function()? _onReturnToPersonalExpression;

  /// Host seams. [askPersonalExpressionAssessment] and the two return hooks
  /// are dialogs/flows the composition root owns; the coordinator only
  /// decides when they are due.
  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required Future<String?> Function() askPersonalExpressionAssessment,
    required void Function() onReturnToReview,
    required void Function() onReturnToPersonalExpression,
  }) {
    _getApi = getApi;
    _isMounted = isMounted;
    _askPersonalExpressionAssessment = askPersonalExpressionAssessment;
    _onReturnToReview = onReturnToReview;
    _onReturnToPersonalExpression = onReturnToPersonalExpression;
  }

  ReadingTaskSource? _l1CheckSource;
  int _l1PlayCount = 0;

  /// Which personal-expression pattern this speaking session serves, so
  /// closing the surface can file the 3.17 handoff attempt. Assigned by the
  /// launch flow; never drives the build, so it does not notify.
  SentencePatternAssetView? activePersonalPattern;

  ReadingTaskSource? get l1CheckSource => _l1CheckSource;
  int get l1PlayCount => _l1PlayCount;
  bool get isOpen => actions.isOpen;

  bool get _mounted => _isMounted?.call() ?? true;

  /// Swaps the studio for the L1 comprehension check over the same segment.
  /// The speaking rubric's points are the check's template, so both sides
  /// interrogate the same content.
  Future<void> openL1Check() async {
    final service = _getApi?.call();
    final speakingSource = actions.source;
    final rubric = task.state.rubric;
    if (service == null || speakingSource == null || rubric == null) return;
    final profile = await service.learnerProfile();
    final l1 = profile.l1Language;
    if (l1 == null || l1.trim().isEmpty) {
      player.setStatus(_t('statusSetL1First'));
      return;
    }
    final source = ReadingTaskSource(
      anchorCueId: speakingSource.anchorCueId,
      mediaId: speakingSource.mediaId,
      trackId: speakingSource.trackId,
      startMs: speakingSource.startMs,
      endMs: speakingSource.endMs,
      sourceLanguage: speakingSource.language,
      responseLanguage: l1,
      transcriptSnapshot: speakingSource.transcriptSnapshot,
    );
    _l1PlayCount = 0;
    _l1CheckSource = source;
    notifyListeners();
    await readingTask.openTask(
      service,
      source: source,
      templatePoints: rubric.points,
      purpose: ReadingTaskController.listeningPurpose,
    );
  }

  void closeL1Check() {
    if (_l1CheckSource == null) return;
    readingTask.closeTask();
    _l1CheckSource = null;
    notifyListeners();
  }

  void playL1Segment() {
    _l1PlayCount++;
    notifyListeners();
    unawaited(actions.playSource());
  }

  /// Leaves the speaking channel. A personal-expression session files its
  /// one-shot self-assessment first (issue #9 removed the rubric assessment,
  /// but the 3.17 handoff fact still needs one), then the learner is returned
  /// to wherever the session was launched from.
  Future<void> closeSurface() async {
    closeL1Check();
    final returnToReview = actions.source?.recall == 'delayed';
    final personalPattern = activePersonalPattern;
    final personalState = task.state;
    if (personalPattern != null &&
        personalState.phase == 'done' &&
        personalState.attempt != null &&
        personalState.recording != null &&
        personalState.correctedTranscript.trim().isNotEmpty) {
      final assessment =
          await _askPersonalExpressionAssessment?.call() ?? 'partly_expressed';
      try {
        await _getApi?.call()?.recordPersonalExpressionAttempt(
          patternId: personalPattern.id,
          patternVersionId: personalPattern.currentVersion.id,
          channel: 'speaking',
          assistance: 'no_text',
          responseText: personalState.correctedTranscript.trim(),
          rawTranscript: personalState.rawTranscript,
          recordingAssetId: personalState.recording!.id,
          semanticAttemptId: personalState.attempt!.id,
          selfAssessment: assessment,
        );
      } catch (error) {
        player.setStatus(
          '${_t('statusPersonalExpressionSaveFailed')}: $error',
          error: true,
        );
      }
    }
    activePersonalPattern = null;
    await actions.close(_getApi?.call());
    if (returnToReview && _mounted) {
      _onReturnToReview?.call();
    } else if (personalPattern != null && _mounted) {
      _onReturnToPersonalExpression?.call();
    }
  }

  /// Saved words and phrases the learner actually produced in this attempt.
  /// An unreliable ASR transcript yields nothing — a mis-recognition must
  /// never be recorded as evidence of production.
  List<SpeakingTargetCandidate> targetCandidates() {
    final transcript = task.state.correctedTranscript.toLowerCase();
    if (transcript.isEmpty || task.state.asrReliability == 'unreliable') {
      return const [];
    }
    final entries = <LexicalEntry>{
      ...learning.wordEntries.values,
      ...learning.phraseEntries.values.map((details) => details.entry),
    };
    return entries
        .where(
          (entry) =>
              entry.displayForm.trim().isNotEmpty &&
              _containsTarget(
                transcript,
                entry.displayForm.trim().toLowerCase(),
              ),
        )
        .take(12)
        .map(
          (entry) => SpeakingTargetCandidate(
            lexicalEntryId: entry.id,
            surfaceForm: entry.displayForm.trim(),
          ),
        )
        .toList(growable: false);
  }

  bool _containsTarget(String transcript, String surface) {
    if (surface.runes.any((rune) => rune > 0x7f)) {
      return transcript.contains(surface);
    }
    var start = transcript.indexOf(surface);
    while (start >= 0) {
      final before = start == 0 ? null : transcript.codeUnitAt(start - 1);
      final afterIndex = start + surface.length;
      final after = afterIndex == transcript.length
          ? null
          : transcript.codeUnitAt(afterIndex);
      bool isAlphaNumeric(int? code) =>
          code != null &&
          ((code >= 48 && code <= 57) ||
              (code >= 65 && code <= 90) ||
              (code >= 97 && code <= 122));
      if (!isAlphaNumeric(before) && !isAlphaNumeric(after)) return true;
      start = transcript.indexOf(surface, start + 1);
    }
    return false;
  }
}
