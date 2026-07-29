import 'package:flutter/foundation.dart';

import '../models/reading_diff.dart';
import '../models/semantic_task.dart';
import '../services/api_service.dart';
import '../state/store.dart';
import 'reading_task_controller.dart';

const _unset = Object();

/// One side of the read-listen pairing: the rubric (if any), the latest
/// judgment with its corrections applied, and the reduced outcome.
class DiffSide {
  const DiffSide({
    this.rubric,
    this.judgment,
    this.adjudications = const [],
    this.outcome = SideOutcome.unassessed,
  });

  final SemanticRubricView? rubric;
  final SemanticJudgmentView? judgment;
  final List<JudgmentAdjudicationView> adjudications;
  final SideOutcome outcome;
}

class ReadingDiffState {
  const ReadingDiffState({
    this.loading = false,
    this.read = const DiffSide(),
    this.listen = const DiffSide(),
    this.error,
  });

  final bool loading;
  final DiffSide read;
  final DiffSide listen;
  final String? error;

  String get explanationKey => diffExplanationKey(read.outcome, listen.outcome);

  ReadingDiffState copyWith({
    bool? loading,
    DiffSide? read,
    DiffSide? listen,
    Object? error = _unset,
  }) => ReadingDiffState(
    loading: loading ?? this.loading,
    read: read ?? this.read,
    listen: listen ?? this.listen,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

/// Read-side aggregation for the read-listen diff card. Pure consumption of
/// the 3.11 fact family — nothing here writes anything.
class ReadingDiffController extends ChangeNotifier {
  ReadingDiffController() : _store = Store(const ReadingDiffState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ReadingDiffState> _store;

  Store<ReadingDiffState> get store => _store;
  ReadingDiffState get state => _store.state;

  Future<void> loadDiff(LocalApi api, ReadingTaskSource source) async {
    _store.replace(const ReadingDiffState(loading: true));
    try {
      final read = await _loadSide(
        api,
        source,
        ReadingTaskController.readingPurpose,
      );
      final listen = await _loadSide(
        api,
        source,
        ReadingTaskController.listeningPurpose,
      );
      _store.replace(
        ReadingDiffState(loading: false, read: read, listen: listen),
      );
    } catch (error) {
      _store.replace(
        const ReadingDiffState(
          loading: false,
          error: 'This comparison could not be built',
        ),
      );
    }
  }

  void clear() => _store.replace(const ReadingDiffState());

  /// Latest judgment across the rubric's attempts, with its adjudications.
  /// Judgments citing an older rubric version still count for their own
  /// side's coarse outcome — the reduction never compares across rubrics.
  Future<DiffSide> _loadSide(
    LocalApi api,
    ReadingTaskSource source,
    String purpose,
  ) async {
    final rubric = await api.lookupSemanticRubric(
      mediaId: source.mediaId,
      startMs: source.startMs,
      endMs: source.endMs,
      purpose: purpose,
      responseLanguage: source.responseLanguage,
      transcriptSnapshot: source.transcriptSnapshot,
    );
    if (rubric == null) return const DiffSide();

    SemanticJudgmentView? latest;
    for (final attempt in await api.semanticRubricAttempts(rubric.id)) {
      for (final judgment in await api.semanticAttemptJudgments(attempt.id)) {
        if (latest == null || judgment.createdAtMs >= latest.createdAtMs) {
          latest = judgment;
        }
      }
    }
    final adjudications = latest == null
        ? const <JudgmentAdjudicationView>[]
        : await api.judgmentAdjudications(latest.id);
    return DiffSide(
      rubric: rubric,
      judgment: latest,
      adjudications: adjudications,
      outcome: sideOutcome(rubric.points, latest, adjudications),
    );
  }
}
