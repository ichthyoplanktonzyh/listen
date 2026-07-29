import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../state/store.dart';

class HuntingState {
  const HuntingState({
    this.targets = const [],
    this.candidates = const [],
    this.busy = false,
    this.error,
  });

  final List<HuntingTarget> targets;
  final List<HuntingCandidate> candidates;
  final bool busy;
  final String? error;

  bool containsLexicalEntry(String id) =>
      targets.any((target) => target.lexicalEntryId == id);

  HuntingState copyWith({
    List<HuntingTarget>? targets,
    List<HuntingCandidate>? candidates,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => HuntingState(
    targets: targets ?? this.targets,
    candidates: candidates ?? this.candidates,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
  );
}

class HuntingController extends ChangeNotifier {
  HuntingController() : _store = Store(const HuntingState()) {
    _store.addListener(notifyListeners);
  }

  final Store<HuntingState> _store;

  Store<HuntingState> get store => _store;
  HuntingState get state => _store.state;

  Future<bool> load(LocalApi api) async {
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      final targets = await api.huntingTargets();
      final candidates = await api.huntingCandidates();
      _store.replace(HuntingState(targets: targets, candidates: candidates));
      return true;
    } catch (error) {
      _store.update(
        (state) =>
            state.copyWith(busy: false, error: 'Could not load hunting list'),
      );
      return false;
    }
  }

  Future<bool> addManual(LocalApi api, LexicalEntry entry) =>
      _create(api, lexicalEntryId: entry.id, sourceKind: 'manual');

  Future<bool> promoteCandidate(LocalApi api, HuntingCandidate candidate) =>
      _create(
        api,
        lexicalEntryId: candidate.lexicalEntryId,
        sourceKind: 'review_candidate',
        sourceId: candidate.id,
      );

  Future<bool> _create(
    LocalApi api, {
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  }) async {
    if (state.busy || state.containsLexicalEntry(lexicalEntryId)) return false;
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      final target = await api.createHuntingTarget(
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
        (state) =>
            state.copyWith(busy: false, error: 'Could not update hunting list'),
      );
      return false;
    }
  }

  Future<bool> archive(LocalApi api, HuntingTarget target) async {
    if (state.busy) return false;
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      await api.archiveHuntingTarget(target.id);
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
        (state) =>
            state.copyWith(busy: false, error: 'Could not update hunting list'),
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
