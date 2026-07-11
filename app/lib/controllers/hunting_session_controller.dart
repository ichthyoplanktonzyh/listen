import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../services/api_service.dart';
import '../state/store.dart';

const _unset = Object();

class HuntingSessionState {
  const HuntingSessionState({
    this.enabled = false,
    this.loaded = false,
    this.indexed = false,
    this.occurrences = const [],
    this.current,
    this.phase = 'idle',
    this.promptedCount = 0,
    this.recognizedCount = 0,
    this.notRecognizedCount = 0,
    this.notNoticedCount = 0,
    this.perTargetPromptCount = const {},
    this.handledOccurrenceIds = const {},
    this.sessionId,
    this.mediaId,
    this.trackId,
    this.busy = false,
    this.error,
  });

  final bool enabled;
  final bool loaded;
  final bool indexed;
  final List<HuntingOccurrence> occurrences;
  final HuntingOccurrence? current;

  /// idle | priming | check
  final String phase;
  final int promptedCount;
  final int recognizedCount;
  final int notRecognizedCount;
  final int notNoticedCount;
  final Map<String, int> perTargetPromptCount;
  final Set<String> handledOccurrenceIds;
  final String? sessionId;
  final String? mediaId;
  final String? trackId;
  final bool busy;
  final String? error;

  int get remainingBudget => (5 - promptedCount).clamp(0, 5);

  HuntingSessionState copyWith({
    bool? enabled,
    bool? loaded,
    bool? indexed,
    List<HuntingOccurrence>? occurrences,
    Object? current = _unset,
    String? phase,
    int? promptedCount,
    int? recognizedCount,
    int? notRecognizedCount,
    int? notNoticedCount,
    Map<String, int>? perTargetPromptCount,
    Set<String>? handledOccurrenceIds,
    Object? sessionId = _unset,
    Object? mediaId = _unset,
    Object? trackId = _unset,
    bool? busy,
    Object? error = _unset,
  }) => HuntingSessionState(
    enabled: enabled ?? this.enabled,
    loaded: loaded ?? this.loaded,
    indexed: indexed ?? this.indexed,
    occurrences: occurrences ?? this.occurrences,
    current: identical(current, _unset)
        ? this.current
        : current as HuntingOccurrence?,
    phase: phase ?? this.phase,
    promptedCount: promptedCount ?? this.promptedCount,
    recognizedCount: recognizedCount ?? this.recognizedCount,
    notRecognizedCount: notRecognizedCount ?? this.notRecognizedCount,
    notNoticedCount: notNoticedCount ?? this.notNoticedCount,
    perTargetPromptCount: perTargetPromptCount ?? this.perTargetPromptCount,
    handledOccurrenceIds: handledOccurrenceIds ?? this.handledOccurrenceIds,
    sessionId: identical(sessionId, _unset)
        ? this.sessionId
        : sessionId as String?,
    mediaId: identical(mediaId, _unset) ? this.mediaId : mediaId as String?,
    trackId: identical(trackId, _unset) ? this.trackId : trackId as String?,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

class HuntingSessionController extends ChangeNotifier {
  HuntingSessionController() : _store = Store(const HuntingSessionState()) {
    _store.addListener(notifyListeners);
  }

  final Store<HuntingSessionState> _store;

  Store<HuntingSessionState> get store => _store;
  HuntingSessionState get state => _store.state;

  Future<bool> start({
    required LocalApi api,
    required String sessionId,
    required String mediaId,
    String? trackId,
  }) async {
    _store.replace(
      HuntingSessionState(
        enabled: true,
        sessionId: sessionId,
        mediaId: mediaId,
        trackId: trackId,
        busy: true,
      ),
    );
    return _loadOccurrences(api);
  }

  Future<bool> reload(LocalApi api) async {
    if (!state.enabled || state.mediaId == null) return false;
    _store.update((state) => state.copyWith(busy: true, error: null));
    return _loadOccurrences(api);
  }

  Future<bool> _loadOccurrences(LocalApi api) async {
    try {
      final result = await api.huntingOccurrences(
        mediaId: state.mediaId!,
        trackId: state.trackId,
      );
      final occurrences = result.occurrences.toList()
        ..sort(
          (left, right) =>
              left.occurrence.startMs.compareTo(right.occurrence.startMs),
        );
      _store.update(
        (state) => state.copyWith(
          loaded: true,
          indexed: result.indexed,
          occurrences: occurrences,
          busy: false,
          error: null,
        ),
      );
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          loaded: true,
          busy: false,
          error: 'Could not locate hunting targets: $error',
        ),
      );
      return false;
    }
  }

  void stop() => _store.replace(const HuntingSessionState());

  void updatePosition(Duration position) {
    final state = this.state;
    if (!state.enabled || state.busy || !state.indexed) return;
    final positionMs = position.inMilliseconds;
    final current = state.current;
    if (current != null) {
      if (state.phase == 'priming' && positionMs >= current.occurrence.endMs) {
        _store.update((state) => state.copyWith(phase: 'check'));
      } else if (state.phase == 'check' &&
          positionMs > current.occurrence.endMs + 5000) {
        _dismissCurrentWithoutEvidence();
      }
      return;
    }
    if (state.promptedCount >= 5) return;

    for (final occurrence in state.occurrences) {
      if (state.handledOccurrenceIds.contains(occurrence.occurrence.id)) {
        continue;
      }
      if ((state.perTargetPromptCount[occurrence.targetId] ?? 0) >= 2) {
        continue;
      }
      final primingAt = (occurrence.occurrence.startMs - 1500).clamp(
        0,
        occurrence.occurrence.startMs,
      );
      if (positionMs >= primingAt &&
          positionMs < occurrence.occurrence.startMs) {
        final perTarget = Map<String, int>.of(state.perTargetPromptCount);
        perTarget[occurrence.targetId] =
            (perTarget[occurrence.targetId] ?? 0) + 1;
        _store.update(
          (state) => state.copyWith(
            current: occurrence,
            phase: 'priming',
            promptedCount: state.promptedCount + 1,
            perTargetPromptCount: perTarget,
          ),
        );
        return;
      }
      if (positionMs > occurrence.occurrence.endMs + 5000) {
        final handled = Set<String>.of(state.handledOccurrenceIds)
          ..add(occurrence.occurrence.id);
        _store.update((state) => state.copyWith(handledOccurrenceIds: handled));
        return;
      }
    }
  }

  Future<bool> answer(LocalApi api, String answer) async {
    final current = state.current;
    final sessionId = state.sessionId;
    if (current == null || state.phase != 'check' || sessionId == null) {
      return false;
    }
    _store.update((state) => state.copyWith(busy: true, error: null));
    try {
      await api.submitHuntingCheck(
        sessionId: sessionId,
        targetId: current.targetId,
        occurrenceId: current.occurrence.id,
        answer: answer,
      );
      final handled = Set<String>.of(state.handledOccurrenceIds)
        ..add(current.occurrence.id);
      _store.update(
        (state) => state.copyWith(
          current: null,
          phase: 'idle',
          busy: false,
          handledOccurrenceIds: handled,
          recognizedCount:
              state.recognizedCount + (answer == 'recognized' ? 1 : 0),
          notRecognizedCount:
              state.notRecognizedCount + (answer == 'not_recognized' ? 1 : 0),
          notNoticedCount:
              state.notNoticedCount + (answer == 'not_noticed' ? 1 : 0),
          error: null,
        ),
      );
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not save hunting answer: $error',
        ),
      );
      return false;
    }
  }

  void _dismissCurrentWithoutEvidence() {
    final current = state.current;
    if (current == null) return;
    final handled = Set<String>.of(state.handledOccurrenceIds)
      ..add(current.occurrence.id);
    _store.update(
      (state) => state.copyWith(
        current: null,
        phase: 'idle',
        handledOccurrenceIds: handled,
      ),
    );
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
