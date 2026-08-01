import 'package:flutter/foundation.dart';

import '../data/repositories/cold_start_marking_repository.dart';
import '../models/types.dart';

@immutable
class ColdStartMarkingState {
  ColdStartMarkingState({
    List<ColdStartWordCandidate> candidates = const [],
    this.currentIndex = 0,
    this.loading = true,
    this.submitting = false,
    this.loadFailed = false,
    this.saveFailed = false,
    this.finished = false,
  }) : _candidates = List.unmodifiable(candidates);

  final List<ColdStartWordCandidate> _candidates;
  List<ColdStartWordCandidate> get candidates => List.unmodifiable(_candidates);
  final int currentIndex;
  final bool loading;
  final bool submitting;
  final bool loadFailed;
  final bool saveFailed;
  final bool finished;

  ColdStartWordCandidate? get current =>
      candidates.isEmpty ? null : candidates[currentIndex];
}

class ColdStartMarkingViewModel extends ChangeNotifier {
  ColdStartMarkingViewModel(
    this._repository, {
    required this.trackId,
    required this.language,
  });

  final ColdStartMarkingRepository _repository;
  final String trackId;
  final String language;
  ColdStartMarkingState _state = ColdStartMarkingState();
  int _generation = 0;
  bool _disposed = false;

  ColdStartMarkingState get state => _state;

  Future<void> load() async {
    final generation = ++_generation;
    _publish(ColdStartMarkingState());
    try {
      final candidates = await _repository.loadCandidates(trackId);
      if (!_isCurrent(generation)) return;
      _publish(
        ColdStartMarkingState(
          candidates: List.unmodifiable(candidates),
          loading: false,
        ),
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _publish(ColdStartMarkingState(loading: false, loadFailed: true));
    }
  }

  Future<void> mark(String status) async {
    final candidate = _state.current;
    if (_state.submitting || candidate == null || _state.finished) return;
    final generation = ++_generation;
    _publish(
      ColdStartMarkingState(
        candidates: _state.candidates,
        currentIndex: _state.currentIndex,
        loading: false,
        submitting: true,
      ),
    );
    var saveFailed = false;
    try {
      await _repository.saveMark(
        candidate: candidate,
        status: status,
        language: language,
      );
    } catch (_) {
      saveFailed = true;
    }
    if (!_isCurrent(generation)) return;
    _advance(saveFailed: saveFailed);
  }

  void skip() {
    if (_state.submitting || _state.finished || _state.current == null) return;
    _generation += 1;
    _advance();
  }

  void finish() {
    if (_state.finished) return;
    _generation += 1;
    _publish(
      ColdStartMarkingState(
        candidates: _state.candidates,
        currentIndex: _state.currentIndex,
        loading: false,
        saveFailed: _state.saveFailed,
        finished: true,
      ),
    );
  }

  void _advance({bool saveFailed = false}) {
    final nextIndex = _state.currentIndex + 1;
    final finished = nextIndex >= _state.candidates.length;
    _publish(
      ColdStartMarkingState(
        candidates: _state.candidates,
        currentIndex: finished ? _state.currentIndex : nextIndex,
        loading: false,
        saveFailed: saveFailed,
        finished: finished,
      ),
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _publish(ColdStartMarkingState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
