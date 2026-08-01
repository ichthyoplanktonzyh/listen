import 'package:flutter/foundation.dart';

import '../data/repositories/review_repository.dart';
import '../models/practice.dart';
import '../state/store.dart';

class ReviewState {
  const ReviewState({
    this.queue = const [],
    this.index = 0,
    this.revealed = false,
    this.busy = false,
    this.completedCount = 0,
    this.upgradeSuggestions = const [],
    this.error,
  });

  final List<ReviewQueueEntry> queue;
  final int index;
  final bool revealed;
  final bool busy;
  final int completedCount;
  final List<UpgradeSuggestion> upgradeSuggestions;
  final String? error;

  ReviewQueueEntry? get current => index < queue.length ? queue[index] : null;
  int get remaining => queue.length - index;
  bool get finished => !busy && current == null;

  ReviewState copyWith({
    List<ReviewQueueEntry>? queue,
    int? index,
    bool? revealed,
    bool? busy,
    int? completedCount,
    List<UpgradeSuggestion>? upgradeSuggestions,
    String? error,
    bool clearError = false,
  }) => ReviewState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    revealed: revealed ?? this.revealed,
    busy: busy ?? this.busy,
    completedCount: completedCount ?? this.completedCount,
    upgradeSuggestions: upgradeSuggestions ?? this.upgradeSuggestions,
    error: clearError ? null : error ?? this.error,
  );
}

class ReviewController extends ChangeNotifier {
  ReviewController(this._repository) : _store = Store(const ReviewState()) {
    _store.addListener(notifyListeners);
  }

  final ReviewRepository _repository;
  final Store<ReviewState> _store;
  bool _disposed = false;
  int _loadGeneration = 0;

  Store<ReviewState> get store => _store;
  ReviewState get state => _store.state;
  ReviewQueueEntry? get current => state.current;

  void _set(ReviewState Function(ReviewState) update) {
    if (_disposed) return;
    _store.update(update);
  }

  Future<bool> load({int limit = 20}) async {
    final generation = ++_loadGeneration;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final queue = await _repository.dueItems(limit: limit);
      List<UpgradeSuggestion> suggestions;
      try {
        suggestions = await _repository.pendingUpgradeSuggestions();
      } catch (_) {
        suggestions = const [];
      }
      if (_disposed || generation != _loadGeneration) return false;
      _store.replace(
        ReviewState(
          queue: queue,
          busy: false,
          completedCount: 0,
          upgradeSuggestions: suggestions,
        ),
      );
      return true;
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return false;
      _set(
        (state) =>
            state.copyWith(busy: false, error: 'Could not load review queue'),
      );
      return false;
    }
  }

  void reveal() => _set(
    (state) => state.current == null
        ? state
        : state.copyWith(revealed: true, clearError: true),
  );

  Future<bool> rate(String rating) async {
    final current = state.current;
    if (current == null || state.busy) return false;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final submission = await _repository.submitRating(
        current.item.id,
        rating,
      );
      _set(
        (state) => state.copyWith(
          index: state.index + 1,
          revealed: false,
          busy: false,
          completedCount: state.completedCount + 1,
          upgradeSuggestions: _mergeSuggestions(
            state.upgradeSuggestions,
            submission.upgradeSuggestions,
          ),
        ),
      );
      return true;
    } catch (error) {
      _set(
        (state) =>
            state.copyWith(busy: false, error: 'Could not save review result'),
      );
      return false;
    }
  }

  Future<bool> resolveUpgradeSuggestion(
    String id, {
    required bool confirm,
  }) async {
    if (state.busy) return false;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      await _repository.resolveUpgradeSuggestion(id, confirm: confirm);
      _set(
        (state) => state.copyWith(
          busy: false,
          upgradeSuggestions: state.upgradeSuggestions
              .where((value) => value.id != id)
              .toList(growable: false),
        ),
      );
      return true;
    } catch (error) {
      _set(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not update recognition status',
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _store.dispose();
    super.dispose();
  }
}

List<UpgradeSuggestion> _mergeSuggestions(
  List<UpgradeSuggestion> current,
  List<UpgradeSuggestion> incoming,
) {
  final byId = {for (final value in current) value.id: value};
  for (final value in incoming) {
    byId[value.id] = value;
  }
  return byId.values.toList(growable: false);
}
