import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../state/store.dart';

const _unset = Object();

class PracticeDraft {
  const PracticeDraft({
    required this.kind,
    required this.targetKind,
    required this.promptText,
    required this.expectedText,
    required this.target,
    required this.anchors,
    required this.playbackStartMs,
    required this.playbackEndMs,
    this.focusLabel,
    this.degradedMessage,
  });

  final String kind;
  final String targetKind;
  final String promptText;
  final String expectedText;
  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final int playbackStartMs;
  final int playbackEndMs;
  final String? focusLabel;
  final String? degradedMessage;
}

class _StuckPointDraft {
  const _StuckPointDraft({
    required this.target,
    required this.anchors,
    required this.label,
  });

  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final String label;
}

class PracticeState {
  const PracticeState({
    this.session,
    this.draft,
    this.item,
    this.attempt,
    this.summary,
    this.answer = '',
    this.createReviewOnFailure = true,
    this.busy = false,
    this.error,
  });

  final PracticeSession? session;
  final PracticeDraft? draft;
  final PracticeItem? item;
  final PracticeAttempt? attempt;
  final PracticeSessionSummary? summary;
  final String answer;
  final bool createReviewOnFailure;
  final bool busy;
  final String? error;

  bool get hasActivePrompt => draft != null && item != null;
  bool get hasResult => attempt != null;

  PracticeState copyWith({
    Object? session = _unset,
    Object? draft = _unset,
    Object? item = _unset,
    Object? attempt = _unset,
    Object? summary = _unset,
    String? answer,
    bool? createReviewOnFailure,
    bool? busy,
    Object? error = _unset,
  }) => PracticeState(
    session: identical(session, _unset)
        ? this.session
        : session as PracticeSession?,
    draft: identical(draft, _unset) ? this.draft : draft as PracticeDraft?,
    item: identical(item, _unset) ? this.item : item as PracticeItem?,
    attempt: identical(attempt, _unset)
        ? this.attempt
        : attempt as PracticeAttempt?,
    summary: identical(summary, _unset)
        ? this.summary
        : summary as PracticeSessionSummary?,
    answer: answer ?? this.answer,
    createReviewOnFailure: createReviewOnFailure ?? this.createReviewOnFailure,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

class PracticeController extends ChangeNotifier {
  PracticeController() : _store = Store(const PracticeState()) {
    _store.addListener(notifyListeners);
  }

  final Store<PracticeState> _store;
  int _generation = 0;

  Store<PracticeState> get store => _store;
  PracticeState get state => _store.state;
  PracticeSession? get session => _store.state.session;
  PracticeDraft? get draft => _store.state.draft;
  PracticeItem? get item => _store.state.item;
  PracticeAttempt? get attempt => _store.state.attempt;
  PracticeSessionSummary? get summary => _store.state.summary;
  String get answer => _store.state.answer;
  bool get createReviewOnFailure => _store.state.createReviewOnFailure;
  bool get busy => _store.state.busy;
  String? get error => _store.state.error;

  ValueNotifier<R> select<R>(R Function(PracticeState) selector) =>
      _store.select(selector);

  void setAnswer(String value) =>
      _store.update((s) => s.copyWith(answer: value));

  void setCreateReviewOnFailure(bool value) =>
      _store.update((s) => s.copyWith(createReviewOnFailure: value));

  void clear() => _store.replace(const PracticeState());

  void clearResultForRetry() =>
      _store.update((s) => s.copyWith(attempt: null, answer: '', error: null));

  Future<bool> refreshSummary(LocalApi? api) async {
    final currentSession = session;
    if (api == null || currentSession == null) return false;
    try {
      final value = await api.practiceSessionSummary(currentSession.id);
      _store.update(
        (s) => s.copyWith(session: value.session, summary: value, error: null),
      );
      return true;
    } catch (error) {
      _setError('Could not load session summary: $error');
      return false;
    }
  }

  Future<bool> markCurrentStuckPoint({
    required LocalApi? api,
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    Diagnosis? diagnosis,
  }) async => _recordCurrentStuckPoint(
    api: api,
    cue: cue,
    chunk: chunk,
    mediaId: mediaId,
    trackId: trackId,
    mediaTimeMs: mediaTimeMs,
    diagnosis: diagnosis,
    skip: false,
  );

  Future<bool> skipCurrentStuckPoint({
    required LocalApi? api,
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    Diagnosis? diagnosis,
  }) async => _recordCurrentStuckPoint(
    api: api,
    cue: cue,
    chunk: chunk,
    mediaId: mediaId,
    trackId: trackId,
    mediaTimeMs: mediaTimeMs,
    diagnosis: diagnosis,
    skip: true,
  );

  Future<bool> recordDiagnosisView({
    required LocalApi? api,
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    Diagnosis? diagnosis,
  }) async {
    final draft = _stuckPointDraft(cue, chunk: chunk, mediaTimeMs: mediaTimeMs);
    if (api == null || draft == null) return false;
    try {
      final currentSession = await _ensureSession(
        api,
        mediaId: mediaId,
        trackId: trackId,
      );
      await api.recordDiagnosisView(
        RecordDiagnosisViewInput(
          sessionId: currentSession.id,
          target: draft.target,
          anchors: draft.anchors,
          label: draft.label,
          diagnosisHints: _diagnosisHints(diagnosis),
        ),
      );
      await refreshSummary(api);
      return true;
    } catch (error) {
      _setError('Could not record diagnosis view: $error');
      return false;
    }
  }

  Future<bool> closeStuckPoint(LocalApi? api, String targetKey) async {
    final currentSession = session;
    if (api == null || currentSession == null) return false;
    try {
      await api.closeStuckPoint(
        CloseStuckPointInput(
          sessionId: currentSession.id,
          targetKey: targetKey,
        ),
      );
      await refreshSummary(api);
      return true;
    } catch (error) {
      _setError('Could not close stuck point: $error');
      return false;
    }
  }

  Future<bool> completeSession(
    LocalApi? api, {
    bool markFamiliar = true,
  }) async {
    final currentSession = session;
    if (api == null || currentSession == null) {
      _setError('No intensive listening session is active.');
      return false;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final value = await api.completePracticeSession(
        currentSession.id,
        CompletePracticeSessionInput(markFamiliar: markFamiliar),
      );
      _store.update(
        (s) => s.copyWith(
          session: value.session,
          summary: value,
          busy: false,
          error: null,
        ),
      );
      return true;
    } catch (error) {
      _setError('Could not complete session: $error');
      return false;
    }
  }

  Future<void> startCloze({
    required LocalApi? api,
    required Cue? cue,
    required String? mediaId,
    required String? trackId,
    required List<WordTiming> wordTimings,
    required Map<String, LexicalEntry> wordEntries,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    final generation = ++_generation;
    if (api == null || cue == null) {
      _setError('Open media and subtitles before practice.');
      return;
    }
    if (wordTimings.isEmpty) {
      _setError('Word sync is required for cloze practice.');
      return;
    }
    final token = _selectClozeToken(cue, wordEntries);
    if (token == null) {
      _setError('This sentence has no word token for cloze practice.');
      return;
    }
    final timing = wordTimings
        .where((value) => value.tokenIndex == token.index)
        .cast<WordTiming?>()
        .firstWhere((value) => value != null, orElse: () => null);
    final startMs = mediaTimeMs(timing?.start ?? cue.start);
    final endMs = mediaTimeMs(timing?.end ?? cue.end);
    final entry = token.normalized == null
        ? null
        : wordEntries[token.normalized];
    final anchors = _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs);
    if (entry != null) {
      anchors.add(
        PracticeAnchor(
          kind: 'lexical_entry',
          id: entry.id,
          label: token.text.trim().isEmpty ? entry.displayForm : token.text,
          lexicalEntryId: entry.id,
          sentenceId: cue.id,
          tokenStart: token.index,
          tokenEnd: token.index,
          startMs: startMs,
          endMs: endMs,
        ),
      );
    }
    final draft = PracticeDraft(
      kind: 'cloze',
      targetKind: 'lexical',
      promptText: _cueText(cue, blankTokenIndex: token.index),
      expectedText: token.text.trim(),
      target: PracticeTarget(
        kind: 'lexical',
        id: entry?.id ?? '${cue.id}:${token.index}',
        sentenceId: cue.id,
        startMs: startMs,
        endMs: endMs,
      ),
      anchors: anchors,
      playbackStartMs: startMs,
      playbackEndMs: endMs,
      focusLabel: token.text.trim(),
      degradedMessage: timing?.source == 'estimated'
          ? 'Word timing is estimated; the replay window may be approximate.'
          : entry == null
          ? 'This cloze can be checked, but it is not linked to a saved word asset yet.'
          : null,
    );
    await _createItemFromDraft(
      api: api,
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startSentenceDictation({
    required LocalApi? api,
    required Cue? cue,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    String? degradedMessage,
  }) async {
    final generation = ++_generation;
    if (api == null || cue == null) {
      _setError('Open media and subtitles before practice.');
      return;
    }
    final startMs = mediaTimeMs(cue.start);
    final endMs = mediaTimeMs(cue.end);
    final draft = PracticeDraft(
      kind: 'dictation',
      targetKind: 'sentence',
      promptText: cue.text,
      expectedText: cue.text,
      target: PracticeTarget(
        kind: 'sentence',
        id: cue.id,
        sentenceId: cue.id,
        startMs: startMs,
        endMs: endMs,
      ),
      anchors: _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs),
      playbackStartMs: startMs,
      playbackEndMs: endMs,
      focusLabel: 'sentence',
      degradedMessage: degradedMessage,
    );
    await _createItemFromDraft(
      api: api,
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startChunkDictation({
    required LocalApi? api,
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    if (chunk == null) {
      await startSentenceDictation(
        api: api,
        cue: cue,
        mediaId: mediaId,
        trackId: trackId,
        mediaTimeMs: mediaTimeMs,
        degradedMessage:
            'Chunk replay is unavailable for this sentence; using sentence dictation.',
      );
      return;
    }
    final generation = ++_generation;
    if (api == null || cue == null) {
      _setError('Open media and subtitles before practice.');
      return;
    }
    final startMs = mediaTimeMs(chunk.start);
    final endMs = mediaTimeMs(chunk.end);
    final chunkId = '${cue.id}:chunk-${chunk.index}';
    final anchors = _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs);
    anchors.add(
      PracticeAnchor(
        kind: 'chunk',
        id: chunkId,
        label: chunk.text,
        sentenceId: cue.id,
        tokenStart: chunk.tokenStart,
        tokenEnd: chunk.tokenEnd,
        startMs: startMs,
        endMs: endMs,
      ),
    );
    final draft = PracticeDraft(
      kind: 'dictation',
      targetKind: 'chunk',
      promptText: chunk.text,
      expectedText: chunk.text,
      target: PracticeTarget(
        kind: 'chunk',
        id: chunkId,
        sentenceId: cue.id,
        chunkId: chunkId,
        startMs: startMs,
        endMs: endMs,
      ),
      anchors: anchors,
      playbackStartMs: startMs,
      playbackEndMs: endMs,
      focusLabel: 'chunk ${chunk.index + 1}',
    );
    await _createItemFromDraft(
      api: api,
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> submit(LocalApi? api) async {
    final currentItem = item;
    if (api == null || currentItem == null) {
      _setError('Practice item is not ready.');
      return;
    }
    final textAnswer = answer.trim();
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final value = await api.submitPracticeAttempt(
        SubmitPracticeAttempt(
          itemId: currentItem.id,
          textAnswer: textAnswer,
          createReviewItemOnFailure: createReviewOnFailure,
        ),
      );
      _store.update((s) => s.copyWith(attempt: value, busy: false));
      await refreshSummary(api);
    } catch (error) {
      _setError('Practice submission failed: $error');
    }
  }

  Future<void> saveCurrentFailureToReview(LocalApi? api) async {
    final currentItem = item;
    final currentAttempt = attempt;
    if (api == null || currentItem == null || currentAttempt == null) {
      _setError('No practice failure is ready to review.');
      return;
    }
    if (currentAttempt.result == 'correct') return;
    final lexicalEntryId = currentItem.anchors
        .where((anchor) => anchor.kind == 'lexical_entry')
        .map((anchor) => anchor.lexicalEntryId)
        .cast<String?>()
        .firstWhere((value) => value != null, orElse: () => null);
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final review = await api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'practice_failure',
            id: currentAttempt.id,
            practiceAttemptId: currentAttempt.id,
            lexicalEntryId: lexicalEntryId,
          ),
          anchors: currentItem.anchors,
          promptSnapshot: currentItem.promptSnapshot,
        ),
      );
      final reviewIds = [...currentAttempt.generatedReviewItemIds, review.id];
      _store.update(
        (s) => s.copyWith(
          attempt: currentAttempt.copyWith(generatedReviewItemIds: reviewIds),
          busy: false,
        ),
      );
      await refreshSummary(api);
    } catch (error) {
      _setError('Could not save review item: $error');
    }
  }

  Future<bool> _recordCurrentStuckPoint({
    required LocalApi? api,
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    required Diagnosis? diagnosis,
    required bool skip,
  }) async {
    final draft = _stuckPointDraft(cue, chunk: chunk, mediaTimeMs: mediaTimeMs);
    if (api == null || draft == null) {
      _setError('Open a subtitle sentence before marking a stuck point.');
      return false;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final currentSession = await _ensureSession(
        api,
        mediaId: mediaId,
        trackId: trackId,
      );
      final input = RecordStuckPointInput(
        sessionId: currentSession.id,
        target: draft.target,
        anchors: draft.anchors,
        label: draft.label,
        diagnosisHints: _diagnosisHints(diagnosis),
      );
      if (skip) {
        await api.skipStuckPoint(input);
      } else {
        await api.markStuckPoint(input);
      }
      _store.update((s) => s.copyWith(session: currentSession, busy: false));
      await refreshSummary(api);
      return true;
    } catch (error) {
      _setError(
        skip
            ? 'Could not skip stuck point: $error'
            : 'Could not mark stuck point: $error',
      );
      return false;
    }
  }

  Future<void> _createItemFromDraft({
    required LocalApi api,
    required int generation,
    required PracticeDraft draft,
    required String? mediaId,
    required String? trackId,
  }) async {
    _store.update(
      (s) => s.copyWith(
        draft: draft,
        item: null,
        attempt: null,
        answer: '',
        busy: true,
        error: null,
      ),
    );
    try {
      final session = await _ensureSession(
        api,
        mediaId: mediaId,
        trackId: trackId,
      );
      final item = await api.createPracticeItem(
        CreatePracticeItem(
          sessionId: session.id,
          kind: draft.kind,
          target: draft.target,
          promptSnapshot: draft.promptText,
          expectedText: draft.expectedText,
          anchors: draft.anchors,
        ),
      );
      if (generation != _generation) return;
      _store.update(
        (s) => s.copyWith(session: session, item: item, busy: false),
      );
    } catch (error) {
      if (generation == _generation) {
        _setError('Could not start practice: $error');
      }
    }
  }

  Future<PracticeSession> _ensureSession(
    LocalApi api, {
    required String? mediaId,
    required String? trackId,
  }) async {
    final current = state.session;
    if (current != null &&
        current.mediaId == mediaId &&
        current.trackId == trackId &&
        current.mode == 'intensive') {
      return current;
    }
    return api.createPracticeSession(
      CreatePracticeSession(
        mode: 'intensive',
        mediaId: mediaId,
        trackId: trackId,
        source: 'current_sentence_practice',
      ),
    );
  }

  _StuckPointDraft? _stuckPointDraft(
    Cue? cue, {
    required DisplayChunk? chunk,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) {
    if (cue == null) return null;
    if (chunk != null) {
      final startMs = mediaTimeMs(chunk.start);
      final endMs = mediaTimeMs(chunk.end);
      final chunkId = '${cue.id}:chunk-${chunk.index}';
      final anchors = _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs);
      anchors.add(
        PracticeAnchor(
          kind: 'chunk',
          id: chunkId,
          label: chunk.text,
          sentenceId: cue.id,
          tokenStart: chunk.tokenStart,
          tokenEnd: chunk.tokenEnd,
          startMs: startMs,
          endMs: endMs,
        ),
      );
      return _StuckPointDraft(
        target: PracticeTarget(
          kind: 'chunk',
          id: chunkId,
          sentenceId: cue.id,
          chunkId: chunkId,
          startMs: startMs,
          endMs: endMs,
        ),
        anchors: anchors,
        label: chunk.text,
      );
    }
    final startMs = mediaTimeMs(cue.start);
    final endMs = mediaTimeMs(cue.end);
    return _StuckPointDraft(
      target: PracticeTarget(
        kind: 'sentence',
        id: cue.id,
        sentenceId: cue.id,
        startMs: startMs,
        endMs: endMs,
      ),
      anchors: _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs),
      label: cue.text,
    );
  }

  List<DiagnosisHintEvidence> _diagnosisHints(Diagnosis? diagnosis) =>
      diagnosis == null
      ? const []
      : diagnosis.hints
            .map(
              (hint) =>
                  DiagnosisHintEvidence(kind: hint.kind, reasons: hint.reasons),
            )
            .toList(growable: false);

  void _setError(String message) =>
      _store.update((s) => s.copyWith(busy: false, error: message));

  SubtitleToken? _selectClozeToken(
    Cue cue,
    Map<String, LexicalEntry> wordEntries,
  ) {
    final wordTokens = cue.tokens
        .where((value) => value.kind == 'word' && value.text.trim().isNotEmpty)
        .toList(growable: false);
    for (final status in const [
      'known_recognized',
      'known_not_recognized',
      'unknown_meaning',
    ]) {
      for (final token in wordTokens) {
        final entry = token.normalized == null
            ? null
            : wordEntries[token.normalized];
        if (entry?.status == status) return token;
      }
    }
    return wordTokens.isEmpty ? null : wordTokens.first;
  }

  List<PracticeAnchor> _baseSentenceAnchors(
    Cue cue, {
    required int startMs,
    required int endMs,
  }) => [
    PracticeAnchor(
      kind: 'sentence',
      id: cue.id,
      label: cue.text,
      sentenceId: cue.id,
      tokenStart: cue.tokens.isEmpty ? null : cue.tokens.first.index,
      tokenEnd: cue.tokens.isEmpty ? null : cue.tokens.last.index,
      startMs: startMs,
      endMs: endMs,
    ),
  ];

  String _cueText(Cue cue, {int? blankTokenIndex}) {
    if (cue.tokens.isEmpty) return cue.text;
    return cue.tokens
        .map((token) => token.index == blankTokenIndex ? '____' : token.text)
        .join();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
