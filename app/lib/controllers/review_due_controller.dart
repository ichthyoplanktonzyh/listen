import 'package:flutter/foundation.dart';

import '../data/repositories/review_repository.dart';

/// How much the shell knows about the due count right now.
///
/// Four states that must never impersonate one another. "Nobody has asked
/// yet", "the answer is on its way", "the answer is zero" and "asking failed"
/// are four different facts, and only one of them may be drawn as `0`. This
/// is the same rule [ReviewDeckState.overview] already states for the review
/// home; the today pane inherits it because a `?? 0` on any of the other
/// three would quietly invent a fact about the learner's day.
enum ReviewDueStatus { unknown, loading, loaded, failed }

@immutable
class ReviewDueState {
  const ReviewDueState({this.status = ReviewDueStatus.unknown, this.count});

  final ReviewDueStatus status;

  /// Set only when [status] is [ReviewDueStatus.loaded]. Null otherwise —
  /// including on failure, where a stale number would read as current.
  final int? count;

  const ReviewDueState.unknown()
    : status = ReviewDueStatus.unknown,
      count = null;
}

/// The shell's read of "how many cards are waiting", and nothing else.
///
/// Deliberately separate from [ReviewDeckController]: that one is route
/// scoped, built when the review surface opens and disposed when it closes,
/// so the today pane cannot borrow it — the pane has to answer before the
/// learner has been anywhere. This controller owns one number, holds no
/// session, and survives for the life of the shell.
class ReviewDueController extends ChangeNotifier {
  ReviewDueController(this._repository);

  final ReviewRepository _repository;

  ReviewDueState _state = const ReviewDueState.unknown();
  ReviewDueState get state => _state;

  bool _disposed = false;
  int _generation = 0;

  /// Drops back to unknown — used when the core disconnects, so a number read
  /// from the previous session does not linger as if it were current.
  void reset() {
    _generation++;
    _set(const ReviewDueState.unknown());
  }

  Future<void> load() async {
    final generation = ++_generation;
    _set(const ReviewDueState(status: ReviewDueStatus.loading));
    try {
      final overview = await _repository.deckOverview();
      if (_disposed || generation != _generation) return;
      _set(
        ReviewDueState(
          status: ReviewDueStatus.loaded,
          count: overview.dueTotal,
        ),
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _set(const ReviewDueState(status: ReviewDueStatus.failed));
    }
  }

  void _set(ReviewDueState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
