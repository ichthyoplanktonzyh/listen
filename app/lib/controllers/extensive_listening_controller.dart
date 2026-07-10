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
  ExtensiveListeningController()
    : _store = Store(const ExtensiveListeningState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ExtensiveListeningState> _store;

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
      return true;
    } catch (error) {
      return _fail('Could not start extensive listening: $error');
    }
  }

  Future<bool> finishSession(
    LocalApi? api, {
    String? comprehensionReport,
  }) async {
    final current = session;
    if (api == null || current == null) {
      return _fail('No extensive listening session is active.');
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final session = await api.completeListeningSession(
        current.id,
        comprehensionReport: comprehensionReport,
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
      return _fail('Could not finish extensive listening: $error');
    }
  }

  Future<bool> refreshInbox(LocalApi? api, {String status = 'active'}) async {
    if (api == null) return false;
    try {
      final items = await api.listeningInboxItems(status: status);
      _store.update((s) => s.copyWith(items: items, error: null));
      return true;
    } catch (error) {
      return _fail('Could not load Listening Inbox: $error');
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
      final currentSession = active
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
      return true;
    } catch (error) {
      return _fail('Could not capture Listening Inbox item: $error');
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
      _fail('Could not process Listening Inbox item: $error');
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
