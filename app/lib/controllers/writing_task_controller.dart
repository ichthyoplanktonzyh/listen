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
    this.selfVerdicts = const {},
    this.selfAssessment,
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
  final Map<String, String> selfVerdicts;
  final SemanticJudgmentView? selfAssessment;
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
    Map<String, String>? selfVerdicts,
    Object? selfAssessment = _unset,
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
    selfVerdicts: selfVerdicts ?? this.selfVerdicts,
    selfAssessment: identical(selfAssessment, _unset)
        ? this.selfAssessment
        : selfAssessment as SemanticJudgmentView?,
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
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
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
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
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
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
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

  void setSelfVerdict(String pointId, String verdict) {
    if (!const {'covered', 'partial', 'missing'}.contains(verdict)) return;
    _store.update(
      (s) => s.copyWith(selfVerdicts: {...s.selfVerdicts, pointId: verdict}),
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
      SemanticJudgmentView? selfAssessment;
      if (rubric.points.isNotEmpty &&
          rubric.points.every(
            (point) => state.selfVerdicts.containsKey(point.pointId),
          )) {
        final charCount = revised.runes.length;
        selfAssessment = await api.createSemanticJudgment(
          attemptId: attempt.id,
          responseRevision: 2,
          rubricId: rubric.id,
          rubricVersion: rubric.version,
          rubricTranscriptSnapshot: source.transcriptSnapshot,
          responseTranscript: revised,
          points: [
            for (final point in rubric.points)
              PointJudgmentView(
                pointId: point.pointId,
                verdict: state.selfVerdicts[point.pointId]!,
                supportingSpans: switch (state.selfVerdicts[point.pointId]!) {
                  'covered' || 'partial' => [
                    ResponseSpanView(startChar: 0, endChar: charCount),
                  ],
                  _ => const [],
                },
              ),
          ],
          provenance: const SemanticProvenanceView(
            kind: 'manual',
            detail: 'writing studio learner self-assessment',
          ),
          evidenceClass: 'self_assessment',
        );
      }
      _store.update(
        (s) => s.copyWith(
          phase: 'done',
          revisedAttempt: attempt,
          selfAssessment: selfAssessment,
          busy: false,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
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
