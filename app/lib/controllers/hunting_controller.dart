import 'package:flutter/foundation.dart';

import '../data/repositories/hunting_repository.dart';
import '../models/named_failure.dart';
import '../models/practice.dart';
import '../models/types.dart';
import '../state/store.dart';

class HuntingState {
  HuntingState({
    List<HuntingTarget> targets = const [],
    List<HuntingCandidate> candidates = const [],
    this.busy = false,
    this.error,
  }) : _targets = List.unmodifiable(targets),
       _candidates = List.unmodifiable(candidates);

  final List<HuntingTarget> _targets;
  List<HuntingTarget> get targets => List.unmodifiable(_targets);
  final List<HuntingCandidate> _candidates;
  List<HuntingCandidate> get candidates => List.unmodifiable(_candidates);
  final bool busy;
  final NamedFailure? error;

  bool containsLexicalEntry(String id) =>
      targets.any((target) => target.lexicalEntryId == id);

  HuntingState copyWith({
    List<HuntingTarget>? targets,
    List<HuntingCandidate>? candidates,
    bool? busy,
    NamedFailure? error,
    bool clearError = false,
  }) => HuntingState(
    targets: targets ?? this.targets,
    candidates: candidates ?? this.candidates,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
  );
}

class HuntingController extends ChangeNotifier {
  factory HuntingController({
    HuntingRepository repository = const UnavailableHuntingRepository(),
  }) => HuntingController._(repository);

  HuntingController._(this._repository) : _store = Store(HuntingState()) {
    _store.addListener(notifyListeners);
  }

  final Store<HuntingState> _store;
  final HuntingRepository _repository;

  Store<HuntingState> get store => _store;
  HuntingState get state => _store.state;

  Future<bool> load() async {
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      final targets = await _repository.targets();
      final candidates = await _repository.candidates();
      _store.replace(HuntingState(targets: targets, candidates: candidates));
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: NamedFailure(
            'huntingLoadFailed',
            detail: huntingFailureDetail(error),
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> addManual(LexicalEntry entry) =>
      _create(lexicalEntryId: entry.id, sourceKind: 'manual');

  Future<bool> promoteCandidate(HuntingCandidate candidate) => _create(
    lexicalEntryId: candidate.lexicalEntryId,
    sourceKind: 'review_candidate',
    sourceId: candidate.id,
  );

  Future<bool> _create({
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  }) async {
    if (state.busy || state.containsLexicalEntry(lexicalEntryId)) return false;
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      final target = await _repository.createTarget(
        lexicalEntryId: lexicalEntryId,
        sourceKind: sourceKind,
        sourceId: sourceId,
      );
      _store.update(
        (state) => state.copyWith(
          busy: false,
          targets: [...state.targets, target],
          candidates: sourceId == null
              ? state.candidates
              : state.candidates
                    .where((candidate) => candidate.id != sourceId)
                    .toList(growable: false),
        ),
      );
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: NamedFailure(
            'huntingUpdateFailed',
            detail: huntingFailureDetail(error),
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> archive(HuntingTarget target) async {
    if (state.busy) return false;
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      await _repository.archiveTarget(target.id);
      _store.update(
        (state) => state.copyWith(
          busy: false,
          targets: state.targets
              .where((value) => value.id != target.id)
              .toList(growable: false),
        ),
      );
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: NamedFailure(
            'huntingUpdateFailed',
            detail: huntingFailureDetail(error),
          ),
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
