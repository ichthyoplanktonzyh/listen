import '../../models/practice.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';
import 'occurrence_media_repository.dart';

/// Narrow backend boundary for the review queue and its source media.
abstract interface class ReviewRepository implements OccurrenceMediaRepository {
  Future<List<ReviewQueueEntry>> dueItems({int limit = 20});

  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions();

  Future<ReviewSubmission> submitRating(String itemId, String rating);

  Future<void> resolveUpgradeSuggestion(String id, {required bool confirm});
}

class LocalReviewRepository implements ReviewRepository {
  LocalReviewRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<ReviewQueueEntry>> dueItems({int limit = 20}) =>
      _api.dueReviewItems(limit: limit);

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
