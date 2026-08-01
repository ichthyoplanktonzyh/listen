import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../services/api_service.dart';

abstract interface class ManualReviewRepository {
  ApiFailure failureDetail(Object error);
  Future<WordTimeline> wordTimeline(String id);
  Future<void> saveTimeline(String trackId, Map<String, dynamic> payload);
}

final class LocalManualReviewRepository implements ManualReviewRepository {
  const LocalManualReviewRepository(this._api);
  final LocalApi _api;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<WordTimeline> wordTimeline(String id) => _api.wordTimeline(id);
  @override
  Future<void> saveTimeline(
    String trackId,
    Map<String, dynamic> payload,
  ) async {
    await _api.createTrackWordTimeline(trackId, payload);
  }
}
