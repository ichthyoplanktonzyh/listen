import 'package:flutter/foundation.dart';

import '../models/semantic_task.dart';
import '../services/api_service.dart';
import '../state/store.dart';

const _unset = Object();

/// Everything the task flow needs to know about the paragraph being tasked.
/// Times are media-time milliseconds (subtitle offset already applied) so
/// the rubric source matches slice playback and survives track re-imports.
class ReadingTaskSource {
  const ReadingTaskSource({
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

class ReadingTaskState {
  const ReadingTaskState({
    this.phase = 'idle',
    this.purpose = ReadingTaskController.readingPurpose,
    this.source,
    this.rubric,
    this.draftPoints = const [],
    this.draftAnswer = '',
    this.attempt,
    this.judgment,
    this.draftVerdicts = const {},
    this.adjudications = const [],
    this.judgeProviderId,
    this.rubricProviderId,
    this.llmJudgment,
    this.llmAdjudications = const [],
    this.pastAttemptCount = 0,
    this.busy = false,
    this.error,
  });

  /// idle | editing | answering | assessing | done
  final String phase;

  /// `reading_comprehension` (text visible) or `l1_retelling` (listen-only).
  final String purpose;
  final ReadingTaskSource? source;

  bool get isListening => purpose == ReadingTaskController.listeningPurpose;
  final SemanticRubricView? rubric;

  /// Editable template points before the rubric exists (editing phase).
  final List<RubricPointView> draftPoints;
  final String draftAnswer;
  final SemanticAttemptView? attempt;
  final SemanticJudgmentView? judgment;

  /// point_id → verdict picked so far during self-assessment.
  final Map<String, String> draftVerdicts;
  final List<JudgmentAdjudicationView> adjudications;

  /// Phase 3.12.2: an optional LLM judgment shown as correctable assist. It
  /// never replaces the manual self-assessment; both are stored, honest
  /// `heuristic_proxy` rows that write no observation/projection.
  final String? judgeProviderId;

  /// Provider allowed for rubric generation (`rubric_generation`), if any.
  final String? rubricProviderId;
  final SemanticJudgmentView? llmJudgment;
  final List<JudgmentAdjudicationView> llmAdjudications;
  final int pastAttemptCount;
  final bool busy;
  final String? error;

  bool get allPointsJudged =>
      rubric != null &&
      rubric!.points.every((point) => draftVerdicts.containsKey(point.pointId));

  ReadingTaskState copyWith({
    String? phase,
    String? purpose,
    Object? source = _unset,
    Object? rubric = _unset,
    List<RubricPointView>? draftPoints,
    String? draftAnswer,
    Object? attempt = _unset,
    Object? judgment = _unset,
    Map<String, String>? draftVerdicts,
    List<JudgmentAdjudicationView>? adjudications,
    Object? judgeProviderId = _unset,
    Object? rubricProviderId = _unset,
    Object? llmJudgment = _unset,
    List<JudgmentAdjudicationView>? llmAdjudications,
    int? pastAttemptCount,
    bool? busy,
    Object? error = _unset,
  }) => ReadingTaskState(
    phase: phase ?? this.phase,
    purpose: purpose ?? this.purpose,
    source: identical(source, _unset)
        ? this.source
        : source as ReadingTaskSource?,
    rubric: identical(rubric, _unset)
        ? this.rubric
        : rubric as SemanticRubricView?,
    draftPoints: draftPoints ?? this.draftPoints,
    draftAnswer: draftAnswer ?? this.draftAnswer,
    attempt: identical(attempt, _unset)
        ? this.attempt
        : attempt as SemanticAttemptView?,
    judgment: identical(judgment, _unset)
        ? this.judgment
        : judgment as SemanticJudgmentView?,
    draftVerdicts: draftVerdicts ?? this.draftVerdicts,
    adjudications: adjudications ?? this.adjudications,
    judgeProviderId: identical(judgeProviderId, _unset)
        ? this.judgeProviderId
        : judgeProviderId as String?,
    rubricProviderId: identical(rubricProviderId, _unset)
        ? this.rubricProviderId
        : rubricProviderId as String?,
    llmJudgment: identical(llmJudgment, _unset)
        ? this.llmJudgment
        : llmJudgment as SemanticJudgmentView?,
    llmAdjudications: llmAdjudications ?? this.llmAdjudications,
    pastAttemptCount: pastAttemptCount ?? this.pastAttemptCount,
    busy: busy ?? this.busy,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

/// Paragraph-task flow for the Reading Studio (Phase 3.13): manual rubric +
/// typed answer + per-point self-assessment, all through the 3.11 semantic
/// fact family. No path here writes observations or projections — the
/// attempt/judgment/adjudication rows are the only durable output.
class ReadingTaskController extends ChangeNotifier {
  ReadingTaskController() : _store = Store(const ReadingTaskState()) {
    _store.addListener(notifyListeners);
  }

  static const readingPurpose = 'reading_comprehension';
  static const listeningPurpose = 'l1_retelling';
  static const evidenceClass = 'self_assessment';

  final Store<ReadingTaskState> _store;
  int _answerStartedAtMs = 0;

  /// Set when the current draft points came from an AI rubric draft, so a save
  /// records honest `llm` provenance instead of `manual`.
  SemanticProvenanceView? _aiRubricProvenance;
  final Map<String, List<RubricPointView>> _pointDrafts = {};
  final Map<String, String> _answerDrafts = {};

  Store<ReadingTaskState> get store => _store;
  ReadingTaskState get state => _store.state;

  /// Opens the task flow for one paragraph: reuses the existing rubric when
  /// the segment already has one, otherwise enters template editing.
  /// [templatePoints] is the localized preset the user can edit. [purpose]
  /// picks the channel: reading (text visible) or listening retell.
  Future<void> openTask(
    LocalApi api, {
    required ReadingTaskSource source,
    required List<RubricPointView> templatePoints,
    String purpose = readingPurpose,
  }) async {
    final draftKey = _draftKey(source, purpose);
    _aiRubricProvenance = null;
    _store.replace(
      ReadingTaskState(
        phase: 'idle',
        purpose: purpose,
        source: source,
        draftAnswer: _answerDrafts[draftKey] ?? '',
        busy: true,
      ),
    );
    try {
      final rubric = await api.lookupSemanticRubric(
        mediaId: source.mediaId,
        startMs: source.startMs,
        endMs: source.endMs,
        purpose: purpose,
        responseLanguage: source.responseLanguage,
        transcriptSnapshot: source.transcriptSnapshot,
      );
      if (rubric == null) {
        final points = _pointDrafts[draftKey] ?? templatePoints;
        _store.update(
          (s) => s.copyWith(phase: 'editing', draftPoints: points, busy: false),
        );
      } else {
        final attempts = await api.semanticRubricAttempts(rubric.id);
        _enterAnswering(rubric, attempts.length);
      }
      await _resolveProviders(api);
    } catch (error) {
      _store.update(
        (s) => s.copyWith(phase: 'idle', busy: false, error: '$error'),
      );
    }
  }

  /// Resolves the (optional) providers allowed for rubric generation and
  /// semantic judgment, preferring ones with a stored credential. A
  /// provider-listing failure is swallowed: the manual template + self-
  /// assessment path never depends on any provider, and the AI entries simply
  /// stay hidden when nothing is configured.
  Future<void> _resolveProviders(LocalApi api) async {
    try {
      final providers = await api.llmProviders();
      _store.update(
        (s) => s.copyWith(
          judgeProviderId: pickLlmProviderId(providers, 'semantic_judgment'),
          rubricProviderId: pickLlmProviderId(providers, 'rubric_generation'),
        ),
      );
    } catch (_) {
      // A provider-listing failure must not break the task flow.
    }
  }

  /// Phase 3.12.2: asks the configured provider to draft rubric points for the
  /// current source and loads them into the editable template. The suggestion
  /// is never auto-applied — it becomes a rubric only when the user saves it,
  /// and the save then records honest `llm` provenance.
  Future<void> generateRubric(LocalApi api) async {
    final source = state.source;
    final providerId = state.rubricProviderId;
    if (source == null || providerId == null) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final draft = await api.generateRubricViaLlmProvider(
        providerId,
        purpose: state.purpose,
        sourceLanguage: source.sourceLanguage,
        responseLanguage: source.responseLanguage,
        transcriptSnapshot: source.transcriptSnapshot,
      );
      if (draft.points.isEmpty) {
        _store.update(
          (s) => s.copyWith(busy: false, error: 'no rubric points returned'),
        );
        return;
      }
      _aiRubricProvenance = SemanticProvenanceView(
        kind: 'llm',
        detail: 'reading studio paragraph task (AI-generated, user-reviewed)',
        modelId: draft.modelId,
        promptVersion: draft.promptVersion,
        schemaVersion: draft.schemaVersion,
      );
      _cachePointDraft(draft.points);
      _store.update(
        (s) => s.copyWith(
          phase: 'editing',
          draftPoints: draft.points,
          busy: false,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  void updateDraftPoint(int index, RubricPointView point) {
    final points = [...state.draftPoints];
    if (index < 0 || index >= points.length) return;
    points[index] = point;
    _cachePointDraft(points);
    _store.update((s) => s.copyWith(draftPoints: points));
  }

  void removeDraftPoint(int index) {
    final points = [...state.draftPoints];
    if (index < 0 || index >= points.length || points.length <= 1) return;
    points.removeAt(index);
    _cachePointDraft(points);
    _store.update((s) => s.copyWith(draftPoints: points));
  }

  void updateAnswerDraft(String value) {
    final source = state.source;
    if (source == null) return;
    _answerDrafts[_draftKey(source, state.purpose)] = value;
    _store.update((s) => s.copyWith(draftAnswer: value));
  }

  /// Saves the edited template as rubric version 1. On a concurrent 409 the
  /// existing rubric is fetched instead — never two identities for one
  /// segment.
  Future<void> saveRubric(LocalApi api) async {
    final source = state.source;
    if (source == null || state.draftPoints.isEmpty) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final rubric = await api.createSemanticRubric(
        purpose: state.purpose,
        source: RubricSourceView(
          mediaId: source.mediaId,
          trackId: source.trackId,
          startMs: source.startMs,
          endMs: source.endMs,
          language: source.sourceLanguage,
          transcriptSnapshot: source.transcriptSnapshot,
        ),
        responseLanguage: source.responseLanguage,
        points: state.draftPoints,
        provenance:
            _aiRubricProvenance ??
            const SemanticProvenanceView(
              kind: 'manual',
              detail: 'reading studio paragraph task (user-edited template)',
            ),
      );
      _enterAnswering(rubric, 0);
    } catch (_) {
      // Most likely a version conflict from a concurrent save; the lookup
      // either recovers the existing rubric or surfaces the original error.
      final recovered = await _tryLookup(api, source);
      if (recovered != null) {
        _enterAnswering(recovered, 0);
      } else {
        _store.update(
          (s) => s.copyWith(busy: false, error: 'rubric save failed'),
        );
      }
    }
  }

  /// Records the typed answer as a completed attempt. Conditions are honest
  /// per channel: reading has the text visible, the listening retell has it
  /// hidden; [audioPlayCount] is the actual replay count either way.
  Future<void> submitAnswer(
    LocalApi api,
    String answer, {
    int audioPlayCount = 0,
  }) async {
    final source = state.source;
    final rubric = state.rubric;
    final purpose = state.purpose;
    final trimmed = answer.trim();
    if (source == null || rubric == null || trimmed.isEmpty) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final attempt = await api.createSemanticAttempt(
        kind: purpose,
        target: {
          'kind': 'segment',
          'id': null,
          'sentence_id': null,
          'chunk_id': null,
          'start_ms': source.startMs,
          'end_ms': source.endMs,
        },
        rubricId: rubric.id,
        rubricVersion: rubric.version,
        sourceTextVisible: !state.isListening,
        audioPlayCount: audioPlayCount,
        l1Trigger: state.isListening ? 'user_requested' : null,
        responseTranscript: trimmed,
        responseLanguage: source.responseLanguage,
        startedAtMs: _answerStartedAtMs,
        endedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _store.update(
        (s) => s.copyWith(
          phase: 'assessing',
          attempt: attempt,
          draftVerdicts: const {},
          llmJudgment: null,
          llmAdjudications: const [],
          busy: false,
        ),
      );
      _answerDrafts.remove(_draftKey(source, purpose));
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  void setVerdict(String pointId, String verdict) {
    _store.update(
      (s) => s.copyWith(draftVerdicts: {...s.draftVerdicts, pointId: verdict}),
    );
  }

  /// Saves the per-point self-assessment as a manual judgment. Covered and
  /// partial verdicts cite the whole response as their span — this is a
  /// self-report, not citation evidence, and the provenance says so.
  Future<void> submitSelfAssessment(LocalApi api) async {
    final rubric = state.rubric;
    final attempt = state.attempt;
    if (rubric == null || attempt == null || !state.allPointsJudged) return;
    final response = attempt.responses.single;
    // Rust validates spans against chars().count(): Unicode scalar values,
    // which is Dart's rune count, not UTF-16 length.
    final charCount = response.transcript.runes.length;
    final points = [
      for (final point in rubric.points)
        PointJudgmentView(
          pointId: point.pointId,
          verdict: state.draftVerdicts[point.pointId]!,
          supportingSpans: switch (state.draftVerdicts[point.pointId]!) {
            'covered' ||
            'partial' => [ResponseSpanView(startChar: 0, endChar: charCount)],
            _ => const [],
          },
        ),
    ];
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final judgment = await api.createSemanticJudgment(
        attemptId: attempt.id,
        responseRevision: response.revision,
        rubricId: rubric.id,
        rubricVersion: rubric.version,
        rubricTranscriptSnapshot: rubric.source.transcriptSnapshot,
        responseTranscript: response.transcript,
        points: points,
        provenance: const SemanticProvenanceView(
          kind: 'manual',
          detail: 'reading self-assessment; spans default to whole response',
        ),
        evidenceClass: evidenceClass,
      );
      _store.update(
        (s) => s.copyWith(phase: 'done', judgment: judgment, busy: false),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  /// Appends a correction for one point of the saved judgment. The original
  /// judgment is never rewritten (3.11 adjudication semantics).
  Future<void> adjudicate(
    LocalApi api, {
    required String pointId,
    required String userVerdict,
    String? note,
  }) async {
    final judgment = state.judgment;
    final prior = judgment?.verdictFor(pointId);
    if (judgment == null || prior == null || prior == userVerdict) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final adjudication = await api.createJudgmentAdjudication(
        judgmentId: judgment.id,
        pointId: pointId,
        priorVerdict: prior,
        userVerdict: userVerdict,
        note: note,
      );
      _store.update(
        (s) => s.copyWith(
          adjudications: [...s.adjudications, adjudication],
          busy: false,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  /// Phase 3.12.2: judges the current answer through the configured provider
  /// and shows the result as correctable assist. The judgment is recorded
  /// server-side as a `heuristic_proxy` (no observation/projection). On any
  /// provider failure nothing is stored and the error surfaces — the manual
  /// path is unaffected.
  Future<void> requestLlmJudgment(LocalApi api) async {
    final attempt = state.attempt;
    final providerId = state.judgeProviderId;
    if (attempt == null || providerId == null) return;
    final response = attempt.responses.single;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final judgment = await api.judgeViaLlmProvider(
        providerId,
        attemptId: attempt.id,
        responseRevision: response.revision,
      );
      _store.update(
        (s) => s.copyWith(
          llmJudgment: judgment,
          llmAdjudications: const [],
          busy: false,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  /// Corrects one point of the LLM judgment. Mirrors [adjudicate]: the stored
  /// judgment row is never rewritten; the correction is an append-only
  /// adjudication citing the LLM judgment id.
  Future<void> adjudicateLlm(
    LocalApi api, {
    required String pointId,
    required String userVerdict,
    String? note,
  }) async {
    final judgment = state.llmJudgment;
    final prior = judgment?.verdictFor(pointId);
    if (judgment == null || prior == null || prior == userVerdict) return;
    _store.update((s) => s.copyWith(busy: true, error: null));
    try {
      final adjudication = await api.createJudgmentAdjudication(
        judgmentId: judgment.id,
        pointId: pointId,
        priorVerdict: prior,
        userVerdict: userVerdict,
        note: note,
      );
      _store.update(
        (s) => s.copyWith(
          llmAdjudications: [...s.llmAdjudications, adjudication],
          busy: false,
        ),
      );
    } catch (error) {
      _store.update((s) => s.copyWith(busy: false, error: '$error'));
    }
  }

  void closeTask() {
    _store.replace(const ReadingTaskState());
  }

  void _cachePointDraft(List<RubricPointView> points) {
    final source = state.source;
    if (source == null) return;
    _pointDrafts[_draftKey(source, state.purpose)] = List.unmodifiable(points);
  }

  String _draftKey(ReadingTaskSource source, String purpose) =>
      '$purpose|${source.mediaId}|${source.trackId}|${source.startMs}|${source.endMs}';

  void _enterAnswering(SemanticRubricView rubric, int pastAttemptCount) {
    _answerStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    _store.update(
      (s) => s.copyWith(
        phase: 'answering',
        rubric: rubric,
        pastAttemptCount: pastAttemptCount,
        busy: false,
        error: null,
      ),
    );
  }

  Future<SemanticRubricView?> _tryLookup(
    LocalApi api,
    ReadingTaskSource source,
  ) async {
    try {
      return await api.lookupSemanticRubric(
        mediaId: source.mediaId,
        startMs: source.startMs,
        endMs: source.endMs,
        purpose: state.purpose,
        responseLanguage: source.responseLanguage,
        transcriptSnapshot: source.transcriptSnapshot,
      );
    } catch (_) {
      return null;
    }
  }
}
