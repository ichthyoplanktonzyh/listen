import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/models/types.dart';

/// Base for review-repository fakes. Every member throws, so a test overrides
/// exactly the calls its case makes and an unexpected call fails loudly
/// instead of quietly returning an empty success.
///
/// Each test overrides only the calls its case makes, while an unexpected
/// call still fails loudly instead of quietly returning an empty success.
abstract class FakeReviewRepositoryBase implements ReviewRepository {
  @override
  Future<ReviewQueue> queue({int limit = 20}) =>
      throw UnimplementedError('queue');

  @override
  Future<List<ReviewIntervalPreview>> intervalPreview(String itemId) =>
      throw UnimplementedError('intervalPreview');

  @override
  Future<ReviewDeckOverview> deckOverview() =>
      throw UnimplementedError('deckOverview');

  @override
  Future<ReviewDailyLimits> dailyLimits() =>
      throw UnimplementedError('dailyLimits');

  @override
  Future<ReviewDailyLimits> updateDailyLimits(ReviewDailyLimits limits) =>
      throw UnimplementedError('updateDailyLimits');

  @override
  Future<CustomStudyQueue> customStudy(CustomStudyRequest request) =>
      throw UnimplementedError('customStudy');

  @override
  Future<ReviewSubmission> submitCustomStudyRating({
    required String itemId,
    required String rating,
    required CustomStudyRequest request,
  }) => throw UnimplementedError('submitCustomStudyRating');

  @override
  Future<ReviewSubmission> submitRating(String itemId, String rating) =>
      throw UnimplementedError('submitRating');

  @override
  Future<MediaItem> readMedia(String mediaId) =>
      throw UnimplementedError('readMedia');

  @override
  Future<String> fingerprintFile(String path) =>
      throw UnimplementedError('fingerprintFile');

  @override
  Future<void> registerMedia(String path) =>
      throw UnimplementedError('registerMedia');
}

/// An empty budget status: nothing done, nothing capped. The default for
/// fixtures whose case is not about limits.
ReviewLimitStatus fakeLimitStatus({
  int newCards = 20,
  int reviews = 200,
  int newCompleted = 0,
  int reviewsCompleted = 0,
  bool newLimitReached = false,
  bool reviewLimitReached = false,
}) => ReviewLimitStatus(
  limits: ReviewDailyLimits(newCards: newCards, reviews: reviews),
  newCompleted: newCompleted,
  reviewsCompleted: reviewsCompleted,
  newLimitReached: newLimitReached,
  reviewLimitReached: reviewLimitReached,
);
