import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/semantic_task.dart';
import '../services/api_service.dart';
import '../state/store.dart';

const _unset = Object();

class WritingTaskSource {
  const WritingTaskSource({
    required this.anchorCueId,
    this.mediaId,
    this.trackId,
    required this.startMs,
    required this.endMs,
    required this.sourceLanguage,
    required this.responseLanguage,
    required this.transcriptSnapshot,
  });

  final String anchorCueId;
  final String? mediaId;
  final String? trackId;
  final int startMs;
  final int endMs;
  final String sourceLanguage;
  final String responseLanguage;
  final String transcriptSnapshot;
}

class WritingTaskState {
  const WritingTaskState({
    this.phase = 'idle',
    this.kind = WritingTaskController.summaryKind,
    this.promptSnapshot = '',
    this.source,
    this.rubric,
    this.draft = '',
    this.revisionDraft = '',
    this.initialAttempt,
    this.revisedAttempt,
    this.findings = const [],
    this.decisions = const {},
    this.feedbackProviderId,
    this.llmFeedback,
    this.pastAttempts = const [],
    this.pastAttemptCount = 0,
    this.busy = false,
    this.error,
  });

  /// idle | drafting | submitted | revising | done
  final String phase;
  final String kind;
  final String promptSnapshot;
  final WritingTaskSource? source;
  final SemanticRubricView? rubric;
  final String draft;
  final String revisionDraft;
  final SemanticAttemptView? initialAttempt;
  final SemanticAttemptView? revisedAttempt;
  final List<WritingFeedbackFindingView> findings;

  /// finding id → accepted/rejected. Acceptance is persisted only after the
  /// learner submits the revised text; provider text is never applied here.
  final Map<String, String> decisions;

  /// Optional teacher-style free-text LLM feedback (issue #9), distinct from
  /// the Harper surface findings. The provider sees the full source context
  /// and answers in prose; nothing is persisted and no observation/projection
  /// is written.
  final String? feedbackProviderId;
  final String? llmFeedback;
  final List<SemanticAttemptView> pastAttempts;
  final int pastAttemptCount;
  final bool busy;
  final String? error;

  WritingTaskState copyWith({
    String? phase,
    String? kind,
    String? promptSnapshot,
    Object? source = _unset,
    Object? rubric = _unset,
    String? draft,
    String? revisionDraft,
    Object? initialAttempt = _unset,
    Object? revisedAttempt = _unset,
    List<WritingFeedbackFindingView>? findings,
    Map<String, String>? decisions,
    Object? feedbackProviderId = _unset,
    Object? llmFeedback = _unset,
    List<SemanticAttemptView>? pastAttempts,
    int? pastAttemptCount,
    bool? busy,
    Object? error = _unset,
  }) => WritingTaskState(
    phase: phase ?? this.phase,
    kind: kind ?? this.kind,
    promptSnapshot: promptSnapshot ?? this.promptSnapshot,
    source: identical(source, _unset)
        ? this.source
        : source as WritingTaskSource?,
    rubric: identical(rubric, _unset)
        ? this.rubric
        : rubric as SemanticRubricView?,
    draft: draft ?? this.draft,
    revisionDraft: revisionDraft ?? this.revisionDraft,
    initialAttempt: identical(initialAttempt, _unset)
        ? this.initialAttempt
        : initialAttempt as SemanticAttemptView?,
    revisedAttempt: identical(revisedAttempt, _unset)
        ? this.revisedAttempt
        : revisedAttempt as SemanticAttemptView?,
    findings: findings ?? this.findings,
    decisions: decisions ?? this.decisions,
    feedbackProviderId: identical(feedbackProviderId, _unset)
        ? this.feedbackProviderId
        : feedbackProviderId as String?,
    llmFeedback: identical(llmFeedback, _unset)
        ? this.llmFeedback
        : llmFeedback as String?,
    pastAttempts: pastAttempts ?? this.pastAttempts,
    pastAttemptCount: pastAttemptCount ?? this.pastAttemptCount,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

/// Editor-owned Writing lifecycle. The controller records immutable attempts,
/// revision-bound feedback, and explicit learner dispositions only. It has no
/// learning-observation or capability-projection dependency.
class WritingTaskController extends ChangeNotifier {
  WritingTaskController() : _store = Store(const WritingTaskState()) {
    _store.addListener(notifyListeners);
  }

  static const summaryKind = 'summary';
  static const oneSentenceSummaryKind = 'one_sentence_summary';
  static const opinionKind = 'opinion_response';
  static const dictoglossKind = 'dictogloss';

  final Store<WritingTaskState> _store;
  final Map<String, String> _drafts = {};
  LocalApi? _api;
  Timer? _draftSaveTimer;
  int _startedAtMs = 0;

  Store<WritingTaskState> get store => _store;
  WritingTaskState get state => _store.state;

  Future<void> openTask(
    LocalApi api, {
    required WritingTaskSource source,
    required String kind,
    required String promptSnapshot,
    required List<RubricPointView> fixedRubricPoints,
  }) async {
    _draftSaveTimer?.cancel();
    await _persistDraft();
    _api = api;
    final key = _draftKey(source, kind, promptSnapshot);
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _store.replace(
      WritingTaskState(
        phase: 'idle',
        kind: kind,
        promptSnapshot: promptSnapshot,
        source: source,
        draft: _drafts[key] ?? '',
        busy: true,
      ),
    );
    try {
      var rubric = await _lookup(api, source, kind);
      if (rubric == null) {
        try {
          rubric = await api.createSemanticRubric(
            purpose: kind,
            source: RubricSourceView(
              mediaId: source.mediaId,
              trackId: source.trackId,
              startMs: source.startMs,
              endMs: source.endMs,
              language: source.sourceLanguage,
              transcriptSnapshot: source.transcriptSnapshot,
            ),
            responseLanguage: source.responseLanguage,
            points: fixedRubricPoints,
            provenance: const SemanticProvenanceView(
              kind: 'manual',
              detail: 'writing studio fixed task rubric',
            ),
          );
        } catch (_) {
          rubric = await _lookup(api, source, kind);
          if (rubric == null) rethrow;
        }
      }
      final attempts = await api.semanticRubricAttempts(rubric.id);
      final durableDraft = await api.writingDraft(rubric.id);
      var latestSubmissionMs = 0;
      for (final attempt in attempts) {
        final endedAt = attempt.endedAtMs ?? attempt.startedAtMs;
        if (endedAt > latestSubmissionMs) latestSubmissionMs = endedAt;
      }
      final durableIsNewer =
          durableDraft != null &&
          durableDraft.promptSnapshot == promptSnapshot &&
          durableDraft.updatedAtMs > latestSubmissionMs;
      final restoredDraft = durableIsNewer
          ? durableDraft.transcript
          : _drafts[key] ?? '';
      if (restoredDraft.isNotEmpty) _drafts[key] = restoredDraft;
      _store.update(
        (s) => s.copyWith(
          phase: 'drafting',
          rubric: rubric,
          draft: restoredDraft,
          pastAttemptCount: attempts.length,
          pastAttempts: attempts,
          busy: false,
        ),
      );
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          busy: false,
          error: 'This writing task could not be opened',
        ),
      );
    }
  }

  void updateDraft(String value) {
    final source = state.source;
    if (source == null || state.phase != 'drafting') return;
    _drafts[_draftKey(source, state.kind, state.promptSnapshot)] = value;
    _store.update((s) => s.copyWith(draft: value));
    _draftSaveTimer?.cancel();
    if (value.trim().isNotEmpty) {
      _draftSaveTimer = Timer(const Duration(milliseconds: 600), _persistDraft);
    }
  }

  Future<void> submitDraft(LocalApi api, {int? audioPlayCount}) async {
    final source = state.source;
    final rubric = state.rubric;
    final text = state.draft.trim();
    if (source == null || rubric == null || text.isEmpty) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final attempt = await api.createWritingAttempt(
        kind: state.kind,
        target: _target(source),
        rubricId: rubric.id,
        rubricVersion: rubric.version,
        sourceTextVisible: state.kind != dictoglossKind,
        audioPlayCount: state.kind == dictoglossKind
            ? (audioPlayCount ?? 0)
            : null,
        promptSnapshot: state.promptSnapshot,
        revisions: [text],
        responseLanguage: source.responseLanguage,
        startedAtMs: _startedAtMs,
        endedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _drafts.remove(_draftKey(source, state.kind, state.promptSnapshot));
      _draftSaveTimer?.cancel();
      try {
        await api.deleteWritingDraft(rubric.id);
      } catch (_) {
        // The immutable attempt is authoritative. A stale scratch row is
        // harmless and will be replaced by the next deliberate edit.
      }
      _store.update(
        (s) => s.copyWith(
          phase: 'submitted',
          draft: text,
          revisionDraft: text,
          initialAttempt: attempt,
          busy: false,
        ),
      );
      // Resolve the (optional) feedback provider now that an attempt exists —
      // the assist entry only appears once there is something to comment on,
      // and the task flow never depends on any provider.
      final providerId = await api.preferredLlmProviderId('semantic_judgment');
      if (providerId != null && state.feedbackProviderId != providerId) {
        _store.update((s) => s.copyWith(feedbackProviderId: providerId));
      }
    } catch (error) {
      _store.update(
        (s) =>
            s.copyWith(busy: false, error: 'Your draft could not be submitted'),
      );
    }
  }

  /// Requests teacher-style free-text feedback on the latest stored attempt
  /// (distinct from Harper surface findings). The provider sees the source
  /// transcript, task prompt, and learner text; the reply is ephemeral assist
  /// — nothing is stored, and on any provider failure only the error
  /// surfaces.
  Future<void> requestLlmFeedback(LocalApi api) async {
    final attempt = state.revisedAttempt ?? state.initialAttempt;
    final providerId = state.feedbackProviderId;
    if (attempt == null || providerId == null) return;
    final response = attempt.responses.last;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final feedback = await api.feedbackViaLlmProvider(
        providerId,
        attemptId: attempt.id,
        responseRevision: response.revision,
      );
      _store.update((s) => s.copyWith(llmFeedback: feedback, busy: false));
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          busy: false,
          error: 'Feedback for this draft could not be generated',
        ),
      );
    }
  }

  Future<void> requestLocalFeedback(LocalApi api) async {
    final attempt = state.initialAttempt;
    if (attempt == null) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final findings = await api.generateLocalWritingFindings(attempt.id, 1);
      _store.update(
        (s) => s.copyWith(
          phase: 'revising',
          findings: findings,
          revisionDraft: s.draft,
          busy: false,
        ),
      );
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          busy: false,
          error: 'Local feedback for this draft is unavailable',
        ),
      );
    }
  }

  void startRevisionWithoutFeedback() {
    if (state.initialAttempt == null) return;
    _store.update((s) => s.copyWith(phase: 'revising', revisionDraft: s.draft));
  }

  void updateRevision(String value) {
    if (state.phase != 'revising') return;
    _store.update((s) => s.copyWith(revisionDraft: value));
  }

  void decide(String findingId, String decision) {
    if (decision != 'accepted' && decision != 'rejected') return;
    _store.update(
      (s) => s.copyWith(decisions: {...s.decisions, findingId: decision}),
    );
  }

  Future<void> submitRevision(LocalApi api, {int? audioPlayCount}) async {
    final source = state.source;
    final rubric = state.rubric;
    final original = state.draft.trim();
    final revised = state.revisionDraft.trim();
    if (source == null ||
        rubric == null ||
        original.isEmpty ||
        revised.isEmpty) {
      return;
    }
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final attempt = await api.createWritingAttempt(
        kind: state.kind,
        target: _target(source),
        rubricId: rubric.id,
        rubricVersion: rubric.version,
        sourceTextVisible: state.kind != dictoglossKind,
        audioPlayCount: state.kind == dictoglossKind
            ? (audioPlayCount ?? 0)
            : null,
        promptSnapshot: state.promptSnapshot,
        revisions: [original, revised],
        responseLanguage: source.responseLanguage,
        startedAtMs: now,
        endedAtMs: now + 1,
      );
      for (final finding in state.findings) {
        final decision = state.decisions[finding.id];
        if (decision == null) continue;
        await api.createWritingDisposition(
          findingId: finding.id,
          decision: decision,
          resultingAttemptId: decision == 'accepted' ? attempt.id : null,
          resultingRevision: decision == 'accepted' ? 2 : null,
        );
      }
      // Any earlier LLM feedback cited the initial attempt's revision; the
      // revised attempt gets a fresh, honest request instead of a carry-over.
      _store.update(
        (s) => s.copyWith(
          phase: 'done',
          revisedAttempt: attempt,
          llmFeedback: null,
          busy: false,
        ),
      );
    } catch (error) {
      _store.update(
        (s) => s.copyWith(
          busy: false,
          error: 'Your revision could not be submitted',
        ),
      );
    }
  }

  void closeTask() {
    _draftSaveTimer?.cancel();
    unawaited(_persistDraft());
    _store.replace(const WritingTaskState());
  }

  Future<void> _persistDraft() async {
    final api = _api;
    final rubric = state.rubric;
    final transcript = state.draft.trim();
    if (api == null ||
        rubric == null ||
        transcript.isEmpty ||
        state.phase != 'drafting') {
      return;
    }
    try {
      await api.saveWritingDraft(
        rubricId: rubric.id,
        promptSnapshot: state.promptSnapshot,
        transcript: transcript,
      );
    } catch (_) {
      // The in-memory cache remains available; the next edit retries durable
      // crash recovery without turning a draft write into a task failure.
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    super.dispose();
  }

  Future<SemanticRubricView?> _lookup(
    LocalApi api,
    WritingTaskSource source,
    String kind,
  ) => api.lookupSemanticRubric(
    mediaId: source.mediaId,
    startMs: source.startMs,
    endMs: source.endMs,
    purpose: kind,
    responseLanguage: source.responseLanguage,
    transcriptSnapshot: source.transcriptSnapshot,
  );

  Map<String, dynamic> _target(WritingTaskSource source) => {
    'kind': 'segment',
    'id': null,
    'sentence_id': null,
    'chunk_id': null,
    'start_ms': source.startMs,
    'end_ms': source.endMs,
  };

  String _draftKey(WritingTaskSource source, String kind, String prompt) =>
      '${source.mediaId}:${source.trackId}:${source.anchorCueId}:$kind:$prompt';
}
