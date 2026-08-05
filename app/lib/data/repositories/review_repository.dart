import '../../models/practice.dart';
import '../../models/review_deck.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';
import 'occurrence_media_repository.dart';

/// Narrow backend boundary for the review queue and its source media.
abstract interface class ReviewRepository implements OccurrenceMediaRepository {
  Future<ReviewQueue> queue({int limit = 20});

  /// FSRS's prediction for all four ratings on one card. No schedule is
  /// written; this is a read.
  Future<List<ReviewIntervalPreview>> intervalPreview(String itemId);

  Future<ReviewDeckOverview> deckOverview();

  Future<ReviewDailyLimits> dailyLimits();

  Future<ReviewDailyLimits> updateDailyLimits(ReviewDailyLimits limits);

  Future<CustomStudyQueue> customStudy(CustomStudyRequest request);

  Future<ReviewSubmission> submitCustomStudyRating({
    required String itemId,
    required String rating,
    required CustomStudyRequest request,
  });

  Future<AnkiPackageImportSummary> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  });

  Future<AnkiPackageExportSummary> exportAnkiPackage(
    AnkiPackageExportRequest request,
  );

  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions();

  Future<ReviewSubmission> submitRating(String itemId, String rating);

  Future<void> resolveUpgradeSuggestion(String id, {required bool confirm});
}

class LocalReviewRepository implements ReviewRepository {
  LocalReviewRepository(this._api);

  final LocalApi _api;

  @override
  Future<ReviewQueue> queue({int limit = 20}) =>
      _api.reviewQueue(limit: limit);

  @override
  Future<List<ReviewIntervalPreview>> intervalPreview(String itemId) =>
      _api.reviewIntervalPreview(itemId);

  @override
  Future<ReviewDeckOverview> deckOverview() => _api.reviewDeckOverview();

  @override
  Future<ReviewDailyLimits> dailyLimits() => _api.reviewDailyLimits();

  @override
  Future<ReviewDailyLimits> updateDailyLimits(ReviewDailyLimits limits) =>
      _api.updateReviewDailyLimits(limits);

  @override
  Future<CustomStudyQueue> customStudy(CustomStudyRequest request) =>
      _api.customStudy(request);

  @override
  Future<ReviewSubmission> submitCustomStudyRating({
    required String itemId,
    required String rating,
    required CustomStudyRequest request,
  }) => _api.submitCustomStudyAttempt(
    itemId: itemId,
    rating: rating,
    request: request,
  );

  @override
  Future<AnkiPackageImportSummary> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  }) => _api.importAnkiPackage(
    packagePath: packagePath,
    mediaDirectory: mediaDirectory,
  );

  @override
  Future<AnkiPackageExportSummary> exportAnkiPackage(
    AnkiPackageExportRequest request,
  ) => _api.exportAnkiPackage(request);

  @override
  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions() =>
      _api.upgradeSuggestions();

  @override
  Future<ReviewSubmission> submitRating(String itemId, String rating) =>
      _api.submitReviewAttempt(itemId, rating);

  @override
  Future<void> resolveUpgradeSuggestion(
    String id, {
    required bool confirm,
  }) async {
    if (confirm) {
      await _api.confirmUpgradeSuggestion(id);
    } else {
      await _api.rejectUpgradeSuggestion(id);
    }
  }

  @override
  Future<MediaItem> readMedia(String mediaId) => _api.readMedia(mediaId);

  @override
  Future<String> fingerprintFile(String path) => _api.fingerprintFile(path);

  @override
  Future<void> registerMedia(String path) async {
    await _api.registerMedia(path);
  }
}
