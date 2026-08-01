import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/practice_repository.dart';
import '../models/practice.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../services/practice_file_service.dart';
import '../services/shadowing_recorder.dart';
import '../state/store.dart';

const _unset = Object();

class PracticeDraft {
  PracticeDraft({
    required this.kind,
    required this.targetKind,
    required this.promptText,
    required this.expectedText,
    required this.target,
    required List<PracticeAnchor> anchors,
    required this.playbackStartMs,
    required this.playbackEndMs,
    this.focusLabel,
    this.degradedMessage,
    List<ShadowingStep> shadowingSteps = const [],
    this.shadowingStepIndex = 0,
    this.referenceMediaPath,
    this.sourceMediaId,
  }) : _anchors = List.unmodifiable(anchors),
       _shadowingSteps = List.unmodifiable(shadowingSteps);

  final String kind;
  final String targetKind;
  final String promptText;
  final String expectedText;
  final PracticeTarget target;
  final List<PracticeAnchor> _anchors;
  List<PracticeAnchor> get anchors => List.unmodifiable(_anchors);
  final int playbackStartMs;
  final int playbackEndMs;
  final String? focusLabel;
  final String? degradedMessage;
  final List<ShadowingStep> _shadowingSteps;
  List<ShadowingStep> get shadowingSteps => List.unmodifiable(_shadowingSteps);
  final int shadowingStepIndex;
  final String? referenceMediaPath;
  final String? sourceMediaId;
}

class ShadowingStep {
  ShadowingStep({
    required this.label,
    required this.target,
    required this.promptText,
    required List<PracticeAnchor> anchors,
    required this.startMs,
    required this.endMs,
  }) : _anchors = List.unmodifiable(anchors);

  final String label;
  final PracticeTarget target;
  final String promptText;
  final List<PracticeAnchor> _anchors;
  List<PracticeAnchor> get anchors => List.unmodifiable(_anchors);
  final int startMs;
  final int endMs;
}

class PracticeState {
  const PracticeState({
    this.session,
    this.draft,
    this.item,
    this.attempt,
    this.answer = '',
    this.createReviewOnFailure = true,
    this.busy = false,
    this.error,
    this.recordingActive = false,
    this.microphonePermission = MicrophonePermissionStatus.notDetermined,
    this.recordingAsset,
    this.comparison,
    this.shadowingRate = 0.9,
    this.comparisonWarning,
  });

  final PracticeSession? session;
  final PracticeDraft? draft;
  final PracticeItem? item;
  final PracticeAttempt? attempt;
  final String answer;
  final bool createReviewOnFailure;
  final bool busy;
  final String? error;
  final bool recordingActive;
  final MicrophonePermissionStatus microphonePermission;
  final RecordingAsset? recordingAsset;
  final ShadowingComparison? comparison;
  final double shadowingRate;
  final String? comparisonWarning;

  bool get hasActivePrompt => draft != null && item != null;
  bool get hasResult => attempt != null;

  PracticeState copyWith({
    Object? session = _unset,
    Object? draft = _unset,
    Object? item = _unset,
    Object? attempt = _unset,
    String? answer,
    bool? createReviewOnFailure,
    bool? busy,
    Object? error = _unset,
    bool? recordingActive,
    MicrophonePermissionStatus? microphonePermission,
    Object? recordingAsset = _unset,
    Object? comparison = _unset,
    double? shadowingRate,
    Object? comparisonWarning = _unset,
  }) => PracticeState(
    session: identical(session, _unset)
        ? this.session
        : session as PracticeSession?,
    draft: identical(draft, _unset) ? this.draft : draft as PracticeDraft?,
    item: identical(item, _unset) ? this.item : item as PracticeItem?,
    attempt: identical(attempt, _unset)
        ? this.attempt
        : attempt as PracticeAttempt?,
    answer: answer ?? this.answer,
    createReviewOnFailure: createReviewOnFailure ?? this.createReviewOnFailure,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
    recordingActive: recordingActive ?? this.recordingActive,
    microphonePermission: microphonePermission ?? this.microphonePermission,
    recordingAsset: identical(recordingAsset, _unset)
        ? this.recordingAsset
        : recordingAsset as RecordingAsset?,
    comparison: identical(comparison, _unset)
        ? this.comparison
        : comparison as ShadowingComparison?,
    shadowingRate: shadowingRate ?? this.shadowingRate,
    comparisonWarning: identical(comparisonWarning, _unset)
        ? this.comparisonWarning
        : comparisonWarning as String?,
  );
}

class PracticeController extends ChangeNotifier {
  PracticeController({
    this.repository = const UnavailablePracticeRepository(),
    ShadowingRecorder? recorder,
    this.fileService = const LocalPracticeFileService(),
  }) : _recorder = recorder ?? MacosShadowingRecorder(),
       _store = Store(const PracticeState()) {
    _store.addListener(notifyListeners);
  }

  final Store<PracticeState> _store;
  final PracticeRepository repository;
  final ShadowingRecorder _recorder;
  final PracticeFileService fileService;
  int _generation = 0;

  Store<PracticeState> get store => _store;
  PracticeState get state => _store.state;
  PracticeSession? get session => _store.state.session;
  PracticeDraft? get draft => _store.state.draft;
  PracticeItem? get item => _store.state.item;
  PracticeAttempt? get attempt => _store.state.attempt;
  String get answer => _store.state.answer;
  bool get createReviewOnFailure => _store.state.createReviewOnFailure;
  bool get busy => _store.state.busy;
  String? get error => _store.state.error;
  bool get recordingActive => _store.state.recordingActive;
  RecordingAsset? get recordingAsset => _store.state.recordingAsset;
  ShadowingComparison? get comparison => _store.state.comparison;

  ValueNotifier<R> select<R>(R Function(PracticeState) selector) =>
      _store.select(selector);

  void setAnswer(String value) =>
      _store.update((s) => s.copyWith(answer: value));

  void setCreateReviewOnFailure(bool value) =>
      _store.update((s) => s.copyWith(createReviewOnFailure: value));

  void clear() {
    // Ignore any in-flight item creation that resolves after the floating
    // practice window has been closed.
    _generation++;
    if (recordingActive) unawaited(_recorder.cancel());
    _store.replace(const PracticeState());
  }

  void clearResultForRetry() =>
      _store.update((s) => s.copyWith(attempt: null, answer: '', error: null));

  void setShadowingRate(double value) =>
      _store.update((s) => s.copyWith(shadowingRate: value));

  Future<void> startCloze({
    required Cue? cue,
    required String? mediaId,
    required String? trackId,
    required List<WordTiming> wordTimings,
    required Map<String, LexicalEntry> wordEntries,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    final generation = ++_generation;
    if (!repository.isAvailable || cue == null) {
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
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startSentenceDictation({
    required Cue? cue,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
    String? degradedMessage,
  }) async {
    final generation = ++_generation;
    if (!repository.isAvailable || cue == null) {
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
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startChunkDictation({
    required Cue? cue,
    required DisplayChunk? chunk,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    if (chunk == null) {
      await startSentenceDictation(
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
    if (!repository.isAvailable || cue == null) {
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
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startShadowing({
    required Cue? cue,
    required DisplayChunk? chunk,
    required List<DisplayChunk> chunks,
    required String? mediaId,
    required String? trackId,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) async {
    final generation = ++_generation;
    if (!repository.isAvailable || cue == null) {
      _setError('Open media and subtitles before shadowing.');
      return;
    }
    final steps = _shadowingSteps(cue, chunk, chunks, mediaTimeMs: mediaTimeMs);
    final draft = _shadowingDraft(
      steps,
      0,
      degradedMessage: chunk == null
          ? 'No rhythm chunk is available; shadowing the full sentence.'
          : null,
    );
    await _createItemFromDraft(
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> selectShadowingStep({
    required int index,
    required String? mediaId,
    required String? trackId,
  }) async {
    final current = draft;
    if (!repository.isAvailable ||
        current == null ||
        current.kind != 'shadowing' ||
        index < 0 ||
        index >= current.shadowingSteps.length ||
        index == current.shadowingStepIndex) {
      return;
    }
    final generation = ++_generation;
    await _createItemFromDraft(
      generation: generation,
      draft: _shadowingDraft(
        current.shadowingSteps,
        index,
        degradedMessage: current.degradedMessage,
      ),
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  Future<void> startExternalShadowing({
    required String mediaPath,
    required String? mediaId,
    required String? trackId,
    required String? sentenceId,
    required String promptText,
    required int startMs,
    required int endMs,
  }) async {
    final generation = ++_generation;
    if (!repository.isAvailable ||
        mediaPath.trim().isEmpty ||
        promptText.trim().isEmpty ||
        endMs <= startMs) {
      _setError('This source clip cannot be used for shadowing.');
      return;
    }
    final target = PracticeTarget(
      kind: 'segment',
      id: sentenceId == null
          ? 'segment:$startMs:$endMs'
          : '$sentenceId:$startMs:$endMs',
      sentenceId: sentenceId,
      startMs: startMs,
      endMs: endMs,
    );
    final anchors = sentenceId == null
        ? <PracticeAnchor>[]
        : [
            PracticeAnchor(
              kind: 'sentence',
              id: sentenceId,
              label: promptText,
              sentenceId: sentenceId,
              startMs: startMs,
              endMs: endMs,
            ),
          ];
    final step = ShadowingStep(
      label: 'source clip',
      target: target,
      promptText: promptText,
      anchors: anchors,
      startMs: startMs,
      endMs: endMs,
    );
    final draft = PracticeDraft(
      kind: 'shadowing',
      targetKind: 'segment',
      promptText: promptText,
      expectedText: promptText,
      target: target,
      anchors: anchors,
      playbackStartMs: startMs,
      playbackEndMs: endMs,
      focusLabel: step.label,
      shadowingSteps: [step],
      referenceMediaPath: mediaPath,
      sourceMediaId: mediaId,
    );
    await _createItemFromDraft(
      generation: generation,
      draft: draft,
      mediaId: mediaId,
      trackId: trackId,
    );
  }

  List<ShadowingStep> _shadowingSteps(
    Cue cue,
    DisplayChunk? current,
    List<DisplayChunk> chunks, {
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) {
    if (current == null) {
      final startMs = mediaTimeMs(cue.start);
      final endMs = mediaTimeMs(cue.end);
      return [
        ShadowingStep(
          label: 'sentence',
          target: PracticeTarget(
            kind: 'sentence',
            id: cue.id,
            sentenceId: cue.id,
            startMs: startMs,
            endMs: endMs,
          ),
          promptText: cue.text,
          anchors: _baseSentenceAnchors(cue, startMs: startMs, endMs: endMs),
          startMs: startMs,
          endMs: endMs,
        ),
      ];
    }
    final ordered = [...chunks]
      ..sort((left, right) => left.index.compareTo(right.index));
    final position = ordered.indexWhere(
      (value) => value.index == current.index,
    );
    final steps = <ShadowingStep>[
      _chunkShadowingStep(cue, current, mediaTimeMs),
    ];
    if (position >= 0 && position + 1 < ordered.length) {
      final next = ordered[position + 1];
      final startMs = mediaTimeMs(current.start);
      final endMs = mediaTimeMs(next.end);
      steps.add(
        ShadowingStep(
          label: '1 + 2',
          target: PracticeTarget(
            kind: 'segment',
            id: '${cue.id}:chunks-${current.index}-${next.index}',
            sentenceId: cue.id,
            startMs: startMs,
            endMs: endMs,
          ),
          promptText: '${current.text} ${next.text}',
          anchors: [
            ..._baseSentenceAnchors(cue, startMs: startMs, endMs: endMs),
            _chunkAnchor(cue, current, mediaTimeMs),
            _chunkAnchor(cue, next, mediaTimeMs),
          ],
          startMs: startMs,
          endMs: endMs,
        ),
      );
    }
    final sentenceStart = mediaTimeMs(cue.start);
    final sentenceEnd = mediaTimeMs(cue.end);
    if (steps.last.startMs != sentenceStart ||
        steps.last.endMs != sentenceEnd) {
      steps.add(
        ShadowingStep(
          label: 'sentence',
          target: PracticeTarget(
            kind: 'sentence',
            id: cue.id,
            sentenceId: cue.id,
            startMs: sentenceStart,
            endMs: sentenceEnd,
          ),
          promptText: cue.text,
          anchors: _baseSentenceAnchors(
            cue,
            startMs: sentenceStart,
            endMs: sentenceEnd,
          ),
          startMs: sentenceStart,
          endMs: sentenceEnd,
        ),
      );
    }
    return steps;
  }

  ShadowingStep _chunkShadowingStep(
    Cue cue,
    DisplayChunk chunk,
    int Function(Duration subtitleTime) mediaTimeMs,
  ) {
    final startMs = mediaTimeMs(chunk.start);
    final endMs = mediaTimeMs(chunk.end);
    final chunkId = '${cue.id}:chunk-${chunk.index}';
    return ShadowingStep(
      label: 'chunk ${chunk.index + 1}',
      target: PracticeTarget(
        kind: 'chunk',
        id: chunkId,
        sentenceId: cue.id,
        chunkId: chunkId,
        startMs: startMs,
        endMs: endMs,
      ),
      promptText: chunk.text,
      anchors: [
        ..._baseSentenceAnchors(cue, startMs: startMs, endMs: endMs),
        _chunkAnchor(cue, chunk, mediaTimeMs),
      ],
      startMs: startMs,
      endMs: endMs,
    );
  }

  PracticeAnchor _chunkAnchor(
    Cue cue,
    DisplayChunk chunk,
    int Function(Duration subtitleTime) mediaTimeMs,
  ) => PracticeAnchor(
    kind: 'chunk',
    id: '${cue.id}:chunk-${chunk.index}',
    label: chunk.text,
    sentenceId: cue.id,
    tokenStart: chunk.tokenStart,
    tokenEnd: chunk.tokenEnd,
    startMs: mediaTimeMs(chunk.start),
    endMs: mediaTimeMs(chunk.end),
  );

  PracticeDraft _shadowingDraft(
    List<ShadowingStep> steps,
    int index, {
    String? degradedMessage,
  }) {
    final step = steps[index];
    return PracticeDraft(
      kind: 'shadowing',
      targetKind: step.target.kind,
      promptText: step.promptText,
      expectedText: step.promptText,
      target: step.target,
      anchors: step.anchors,
      playbackStartMs: step.startMs,
      playbackEndMs: step.endMs,
      focusLabel: step.label,
      degradedMessage: degradedMessage,
      shadowingSteps: steps,
      shadowingStepIndex: index,
    );
  }

  Future<bool> beginShadowingRecording({
    required Future<void> Function() acquireAudioFocus,
  }) async {
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      var permission = await _recorder.permissionStatus();
      if (permission == MicrophonePermissionStatus.notDetermined) {
        permission = await _recorder.requestPermission();
      }
      if (permission != MicrophonePermissionStatus.granted) {
        _store.update(
          (s) => s.copyWith(
            busy: false,
            microphonePermission: permission,
            error: 'Microphone permission is required for shadowing recording.',
          ),
        );
        return false;
      }
      await acquireAudioFocus();
      await _recorder.start();
      _store.update(
        (s) => s.copyWith(
          busy: false,
          recordingActive: true,
          microphonePermission: permission,
          comparisonWarning: null,
        ),
      );
      return true;
    } catch (error) {
      _setError('Could not start recording');
      return false;
    }
  }

  Future<void> stopShadowingRecording({
    required String language,
    required String? mediaId,
    required Future<String> Function() extractReferenceWav,
  }) async {
    final currentItem = item;
    final currentDraft = draft;
    if (!repository.isAvailable ||
        currentItem == null ||
        currentDraft == null) {
      _setError('Shadowing practice is not ready.');
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final captured = await _recorder.stop();
      final asset = await repository.createRecording(
        CreateRecordingAsset(
          filePath: captured.path,
          durationMs: captured.durationMs,
          target: currentItem.target,
          sourceSegment: PlayableSegment(
            mediaId: mediaId,
            startMs: currentDraft.playbackStartMs,
            endMs: currentDraft.playbackEndMs,
            label: currentDraft.focusLabel ?? 'shadowing target',
            subtitleSnapshot: currentDraft.expectedText,
            availability: mediaId == null ? 'missing_media' : 'available',
          ),
          language: language,
          audio: RecordingAudioMetadata(
            container: 'wav',
            codec: 'pcm_s16le',
            sampleRateHz: MacosShadowingRecorder.sampleRateHz,
            channels: 1,
            sampleFormat: 's16',
            byteLength: captured.byteLength,
            contentSha256: captured.contentSha256,
          ),
          recorderVersion: 'macos-avfoundation-pcm16-v1',
        ),
      );
      final completed = await repository.completeShadowing(
        itemId: currentItem.id,
        recordingId: asset.id,
      );
      _store.update(
        (s) => s.copyWith(
          recordingActive: false,
          recordingAsset: asset,
          attempt: completed,
          comparison: null,
          busy: true,
        ),
      );
      try {
        final referenceWav = await extractReferenceWav();
        final comparison = await repository.compareShadowing(
          recordingId: asset.id,
          referenceWavPath: referenceWav,
        );
        _store.update(
          (s) => s.copyWith(
            comparison: comparison,
            comparisonWarning: null,
            busy: false,
          ),
        );
      } catch (error) {
        _store.update(
          (s) => s.copyWith(
            busy: false,
            comparisonWarning:
                'Recording saved, but objective comparison is unavailable',
          ),
        );
      }
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          recordingActive: false,
          busy: false,
          error: 'Could not save recording',
        ),
      );
    }
  }

  Future<void> cancelShadowingRecording() async {
    try {
      await _recorder.cancel();
    } finally {
      _store.update((s) => s.copyWith(recordingActive: false, busy: false));
    }
  }

  Future<void> openMicrophoneSettings() => _recorder.openSettings();

  Future<void> deleteCurrentRecording() async {
    final asset = recordingAsset;
    // The delete affordance only renders with a recording present, behind the
    // root api gate; a null here is a stale click, so silence is correct.
    if (!repository.isAvailable || asset == null) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      await repository.deleteRecording(asset.id);
      final deleted = await fileService.deleteIfExists(asset.filePath);
      final cleanupWarning = deleted
          ? null
          : 'Recording metadata was deleted, but the local file could not be '
                'removed';
      _store.update(
        (s) => s.copyWith(
          recordingAsset: null,
          comparison: null,
          attempt: null,
          comparisonWarning: cleanupWarning,
          busy: false,
        ),
      );
    } catch (error) {
      _setError('Could not delete recording');
    }
  }

  Future<void> submit() async {
    final currentItem = item;
    if (!repository.isAvailable || currentItem == null) {
      _setError('Practice item is not ready.');
      return;
    }
    final textAnswer = answer.trim();
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final value = await repository.submitAttempt(
        SubmitPracticeAttempt(
          itemId: currentItem.id,
          textAnswer: textAnswer,
          createReviewItemOnFailure: createReviewOnFailure,
        ),
      );
      _store.update((s) => s.copyWith(attempt: value, busy: false));
    } catch (error) {
      _setError('Practice submission failed');
    }
  }

  Future<void> saveCurrentFailureToReview() async {
    final currentItem = item;
    final currentAttempt = attempt;
    if (!repository.isAvailable ||
        currentItem == null ||
        currentAttempt == null) {
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
      final review = await repository.createReview(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'practice_failure',
            id: currentAttempt.id,
            practiceAttemptId: currentAttempt.id,
            lexicalEntryId: lexicalEntryId,
            mediaId: session?.mediaId,
            trackId: session?.trackId,
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
    } catch (error) {
      _setError('Could not save review item');
    }
  }

  Future<void> _createItemFromDraft({
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
      final session = await _ensureSession(mediaId: mediaId, trackId: trackId);
      final item = await repository.createItem(
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
        _setError('Could not start practice');
      }
    }
  }

  Future<PracticeSession> _ensureSession({
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
    return repository.createSession(
      CreatePracticeSession(
        mode: 'intensive',
        mediaId: mediaId,
        trackId: trackId,
        source: 'current_sentence_practice',
      ),
    );
  }

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
    if (recordingActive) unawaited(_recorder.cancel());
    _store.dispose();
    super.dispose();
  }
}
