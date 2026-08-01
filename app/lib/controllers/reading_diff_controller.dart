import 'package:flutter/foundation.dart';

import '../models/reading_diff.dart';
import '../models/semantic_task.dart';
import '../data/repositories/reading_task_repository.dart';
import '../state/store.dart';
import 'reading_task_controller.dart';

const _unset = Object();

/// One side of the read-listen pairing: the rubric (if any), the latest
/// judgment with its corrections applied, and the reduced outcome.
class DiffSide {
  DiffSide({
    this.rubric,
    this.judgment,
    List<JudgmentAdjudicationView> adjudications = const [],
    this.outcome = SideOutcome.unassessed,
  }) : _adjudications = List.unmodifiable(adjudications);

  final SemanticRubricView? rubric;
  final SemanticJudgmentView? judgment;
  final List<JudgmentAdjudicationView> _adjudications;
  List<JudgmentAdjudicationView> get adjudications =>
      List.unmodifiable(_adjudications);
  final SideOutcome outcome;
}

class ReadingDiffState {
  ReadingDiffState({
    this.loading = false,
    DiffSide? read,
    DiffSide? listen,
    this.error,
  }) : read = read ?? DiffSide(),
       listen = listen ?? DiffSide();

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
  ReadingDiffController({required this.repository})
    : _store = Store(ReadingDiffState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ReadingDiffState> _store;
  final ReadingTaskRepository repository;

  Store<ReadingDiffState> get store => _store;
  ReadingDiffState get state => _store.state;

  Future<void> loadDiff(ReadingTaskSource source) async {
    _store.replace(ReadingDiffState(loading: true));
    try {
      final read = await _loadSide(
        source,
        ReadingTaskController.readingPurpose,
      );
      final listen = await _loadSide(
        source,
        ReadingTaskController.listeningPurpose,
      );
      _store.replace(
        ReadingDiffState(loading: false, read: read, listen: listen),
      );
    } catch (error) {
      _store.replace(
        ReadingDiffState(
          loading: false,
          error: 'This comparison could not be built',
        ),
      );
    }
  }

  void clear() => _store.replace(ReadingDiffState());

  /// Latest judgment across the rubric's attempts, with its adjudications.
  /// Judgments citing an older rubric version still count for their own
  /// side's coarse outcome — the reduction never compares across rubrics.
  Future<DiffSide> _loadSide(ReadingTaskSource source, String purpose) async {
    final rubric = await repository.lookupRubric(
      mediaId: source.mediaId,
      startMs: source.startMs,
      endMs: source.endMs,
      purpose: purpose,
      responseLanguage: source.responseLanguage,
      transcriptSnapshot: source.transcriptSnapshot,
    );
    if (rubric == null) return DiffSide();

    SemanticJudgmentView? latest;
    for (final attempt in await repository.rubricAttempts(rubric.id)) {
      for (final judgment in await repository.attemptJudgments(attempt.id)) {
        if (latest == null || judgment.createdAtMs >= latest.createdAtMs) {
          latest = judgment;
        }
      }
    }
    final adjudications = latest == null
        ? const <JudgmentAdjudicationView>[]
        : await repository.judgmentAdjudications(latest.id);
    return DiffSide(
      rubric: rubric,
      judgment: latest,
      adjudications: adjudications,
      outcome: sideOutcome(rubric.points, latest, adjudications),
    );
  }
}
