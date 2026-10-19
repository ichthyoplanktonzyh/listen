import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/review_repository.dart';
import '../models/practice.dart';
import '../models/review_deck.dart';
import '../state/store.dart';

class ReviewState {
  ReviewState({
    List<ReviewQueueEntry> queue = const [],
    this.index = 0,
    this.revealed = false,
    this.busy = false,
    this.completedCount = 0,
    List<UpgradeSuggestion> upgradeSuggestions = const [],
    List<ReviewIntervalPreview> previews = const [],
    this.limitStatus,
    this.customStudy,
    this.advancesNormalSchedule,
    this.error,
  }) : _queue = List.unmodifiable(queue),
       _upgradeSuggestions = List.unmodifiable(upgradeSuggestions),
       _previews = List.unmodifiable(previews);

  final List<ReviewQueueEntry> _queue;
  List<ReviewQueueEntry> get queue => List.unmodifiable(_queue);
  final int index;
  final bool revealed;
  final bool busy;
  final int completedCount;
  final List<UpgradeSuggestion> _upgradeSuggestions;
  List<UpgradeSuggestion> get upgradeSuggestions =>
      List.unmodifiable(_upgradeSuggestions);

  /// FSRS's prediction for each rating on the *current* card, empty whenever
  /// the prediction has not arrived or could not be fetched. Empty means the
  /// grades render without previews rather than with invented ones.
  final List<ReviewIntervalPreview> _previews;
  List<ReviewIntervalPreview> get previews => List.unmodifiable(_previews);

  /// Today's budget as the backend last reported it. Null until a queue has
  /// loaded — the finished screen must not claim a limit it has not been told
  /// about.
  final ReviewLimitStatus? limitStatus;

  /// Set when this session is a custom-study round rather than the day's
  /// schedule; grades then go to the custom-study endpoint.
  final CustomStudyRequest? customStudy;

  /// Whether grading this custom-study round moves the real schedule. Only
  /// meaningful alongside [customStudy].
  final bool? advancesNormalSchedule;
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
    List<ReviewIntervalPreview>? previews,
    ReviewLimitStatus? limitStatus,
    CustomStudyRequest? customStudy,
    bool? advancesNormalSchedule,
    String? error,
    bool clearError = false,
  }) => ReviewState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    revealed: revealed ?? this.revealed,
    busy: busy ?? this.busy,
    completedCount: completedCount ?? this.completedCount,
    upgradeSuggestions: upgradeSuggestions ?? this.upgradeSuggestions,
    previews: previews ?? this.previews,
    limitStatus: limitStatus ?? this.limitStatus,
    customStudy: customStudy ?? this.customStudy,
    advancesNormalSchedule:
        advancesNormalSchedule ?? this.advancesNormalSchedule,
    error: clearError ? null : error ?? this.error,
  );
}

class ReviewController extends ChangeNotifier {
  ReviewController(this._repository) : _store = Store(ReviewState()) {
    _store.addListener(notifyListeners);
  }

  final ReviewRepository _repository;
  final Store<ReviewState> _store;
  bool _disposed = false;
  int _loadGeneration = 0;
  int _previewGeneration = 0;

  Store<ReviewState> get store => _store;
  ReviewState get state => _store.state;
  ReviewQueueEntry? get current => state.current;

  void _set(ReviewState Function(ReviewState) update) {
    if (_disposed) return;
    _store.update(update);
  }

  /// Loads the day's queue. The backend clips it to the daily budget and
  /// returns the budget status, so a short queue can be explained instead of
  /// looking like an empty one.
  Future<bool> load({int limit = 20}) async {
    final generation = ++_loadGeneration;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final queue = await _repository.queue(limit: limit);
      List<UpgradeSuggestion> suggestions;
      try {
        suggestions = await _repository.pendingUpgradeSuggestions();
      } catch (_) {
        suggestions = const [];
      }
      if (_disposed || generation != _loadGeneration) return false;
      _store.replace(
        ReviewState(
          queue: queue.entries,
          busy: false,
          completedCount: 0,
          upgradeSuggestions: suggestions,
          limitStatus: queue.limitStatus,
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

  /// Starts a one-shot custom-study round. It replaces the queue in this
  /// controller but is a different kind of session: grades are submitted to
  /// the custom-study endpoint, and [ReviewState.advancesNormalSchedule]
  /// records whether the backend says it touches the real schedule.
  Future<bool> loadCustomStudy(CustomStudyRequest request) async {
    final generation = ++_loadGeneration;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final queue = await _repository.customStudy(request);
      if (_disposed || generation != _loadGeneration) return false;
      _store.replace(
        ReviewState(
          queue: queue.entries,
          busy: false,
          customStudy: request,
          advancesNormalSchedule: queue.advancesNormalSchedule,
        ),
      );
      return true;
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return false;
      _set(
        (state) =>
            state.copyWith(busy: false, error: 'Could not load custom study'),
      );
      return false;
    }
  }

  void reveal() {
    if (state.current == null) return;
    _set((state) => state.copyWith(revealed: true, clearError: true));
    // The previews belong to the answer side of the card, so they are fetched
    // when it flips. A failure is silent on purpose: the grades still work,
    // they just carry no prediction.
    unawaited(_loadPreviews());
  }

  Future<void> _loadPreviews() async {
    final entry = state.current;
    if (entry == null) return;
    final generation = ++_previewGeneration;
    try {
      final previews = await _repository.intervalPreview(entry.item.id);
      if (_disposed || generation != _previewGeneration) return;
      // Guard against the answer landing after the learner moved on.
      if (state.current?.item.id != entry.item.id) return;
      _set((state) => state.copyWith(previews: previews));
    } catch (_) {
      if (_disposed || generation != _previewGeneration) return;
      _set((state) => state.copyWith(previews: const []));
    }
  }

  Future<bool> rate(String rating) async {
    final current = state.current;
    if (current == null || state.busy) return false;
    _set((state) => state.copyWith(busy: true, clearError: true));
    final customStudy = state.customStudy;
    try {
      final submission = customStudy == null
          ? await _repository.submitRating(current.item.id, rating)
          : await _repository.submitCustomStudyRating(
              itemId: current.item.id,
              rating: rating,
              request: customStudy,
            );
      _previewGeneration++;
      _set(
        (state) => state.copyWith(
          index: state.index + 1,
          revealed: false,
          busy: false,
          previews: const [],
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
    _previewGeneration++;
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
