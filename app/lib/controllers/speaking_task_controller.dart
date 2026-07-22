import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/runtime_resources.dart';
import '../models/semantic_task.dart';
import '../services/api_service.dart';
import '../services/shadowing_recorder.dart';
import '../state/store.dart';

const _unset = Object();

/// Immutable content snapshot carried into one constructed-speaking task.
class SpeakingTaskSource {
  const SpeakingTaskSource({
    required this.anchorCueId,
    this.semanticSentenceId,
    this.mediaId,
    this.trackId,
    required this.startMs,
    required this.endMs,
    required this.language,
    required this.transcriptSnapshot,
    this.audioTranscriptSnapshot,
    this.promptSnapshot,
    this.recall = 'immediate',
    this.sourceMediaPath,
    this.reviewItemId,
  });

  final String anchorCueId;
  final String? semanticSentenceId;
  final String? mediaId;
  final String? trackId;
  final int startMs;
  final int endMs;
  final String language;
  final String transcriptSnapshot;
  final String? audioTranscriptSnapshot;
  final String? promptSnapshot;
  final String recall;
  final String? sourceMediaPath;
  final String? reviewItemId;
}

class SpeakingTaskState {
  const SpeakingTaskState({
    this.phase = 'idle',
    this.kind = SpeakingTaskController.retellingKind,
    this.source,
    this.rubric,
    this.asrModelId,
    this.audioPlayCount = 0,
    this.recordingActive = false,
    this.recording,
    this.audioFacts,
    this.transcription,
    this.rawTranscript = '',
    this.correctedTranscript = '',
    this.asrReliability = 'suspect',
    this.assistance,
    this.attempt,
    this.feedbackProviderId,
    this.llmFeedback,
    this.delayedReviewItemId,
    this.delayedReviewCompleted = false,
    this.confirmedTargetIds = const {},
    this.retryCount = 0,
    this.busy = false,
    this.microphonePermission,
    this.error,
  });

  /// idle | listening | recording | transcribing | reviewing | ready_feedback
  /// | done
  final String phase;
  final String kind;
  final SpeakingTaskSource? source;
  final SemanticRubricView? rubric;
  final String? asrModelId;
  final int audioPlayCount;
  final bool recordingActive;
  final RecordingAsset? recording;
  final RecordingAudioFacts? audioFacts;
  final RecordingTranscriptionJobView? transcription;
  final String rawTranscript;
  final String correctedTranscript;
  final String asrReliability;
  final String? assistance;
  final SemanticAttemptView? attempt;

  /// Optional teacher-style free-text LLM feedback (issue #9): the provider
  /// sees the full source context and answers in prose. Ephemeral assist
  /// only — nothing is persisted and no observation/projection is written.
  final String? feedbackProviderId;
  final String? llmFeedback;
  final String? delayedReviewItemId;
  final bool delayedReviewCompleted;
  final Set<String> confirmedTargetIds;
  final int retryCount;
  final bool busy;
  final MicrophonePermissionStatus? microphonePermission;
  final String? error;

  bool get canRetry => phase == 'done' && retryCount == 0;

  SpeakingTaskState copyWith({
    String? phase,
    String? kind,
    Object? source = _unset,
    Object? rubric = _unset,
    Object? asrModelId = _unset,
    int? audioPlayCount,
    bool? recordingActive,
    Object? recording = _unset,
    Object? audioFacts = _unset,
    Object? transcription = _unset,
    String? rawTranscript,
    String? correctedTranscript,
    String? asrReliability,
    Object? assistance = _unset,
    Object? attempt = _unset,
    Object? feedbackProviderId = _unset,
    Object? llmFeedback = _unset,
    Object? delayedReviewItemId = _unset,
    bool? delayedReviewCompleted,
    Set<String>? confirmedTargetIds,
    int? retryCount,
    bool? busy,
    Object? microphonePermission = _unset,
    Object? error = _unset,
  }) => SpeakingTaskState(
    phase: phase ?? this.phase,
    kind: kind ?? this.kind,
    source: identical(source, _unset)
        ? this.source
        : source as SpeakingTaskSource?,
    rubric: identical(rubric, _unset)
        ? this.rubric
        : rubric as SemanticRubricView?,
    asrModelId: identical(asrModelId, _unset)
        ? this.asrModelId
        : asrModelId as String?,
    audioPlayCount: audioPlayCount ?? this.audioPlayCount,
    recordingActive: recordingActive ?? this.recordingActive,
    recording: identical(recording, _unset)
        ? this.recording
        : recording as RecordingAsset?,
    audioFacts: identical(audioFacts, _unset)
        ? this.audioFacts
        : audioFacts as RecordingAudioFacts?,
    transcription: identical(transcription, _unset)
        ? this.transcription
        : transcription as RecordingTranscriptionJobView?,
    rawTranscript: rawTranscript ?? this.rawTranscript,
    correctedTranscript: correctedTranscript ?? this.correctedTranscript,
    asrReliability: asrReliability ?? this.asrReliability,
    assistance: identical(assistance, _unset)
        ? this.assistance
        : assistance as String?,
    attempt: identical(attempt, _unset)
        ? this.attempt
        : attempt as SemanticAttemptView?,
    feedbackProviderId: identical(feedbackProviderId, _unset)
        ? this.feedbackProviderId
        : feedbackProviderId as String?,
    llmFeedback: identical(llmFeedback, _unset)
        ? this.llmFeedback
        : llmFeedback as String?,
    delayedReviewItemId: identical(delayedReviewItemId, _unset)
        ? this.delayedReviewItemId
        : delayedReviewItemId as String?,
    delayedReviewCompleted:
        delayedReviewCompleted ?? this.delayedReviewCompleted,
    confirmedTargetIds: confirmedTargetIds ?? this.confirmedTargetIds,
    retryCount: retryCount ?? this.retryCount,
    busy: busy ?? this.busy,
    microphonePermission: identical(microphonePermission, _unset)
        ? this.microphonePermission
        : microphonePermission as MicrophonePermissionStatus?,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

/// The Speaking-specific state machine. It owns capture and transcript review,
/// while callers retain playback and hand it audio focus before capture.
class SpeakingTaskController extends ChangeNotifier {
  SpeakingTaskController({
    ShadowingRecorder? recorder,
    Future<void> Function(Duration)? delay,
  }) : _recorder = recorder ?? MacosShadowingRecorder(),
       _delay = delay ?? Future<void>.delayed,
       _store = Store(const SpeakingTaskState()) {
    _store.addListener(notifyListeners);
  }

  static const retellingKind = 'l2_retelling';
  static const patternProductionKind = 'pattern_production';

  final ShadowingRecorder _recorder;
  final Future<void> Function(Duration) _delay;
  final Store<SpeakingTaskState> _store;
  final Map<String, SpeakingTaskState> _drafts = {};
  int _attemptStartedAtMs = 0;
  int _pollGeneration = 0;

  Store<SpeakingTaskState> get store => _store;
  SpeakingTaskState get state => _store.state;

  Future<void> openTask(
    LocalApi api, {
    required SpeakingTaskSource source,
    required List<RubricPointView> fixedRubricPoints,
    String kind = retellingKind,
    String? assistance,
  }) async {
    if (kind != retellingKind && kind != patternProductionKind) {
      throw ArgumentError.value(kind, 'kind', 'unsupported speaking task');
    }
    if (kind == patternProductionKind &&
        (assistance == null ||
            source.promptSnapshot?.trim().isEmpty != false)) {
      throw ArgumentError(
        'Pattern production requires assistance and a prompt snapshot.',
      );
    }
    final draft = _drafts[_draftKey(source, kind, assistance)];
    if (draft != null) {
      _pollGeneration++;
      _store.replace(draft.copyWith(busy: false, error: null));
      return;
    }
    _pollGeneration++;
    _store.replace(
      SpeakingTaskState(
        phase: 'idle',
        kind: kind,
        source: source,
        assistance: kind == patternProductionKind ? assistance : null,
        busy: true,
      ),
    );
    try {
      var rubric = await api.lookupSemanticRubric(
        mediaId: source.mediaId,
        startMs: source.startMs,
        endMs: source.endMs,
        purpose: kind,
        responseLanguage: source.language,
        transcriptSnapshot: source.transcriptSnapshot,
      );
      rubric ??= await api.createSemanticRubric(
        purpose: kind,
        source: RubricSourceView(
          mediaId: source.mediaId,
          trackId: source.trackId,
          startMs: source.startMs,
          endMs: source.endMs,
          language: source.language,
          transcriptSnapshot: source.transcriptSnapshot,
        ),
        responseLanguage: source.language,
        points: fixedRubricPoints,
        provenance: const SemanticProvenanceView(
          kind: 'manual',
          detail: 'Speaking Studio fixed information-point rubric v1',
        ),
      );
      final models = await api.transcriptionModels();
      final model = _selectModel(models, source.language);
      _attemptStartedAtMs = DateTime.now().millisecondsSinceEpoch;
      _store.update(
        (s) => s.copyWith(
          phase: 'listening',
          rubric: rubric,
          asrModelId: model?.id,
          busy: false,
          error: model == null
              ? 'No installed transcription model supports this language.'
              : null,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  void noteSourcePlayback() {
    if (state.phase != 'listening') return;
    _store.update((s) => s.copyWith(audioPlayCount: s.audioPlayCount + 1));
  }

  Future<bool> beginRecording({
    required Future<void> Function() acquireAudioFocus,
  }) async {
    if (state.phase != 'listening' || state.asrModelId == null) return false;
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
            error: 'Microphone permission is required for speaking recording.',
          ),
        );
        return false;
      }
      await acquireAudioFocus();
      await _recorder.start();
      _store.update(
        (s) => s.copyWith(
          phase: 'recording',
          recordingActive: true,
          microphonePermission: permission,
          busy: false,
        ),
      );
      return true;
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
      return false;
    }
  }

  Future<void> stopRecording(LocalApi api) async {
    final source = state.source;
    final modelId = state.asrModelId;
    if (state.phase != 'recording' || source == null || modelId == null) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final captured = await _recorder.stop();
      final asset = await api.createRecordingAsset(
        CreateRecordingAsset(
          filePath: captured.path,
          durationMs: captured.durationMs,
          target: PracticeTarget(
            kind: 'segment',
            startMs: source.startMs,
            endMs: source.endMs,
          ),
          sourceSegment: PlayableSegment(
            mediaId: source.mediaId,
            startMs: source.startMs,
            endMs: source.endMs,
            label: state.kind == patternProductionKind
                ? 'personal expression pattern'
                : 'retelling source',
            subtitleSnapshot:
                source.audioTranscriptSnapshot ?? source.transcriptSnapshot,
            availability: source.mediaId == null
                ? 'missing_media'
                : 'available',
          ),
          language: source.language,
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
      RecordingAudioFacts? audioFacts;
      try {
        audioFacts = await api.recordingAudioFacts(asset.id);
      } catch (_) {
        // Acoustic facts are a non-scoring enhancement; ASR remains usable.
      }
      _store.update(
        (s) => s.copyWith(
          phase: 'transcribing',
          recordingActive: false,
          recording: asset,
          audioFacts: audioFacts,
        ),
      );
      final job = await api.createRecordingTranscription(
        recordingId: asset.id,
        modelId: modelId,
        language: source.language,
      );
      final generation = ++_pollGeneration;
      _store.update(
        (s) => s.copyWith(
          phase: 'transcribing',
          recordingActive: false,
          recording: asset,
          transcription: job,
          busy: false,
        ),
      );
      await _pollTranscription(api, job.id, generation);
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          phase: 'listening',
          recordingActive: false,
          busy: false,
          error: 'Could not save or transcribe recording: $error',
        ),
      );
    }
  }

  Future<void> cancelRecording() async {
    if (!state.recordingActive) return;
    await _recorder.cancel();
    _store.update(
      (s) => s.copyWith(
        phase: 'listening',
        recordingActive: false,
        busy: false,
        error: null,
      ),
    );
  }

  Future<void> cancelTranscription(LocalApi api) async {
    final job = state.transcription;
    if (state.phase != 'transcribing' || job == null) return;
    _pollGeneration++;
    try {
      final cancelled = await api.cancelRecordingTranscription(job.id);
      _store.update(
        (s) => s.copyWith(
          phase: 'listening',
          transcription: cancelled,
          busy: false,
          error: null,
        ),
      );
    } catch (error) {
      final generation = ++_pollGeneration;
      _store.update(
        (s) => s.copyWith(error: 'Could not cancel transcription: $error'),
      );
      unawaited(_pollTranscription(api, job.id, generation));
    }
  }

  void updateCorrectedTranscript(String value) {
    if (state.phase != 'reviewing') return;
    _store.update((s) => s.copyWith(correctedTranscript: value));
  }

  void setAsrReliability(String value) {
    if (state.phase != 'reviewing' ||
        !const {'reliable', 'suspect', 'unreliable'}.contains(value)) {
      return;
    }
    _store.update((s) => s.copyWith(asrReliability: value));
  }

  Future<void> acceptTranscript(LocalApi api) async {
    final source = state.source;
    final rubric = state.rubric;
    final recording = state.recording;
    if (state.phase != 'reviewing' ||
        source == null ||
        rubric == null ||
        recording == null ||
        state.rawTranscript.trim().isEmpty ||
        state.correctedTranscript.trim().isEmpty) {
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final endedAt = DateTime.now().millisecondsSinceEpoch;
      final attempt = await api.createSpokenSemanticAttempt(
        kind: state.kind,
        target: recording.target.toJson(),
        rubricId: rubric.id,
        rubricVersion: rubric.version,
        audioPlayCount: state.audioPlayCount,
        speakingAssistance: state.assistance,
        speakingRecall: source.recall,
        promptSnapshot: state.kind == patternProductionKind
            ? source.promptSnapshot
            : null,
        recordingAssetId: recording.id,
        rawTranscript: state.rawTranscript,
        correctedTranscript: state.correctedTranscript.trim(),
        asrReliability: state.asrReliability,
        responseLanguage: source.language,
        startedAtMs: _attemptStartedAtMs,
        endedAtMs: endedAt,
      );
      _store.update(
        (s) =>
            s.copyWith(phase: 'ready_feedback', attempt: attempt, busy: false),
      );
      // Resolve the (optional) feedback provider now that the attempt exists —
      // the assist entry only appears once there is something to comment on,
      // and the task flow never depends on any provider.
      final providerId = await api.preferredLlmProviderId('semantic_judgment');
      if (providerId != null && state.feedbackProviderId != providerId) {
        _store.update((s) => s.copyWith(feedbackProviderId: providerId));
      }
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  /// Ends the task after the saved-recording stage. There is no rubric
  /// self-assessment (issue #9): the attempt itself, confirmed vocabulary
  /// targets, and the optional LLM feedback are all the task produces.
  void finishTask() {
    if (state.phase != 'ready_feedback') return;
    _store.update((s) => s.copyWith(phase: 'done'));
    final source = state.source;
    if (source != null) {
      _drafts.remove(_draftKey(source, state.kind, state.assistance));
    }
  }

  /// Requests teacher-style free-text feedback on the stored attempt through
  /// the configured provider. The provider sees the source transcript, task
  /// prompt, and learner response; the reply is ephemeral assist — nothing is
  /// stored, and on any provider failure only the error surfaces.
  Future<void> requestLlmFeedback(LocalApi api) async {
    final attempt = state.attempt;
    final providerId = state.feedbackProviderId;
    if (attempt == null || providerId == null) return;
    final response = attempt.responses.single;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final feedback = await api.feedbackViaLlmProvider(
        providerId,
        attemptId: attempt.id,
        responseRevision: response.revision,
      );
      _store.update((s) => s.copyWith(llmFeedback: feedback, busy: false));
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  void retryOnce() {
    if (!state.canRetry) return;
    _attemptStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    _store.update(
      (s) => s.copyWith(
        phase: 'listening',
        recording: null,
        audioFacts: null,
        transcription: null,
        rawTranscript: '',
        correctedTranscript: '',
        asrReliability: 'suspect',
        attempt: null,
        llmFeedback: null,
        delayedReviewItemId: null,
        delayedReviewCompleted: false,
        confirmedTargetIds: const {},
        retryCount: 1,
        error: null,
      ),
    );
  }

  Future<void> scheduleDelayedRetelling(LocalApi api) async {
    final source = state.source;
    final attempt = state.attempt;
    if (state.phase != 'done' ||
        source == null ||
        attempt == null ||
        state.delayedReviewItemId != null) {
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final item = await api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'speaking_attempt',
            id: attempt.id,
            mediaId: source.mediaId,
            trackId: source.trackId,
          ),
          anchors: [
            PracticeAnchor(
              kind: 'sentence',
              id: source.anchorCueId,
              label: source.language,
              sentenceId: source.anchorCueId,
              startMs: source.startMs,
              endMs: source.endMs,
            ),
          ],
          promptSnapshot: source.transcriptSnapshot,
        ),
      );
      _store.update(
        (s) =>
            s.copyWith(delayedReviewItemId: item.id, busy: false, error: null),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  Future<void> completeDelayedReview(LocalApi api, String rating) async {
    final reviewItemId = state.source?.reviewItemId;
    if (state.phase != 'done' ||
        state.source?.recall != 'delayed' ||
        reviewItemId == null ||
        state.delayedReviewCompleted ||
        !const {'again', 'hard', 'good', 'easy'}.contains(rating)) {
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      await api.submitReviewAttempt(reviewItemId, rating);
      _store.update(
        (s) =>
            s.copyWith(delayedReviewCompleted: true, busy: false, error: null),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  Future<void> confirmSpeakingTarget(
    LocalApi api, {
    required String lexicalEntryId,
    required String surfaceForm,
  }) async {
    final attempt = state.attempt;
    final source = state.source;
    if (attempt == null ||
        source == null ||
        !const {'ready_feedback', 'done'}.contains(state.phase) ||
        state.asrReliability == 'unreliable' ||
        state.confirmedTargetIds.contains(lexicalEntryId)) {
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      await api.confirmSpeakingTarget(
        attemptId: attempt.id,
        lexicalEntryId: lexicalEntryId,
        surfaceForm: surfaceForm,
        sentenceId: source.semanticSentenceId ?? source.anchorCueId,
      );
      _store.update(
        (s) => s.copyWith(
          confirmedTargetIds: {...s.confirmedTargetIds, lexicalEntryId},
          busy: false,
          error: null,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  Future<void> openMicrophoneSettings() => _recorder.openSettings();

  Future<void> closeTask([LocalApi? api]) async {
    _pollGeneration++;
    var resumable = state;
    if (state.recordingActive) {
      await _recorder.cancel();
      resumable = resumable.copyWith(
        phase: 'listening',
        recordingActive: false,
        busy: false,
      );
    }
    final transcription = state.transcription;
    if (api != null && state.phase == 'transcribing' && transcription != null) {
      try {
        final cancelled = await api.cancelRecordingTranscription(
          transcription.id,
        );
        resumable = resumable.copyWith(
          phase: 'listening',
          transcription: cancelled,
          busy: false,
          error: null,
        );
      } catch (_) {
        // Exit remains local even if the short-lived runtime job disappeared.
        resumable = resumable.copyWith(
          phase: 'listening',
          busy: false,
          error: 'Transcription stopped when the task closed.',
        );
      }
    }
    final source = resumable.source;
    if (source != null &&
        resumable.phase != 'idle' &&
        resumable.phase != 'done') {
      _drafts[_draftKey(source, resumable.kind, resumable.assistance)] =
          resumable;
    }
    _store.replace(const SpeakingTaskState());
  }

  void discardDraft({
    required SpeakingTaskSource source,
    String kind = retellingKind,
    String? assistance,
  }) {
    _drafts.remove(_draftKey(source, kind, assistance));
  }

  Future<void> _pollTranscription(
    LocalApi api,
    String jobId,
    int generation,
  ) async {
    while (generation == _pollGeneration && state.phase == 'transcribing') {
      await _delay(const Duration(milliseconds: 120));
      if (generation != _pollGeneration || state.phase != 'transcribing') {
        return;
      }
      try {
        final job = await api.recordingTranscriptionJob(jobId);
        if (generation != _pollGeneration) {
          return;
        }
        if (job.status == 'completed') {
          final raw = job.rawTranscript?.trim() ?? '';
          _store.update(
            (s) => s.copyWith(
              phase: raw.isEmpty ? 'listening' : 'reviewing',
              transcription: job,
              rawTranscript: raw,
              correctedTranscript: raw,
              asrReliability: 'suspect',
              error: raw.isEmpty
                  ? 'Transcription completed without readable text.'
                  : null,
            ),
          );
          return;
        }
        if (job.status == 'failed' || job.status == 'cancelled') {
          _store.update(
            (s) => s.copyWith(
              phase: 'listening',
              transcription: job,
              error: job.status == 'failed'
                  ? (job.errorMessage ??
                        'Transcription failed; the recording remains saved.')
                  : null,
            ),
          );
          return;
        }
        _store.update((s) => s.copyWith(transcription: job));
      } catch (error) {
        _store.update(
          (s) => s.copyWith(
            phase: 'listening',
            error: 'Could not read transcription status: $error',
          ),
        );
        return;
      }
    }
  }

  TranscriptionModelView? _selectModel(
    List<TranscriptionModelView> models,
    String language,
  ) {
    final installed = models.where(
      (model) => model.state == 'installed' || model.state == 'custom',
    );
    final needsMultilingual = !language.toLowerCase().startsWith('en');
    for (final model in installed) {
      if (!needsMultilingual || !model.englishOnly) {
        return model;
      }
    }
    return null;
  }

  String _draftKey(
    SpeakingTaskSource source,
    String kind,
    String? assistance,
  ) =>
      '$kind|${source.mediaId}|${source.trackId}|${source.startMs}|'
      '${source.endMs}|${source.semanticSentenceId}|${source.transcriptSnapshot}|${source.promptSnapshot}|'
      '${source.audioTranscriptSnapshot}|${source.recall}|${source.reviewItemId}|'
      '${assistance ?? ''}';
}
