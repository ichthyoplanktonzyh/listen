import 'package:flutter/foundation.dart';

import '../models/listening.dart';
import '../models/practice.dart';
import '../models/timeline.dart';
import '../services/api_service.dart';
import '../state/store.dart';

const _unset = Object();

class ExtensiveListeningState {
  const ExtensiveListeningState({
    this.session,
    this.items = const [],
    this.busy = false,
    this.error,
    this.lastCapturedAtMs,
  });

  final PracticeSession? session;
  final List<ListeningInboxItem> items;
  final bool busy;
  final String? error;
  final int? lastCapturedAtMs;

  bool get active => session != null && session!.endedAtMs == null;
  int get activeItemCount =>
      items.where((value) => value.status == 'active').length;

  ExtensiveListeningState copyWith({
    Object? session = _unset,
    List<ListeningInboxItem>? items,
    bool? busy,
    Object? error = _unset,
    Object? lastCapturedAtMs = _unset,
  }) => ExtensiveListeningState(
    session: identical(session, _unset)
        ? this.session
        : session as PracticeSession?,
    items: items ?? this.items,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
    lastCapturedAtMs: identical(lastCapturedAtMs, _unset)
        ? this.lastCapturedAtMs
        : lastCapturedAtMs as int?,
  );
}

class ExtensiveListeningController extends ChangeNotifier {
  ExtensiveListeningController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _store = Store(const ExtensiveListeningState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ExtensiveListeningState> _store;

  /// Injectable wall clock so played-time accumulation is testable.
  final DateTime Function() _clock;

  /// Played-time accumulation for the completion summary (issue #3): wall time
  /// spent in the playing state while a session is active. Pauses stop the
  /// clock; seeks do not disturb it (time keeps passing at 1x while playing).
  /// Kept outside the [Store] on purpose — it advances continuously and must
  /// not churn listeners; readers sample [playedDuration] on demand.
  Duration _playedAccum = Duration.zero;
  DateTime? _playingSince;
  bool _lastPlaying = false;

  Store<ExtensiveListeningState> get store => _store;
  ExtensiveListeningState get state => _store.state;
  PracticeSession? get session => _store.state.session;
  List<ListeningInboxItem> get items => _store.state.items;
  bool get active => _store.state.active;
  bool get busy => _store.state.busy;
  String? get error => _store.state.error;
  int get activeItemCount => _store.state.activeItemCount;

  ValueNotifier<R> select<R>(R Function(ExtensiveListeningState) selector) =>
      _store.select(selector);

  /// Actual accumulated playback time for the current (or just-finished)
  /// session. Live while playing: the open segment is included.
  Duration get playedDuration {
    final since = _playingSince;
    return since == null
        ? _playedAccum
        : _playedAccum + _clock().difference(since);
  }

  /// Feed playback state transitions from the composition root. Cheap and
  /// idempotent; outside an active session it only remembers the latest state
  /// so a session that starts mid-playback begins ticking immediately.
  void notePlaybackState(bool playing) {
    if (playing == _lastPlaying) return;
    _lastPlaying = playing;
    if (!active) return;
    if (playing) {
      _playingSince = _clock();
    } else {
      _flushPlayed();
    }
  }

  void _beginPlayedTracking() {
    _playedAccum = Duration.zero;
    _playingSince = _lastPlaying ? _clock() : null;
  }

  void _flushPlayed() {
    final since = _playingSince;
    if (since == null) return;
    _playedAccum += _clock().difference(since);
    _playingSince = null;
  }

  Future<bool> startSession({
    required LocalApi? api,
    required String? mediaId,
    required String? trackId,
  }) async {
    if (api == null) return _fail('API is not connected.');
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final session = await api.createPracticeSession(
        CreatePracticeSession(
          mode: 'extensive',
          mediaId: mediaId,
          trackId: trackId,
          source: 'extensive_listening',
        ),
      );
      final items = await api.listeningInboxItems();
      _store.update(
        (s) => s.copyWith(session: session, items: items, busy: false),
      );
      _beginPlayedTracking();
      return true;
    } catch (error) {
      return _fail('Could not start extensive listening');
    }
  }

  Future<bool> finishSession(
    LocalApi? api, {
    String? comprehensionReport,
    HuntingCompletionSummary? huntingSummary,
  }) async {
    final current = session;
    if (api == null || current == null) {
      return _fail('No extensive listening session is active.');
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    // Freeze the played clock at completion time; the value stays readable
    // until the next session resets it.
    _flushPlayed();
    try {
      final session = await api.completeListeningSession(
        current.id,
        comprehensionReport: comprehensionReport,
        huntingSummary: huntingSummary,
      );
      final items = await api.listeningInboxItems();
      _store.update(
        (s) => s.copyWith(
          session: session,
          items: items,
          busy: false,
          error: null,
        ),
      );
      return true;
    } catch (error) {
      return _fail('Could not finish extensive listening');
    }
  }

  Future<bool> refreshInbox(LocalApi? api, {String status = 'active'}) async {
    if (api == null) return false;
    try {
      final items = await api.listeningInboxItems(status: status);
      _store.update((s) => s.copyWith(items: items, error: null));
      return true;
    } catch (error) {
      return _fail('Could not load Listening Inbox');
    }
  }

  Future<bool> captureCurrentCue({
    required LocalApi? api,
    required Cue? cue,
    required Cue? previousCue,
    required Cue? nextCue,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    if (api == null || cue == null) {
      return _fail('Open media and subtitles before marking Listening Inbox.');
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final wasActive = active;
      final currentSession = wasActive
          ? session!
          : await api.createPracticeSession(
              CreatePracticeSession(
                mode: 'extensive',
                mediaId: mediaId,
                trackId: trackId,
                source: 'soft_interrupt',
              ),
            );
      final startMs = mediaTimeMs(cue.start);
      final endMs = mediaTimeMs(cue.end);
      final captured = await api.captureListeningInboxItem(
        CaptureListeningInboxItemInput(
          sessionId: currentSession.id,
          target: PracticeTarget(
            kind: 'sentence',
            id: cue.id,
            sentenceId: cue.id,
            startMs: startMs,
            endMs: endMs,
          ),
          anchors: [
            PracticeAnchor(
              kind: 'sentence',
              id: cue.id,
              label: cue.text,
              sentenceId: cue.id,
              tokenStart: 0,
              tokenEnd: cue.tokens.isEmpty ? null : cue.tokens.length - 1,
              startMs: startMs,
              endMs: endMs,
            ),
          ],
          label: cue.text,
          subtitleSnapshot: cue.text,
          contextBefore: previousCue?.text,
          contextAfter: nextCue?.text,
        ),
      );
      final nextItems = [
        captured,
        ...items.where((value) => value.id != captured.id),
      ];
      _store.update(
        (s) => s.copyWith(
          session: currentSession,
          items: nextItems,
          busy: false,
          lastCapturedAtMs: captured.capturedAtMs,
        ),
      );
      // A soft-interrupt capture may have implicitly opened the session; the
      // played clock starts with it.
      if (!wasActive) _beginPlayedTracking();
      return true;
    } catch (error) {
      return _fail('Could not capture Listening Inbox item');
    }
  }

  Future<ListeningInboxItem?> processItem(
    LocalApi? api,
    ListeningInboxItem item,
    String resolution,
  ) async {
    if (api == null) {
      _fail('API is not connected.');
      return null;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final processed = await api.processListeningInboxItem(
        item.id,
        ProcessListeningInboxItemInput(resolution: resolution),
      );
      final nextItems = items
          .where((value) => value.id != processed.id)
          .toList(growable: false);
      _store.update((s) => s.copyWith(items: nextItems, busy: false));
      return processed;
    } catch (error) {
      _fail('Could not process Listening Inbox item');
      return null;
    }
  }

  bool _fail(String message) {
    _store.update((s) => s.copyWith(busy: false, error: message));
    return false;
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
