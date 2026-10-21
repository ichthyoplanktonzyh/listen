import 'package:flutter/foundation.dart';

import '../data/repositories/review_repository.dart';
import '../models/review_deck.dart';
import '../state/store.dart';

class ReviewDeckState {
  const ReviewDeckState({
    this.overview,
    this.busy = false,
    this.savingLimits = false,
    this.error,
  });

  final ReviewDeckOverview? overview;
  final bool busy;
  final bool savingLimits;
  final String? error;

  ReviewDeckState copyWith({
    ReviewDeckOverview? overview,
    bool? busy,
    bool? savingLimits,
    String? error,
    bool clearError = false,
  }) => ReviewDeckState(
    overview: overview ?? this.overview,
    busy: busy ?? this.busy,
    savingLimits: savingLimits ?? this.savingLimits,
    error: clearError ? null : error ?? this.error,
  );
}

/// Owns the listening review overview and its daily budget.
class ReviewDeckController extends ChangeNotifier {
  ReviewDeckController(this._repository)
    : _store = Store(const ReviewDeckState()) {
    _store.addListener(notifyListeners);
  }

  final ReviewRepository _repository;
  final Store<ReviewDeckState> _store;
  bool _disposed = false;
  int _loadGeneration = 0;

  Store<ReviewDeckState> get store => _store;
  ReviewDeckState get state => _store.state;

  void _set(ReviewDeckState Function(ReviewDeckState) update) {
    if (_disposed) return;
    _store.update(update);
  }

  Future<bool> load() async {
    final generation = ++_loadGeneration;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final overview = await _repository.deckOverview();
      if (_disposed || generation != _loadGeneration) return false;
      _set((state) => state.copyWith(overview: overview, busy: false));
      return true;
    } catch (_) {
      if (_disposed || generation != _loadGeneration) return false;
      _set(
        (state) => state.copyWith(busy: false, error: 'Could not load review decks'),
      );
      return false;
    }
  }

  Future<bool> updateDailyLimits(ReviewDailyLimits limits) async {
    if (state.savingLimits) return false;
    _set((state) => state.copyWith(savingLimits: true, clearError: true));
    try {
      await _repository.updateDailyLimits(limits);
      if (_disposed) return false;
      _set((state) => state.copyWith(savingLimits: false));
      return load();
    } catch (_) {
      _set(
        (state) => state.copyWith(
          savingLimits: false,
          error: 'Could not save the daily limits',
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _store.dispose();
    super.dispose();
  }
}
