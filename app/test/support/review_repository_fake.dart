import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/models/types.dart';

/// Base for review-repository fakes. Every member throws, so a test overrides
/// exactly the calls its case makes and an unexpected call fails loudly
/// instead of quietly returning an empty success.
///
/// It exists because contract 1.1.0 turned `ReviewRepository` from four
/// methods into thirteen: without a shared base, each fake carried nine stubs
/// of noise that hid which calls the test actually cared about.
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
  Future<AnkiPackageImportSummary> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  }) => throw UnimplementedError('importAnkiPackage');

  @override
  Future<AnkiPackageExportSummary> exportAnkiPackage(
    AnkiPackageExportRequest request,
  ) => throw UnimplementedError('exportAnkiPackage');

  @override
  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions() async => const [];

  @override
  Future<ReviewSubmission> submitRating(String itemId, String rating) =>
      throw UnimplementedError('submitRating');

  @override
  Future<void> resolveUpgradeSuggestion(String id, {required bool confirm}) =>
      throw UnimplementedError('resolveUpgradeSuggestion');

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
