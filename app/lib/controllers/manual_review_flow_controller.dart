import 'package:flutter/foundation.dart';

import '../data/repositories/manual_review_repository.dart';
import '../models/api_failure.dart';
import '../models/timeline.dart';
import '../player_adapter.dart';
import 'manual_review_controller.dart';
import 'media_session_coordinator.dart';
import 'player_controller.dart';
import 'resource_actions_coordinator.dart';
import 'subtitle_controller.dart';

enum ManualReviewPhase {
  idle,
  unavailable,
  noTrack,
  loading,
  noTimeline,
  noWords,
  ready,
  saving,
  saved,
  failed,
}

@immutable
class ManualReviewFlowState {
  const ManualReviewFlowState({
    this.phase = ManualReviewPhase.idle,
    this.review,
    this.failure,
    this.saveAttempted = false,
  });

  final ManualReviewPhase phase;
  final ManualReviewSnapshot? review;
  final ApiFailure? failure;
  final bool saveAttempted;
}

@immutable
class ManualReviewSnapshot {
  factory ManualReviewSnapshot._(ManualReviewDraft draft) {
    final cues = draft.track.cues.map(_immutableCue).toList(growable: false);
    return ManualReviewSnapshot._values(
      cues: List.unmodifiable(cues),
      currentCue: cues.firstWhere((cue) => cue.id == draft.currentCue.id),
      currentSentenceWords: List.unmodifiable(draft.currentSentenceWords),
      dirtyWords: Set.unmodifiable(draft.dirtyWords),
      currentSentenceErrors: List.unmodifiable(draft.validateCurrentSentence()),
      allErrors: List.unmodifiable(draft.validateAll()),
    );
  }

  const ManualReviewSnapshot._values({
    required this.cues,
    required this.currentCue,
    required this.currentSentenceWords,
    required this.dirtyWords,
    required this.currentSentenceErrors,
    required this.allErrors,
  });

  final List<Cue> cues;
  final Cue currentCue;
  final List<WordTiming> currentSentenceWords;
  final Set<WordKey> dirtyWords;
  final List<String> currentSentenceErrors;
  final List<String> allErrors;

  bool get dirty => dirtyWords.isNotEmpty;

  static Cue _immutableCue(Cue cue) => Cue(
    id: cue.id,
    index: cue.index,
    start: cue.start,
    end: cue.end,
    text: cue.text,
    tokens: List.unmodifiable(cue.tokens),
  );
}

class ManualReviewEditorViewModel extends ChangeNotifier {
  ManualReviewEditorViewModel(this._draft)
    : _state = ManualReviewSnapshot._(_draft);

  final ManualReviewDraft _draft;
  ManualReviewSnapshot _state;

  ManualReviewSnapshot get state => _state;

  void selectCue(Cue cue) {
    _draft.selectCue(cue);
    _refresh();
  }

  void resetCurrentSentence() {
    _draft.resetCurrentSentence();
    _refresh();
  }

  void updateWordBoundary({
    required String sentenceId,
    required int tokenIndex,
    Duration? start,
    Duration? end,
  }) {
    _draft.updateWordBoundary(
      sentenceId: sentenceId,
      tokenIndex: tokenIndex,
      start: start,
      end: end,
    );
    _refresh();
  }

  void stepWordBoundary({
    required String sentenceId,
    required int tokenIndex,
    required bool adjustStart,
    required int deltaMs,
  }) {
    _draft.stepWordBoundary(
      sentenceId: sentenceId,
      tokenIndex: tokenIndex,
      adjustStart: adjustStart,
      deltaMs: deltaMs,
    );
    _refresh();
  }

  void _refresh() {
    _state = ManualReviewSnapshot._(_draft);
    notifyListeners();
  }
}

sealed class ManualReviewPreparation {
  const ManualReviewPreparation();
}

final class ManualReviewUnavailable extends ManualReviewPreparation {
  const ManualReviewUnavailable();
}

final class ManualReviewNoTrack extends ManualReviewPreparation {
  const ManualReviewNoTrack();
}

final class ManualReviewNoTimeline extends ManualReviewPreparation {
  const ManualReviewNoTimeline();
}

final class ManualReviewNoWords extends ManualReviewPreparation {
  const ManualReviewNoWords();
}

final class ManualReviewReady extends ManualReviewPreparation {
  const ManualReviewReady(this.editor);
  final ManualReviewEditorViewModel editor;
}

final class ManualReviewLoadFailed extends ManualReviewPreparation {
  const ManualReviewLoadFailed(this.failure);
  final ApiFailure failure;
}

final class ManualReviewSuperseded extends ManualReviewPreparation {
  const ManualReviewSuperseded();
}

class ManualReviewFlowController extends ChangeNotifier {
  ManualReviewFlowController(
    this._repository,
    this._adapter,
    ResourceActionsCoordinator resourceActions,
    MediaSessionCoordinator mediaSession, {
    required PlayerController playerController,
    required SubtitleController subtitleController,
    Future<void> Function(String trackId)? loadTimelineResource,
    Future<void> Function(String trackId)? reloadSpeechEnhancements,
  }) : _player = playerController,
       _subtitle = subtitleController,
       _loadTimelineResource =
           loadTimelineResource ?? resourceActions.loadTimelineResource,
       _reloadSpeechEnhancements =
           reloadSpeechEnhancements ?? mediaSession.loadSpeechEnhancements,
       super();

  final ManualReviewRepository? _repository;
  final DesktopPlayerAdapter _adapter;
  final PlayerController _player;
  final SubtitleController _subtitle;
  final Future<void> Function(String trackId) _loadTimelineResource;
  final Future<void> Function(String trackId) _reloadSpeechEnhancements;

  ManualReviewFlowState _state = const ManualReviewFlowState();
  int _loadGeneration = 0;
  int _playGeneration = 0;
  int _saveGeneration = 0;
  bool _disposed = false;
  ManualReviewEditorViewModel? _editor;
  ManualReviewFlowState get state => _state;

  Duration? get loopStart => _player.sourceLoopStart;
  Duration? get loopEnd => _player.sourceLoopEnd;

  void reportStatus(String value, {bool error = false, ApiFailure? failure}) =>
      _player.setStatus(value, error: error, failure: failure);

  Future<ManualReviewPreparation> prepare() async {
    final generation = ++_loadGeneration;
    final repository = _repository;
    if (repository == null) {
      _publish(
        const ManualReviewFlowState(phase: ManualReviewPhase.unavailable),
      );
      return const ManualReviewUnavailable();
    }
    final track = _subtitle.primaryTrack;
    if (track == null) {
      _publish(const ManualReviewFlowState(phase: ManualReviewPhase.noTrack));
      return const ManualReviewNoTrack();
    }
    _publish(const ManualReviewFlowState(phase: ManualReviewPhase.loading));
    try {
      await _loadTimelineResource(track.id);
      if (_stale(generation, _loadGeneration)) {
        return const ManualReviewSuperseded();
      }
      final active = _subtitle.wordTimelineSummaries
          .where((summary) => summary.isActive)
          .firstOrNull;
      final timelineId =
          active?.id ?? _subtitle.llTimelineDocument?.activeWordTimelineId;
      if (timelineId == null) {
        _publish(
          const ManualReviewFlowState(phase: ManualReviewPhase.noTimeline),
        );
        return const ManualReviewNoTimeline();
      }
      final timeline = await repository.wordTimeline(timelineId);
      if (_stale(generation, _loadGeneration)) {
        return const ManualReviewSuperseded();
      }
      final cue = _initialCue(track, timeline);
      if (cue == null) {
        _publish(const ManualReviewFlowState(phase: ManualReviewPhase.noWords));
        return const ManualReviewNoWords();
      }
      _editor?.removeListener(_syncEditorState);
      _editor?.dispose();
      _editor = ManualReviewEditorViewModel(
        ManualReviewDraft(
          track: track,
          sourceTimeline: timeline,
          words: timeline.words,
          initialCue: cue,
        ),
      );
      _editor!.addListener(_syncEditorState);
      _publishDraft(ManualReviewPhase.ready);
      return ManualReviewReady(_editor!);
    } catch (error) {
      if (_stale(generation, _loadGeneration)) {
        return const ManualReviewSuperseded();
      }
      final failure = repository.failureDetail(error);
      _publish(
        ManualReviewFlowState(
          phase: ManualReviewPhase.failed,
          failure: failure,
        ),
      );
      return ManualReviewLoadFailed(failure);
    }
  }

  Future<void> playRange(Duration start, Duration end) async {
    if (end <= start) return;
    final generation = ++_playGeneration;
    _player.setSourceLoop(start, end, label: 'loopReview');
    _subtitle.setLoopCue(false);
    await _adapter.seek(start);
    if (_stale(generation, _playGeneration)) return;
    await _adapter.play();
  }

  Future<void> saveCurrent() async {
    final generation = ++_saveGeneration;
    final editor = _editor;
    final draft = editor?._draft;
    final repository = _repository;
    if (repository == null || draft == null) {
      throw const ApiFailure(raw: 'manual review repository unavailable');
    }
    final trackId = _subtitle.primaryTrack?.id;
    if (trackId == null || trackId != draft.track.id) {
      throw const ApiFailure(raw: 'active subtitle track changed');
    }
    final errors = draft.validateAll();
    if (errors.isNotEmpty) {
      throw ApiFailure(raw: errors.join('; '), code: 'validation_error');
    }
    _publish(
      ManualReviewFlowState(
        phase: ManualReviewPhase.saving,
        review: ManualReviewSnapshot._(draft),
        saveAttempted: true,
      ),
    );
    try {
      await repository.saveTimeline(trackId, draft.createPayload());
      if (_stale(generation, _saveGeneration)) return;
      if (_subtitle.primaryTrack?.id == trackId) {
        await _reloadSpeechEnhancements(trackId);
      }
      if (_stale(generation, _saveGeneration)) return;
      _publish(
        ManualReviewFlowState(
          phase: ManualReviewPhase.saved,
          review: ManualReviewSnapshot._(draft),
          saveAttempted: true,
        ),
      );
    } catch (error) {
      if (_stale(generation, _saveGeneration)) return;
      final failure = repository.failureDetail(error);
      _publish(
        ManualReviewFlowState(
          phase: ManualReviewPhase.failed,
          review: ManualReviewSnapshot._(draft),
          failure: failure,
          saveAttempted: true,
        ),
      );
      throw failure;
    }
  }

  void restoreLoop(Duration? start, Duration? end) =>
      _player.setSourceLoop(start, end);

  Cue? _initialCue(SubtitleTrack track, WordTimeline timeline) {
    final sentenceIds = timeline.words.map((word) => word.sentenceId).toSet();
    final current = _subtitle.currentPrimaryCue;
    if (current != null && sentenceIds.contains(current.id)) return current;
    for (final cue in track.cues) {
      if (sentenceIds.contains(cue.id)) return cue;
    }
    return null;
  }

  void _publish(ManualReviewFlowState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  void _publishDraft(ManualReviewPhase phase) {
    final review = _editor?.state;
    if (review == null) return;
    _publish(
      ManualReviewFlowState(
        phase: phase,
        review: review,
        saveAttempted: _state.saveAttempted,
      ),
    );
  }

  void _syncEditorState() => _publishDraft(ManualReviewPhase.ready);

  bool _stale(int generation, int current) =>
      _disposed || generation != current;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _playGeneration++;
    _saveGeneration++;
    _editor?.removeListener(_syncEditorState);
    _editor?.dispose();
    super.dispose();
  }
}
