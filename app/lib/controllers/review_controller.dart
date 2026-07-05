import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../services/api_service.dart';
import '../state/store.dart';

class ReviewState {
  const ReviewState({
    this.queue = const [],
    this.index = 0,
    this.revealed = false,
    this.busy = false,
    this.completedCount = 0,
    this.error,
  });

  final List<ReviewQueueEntry> queue;
  final int index;
  final bool revealed;
  final bool busy;
  final int completedCount;
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
    String? error,
    bool clearError = false,
  }) => ReviewState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    revealed: revealed ?? this.revealed,
    busy: busy ?? this.busy,
    completedCount: completedCount ?? this.completedCount,
    error: clearError ? null : error ?? this.error,
  );
}

class ReviewController extends ChangeNotifier {
  ReviewController() : _store = Store(const ReviewState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ReviewState> _store;

  Store<ReviewState> get store => _store;
  ReviewState get state => _store.state;
  ReviewQueueEntry? get current => state.current;

  Future<bool> load(LocalApi api, {int limit = 20}) async {
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      final queue = await api.dueReviewItems(limit: limit);
      _store.replace(ReviewState(queue: queue, busy: false, completedCount: 0));
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not load review queue: $error',
        ),
      );
      return false;
    }
  }

  void reveal() => _store.update(
    (state) => state.current == null
        ? state
        : state.copyWith(revealed: true, clearError: true),
  );

  Future<bool> rate(LocalApi api, String rating) async {
    final current = state.current;
    if (current == null || state.busy) return false;
    _store.update((state) => state.copyWith(busy: true, clearError: true));
    try {
      await api.submitReviewAttempt(current.item.id, rating);
      _store.update(
        (state) => state.copyWith(
          index: state.index + 1,
          revealed: false,
          busy: false,
          completedCount: state.completedCount + 1,
        ),
      );
      return true;
    } catch (error) {
      _store.update(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not save review result: $error',
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
