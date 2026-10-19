import '../../models/api_failure.dart';
import '../../models/reading.dart';
import '../../services/api_service.dart';

/// Data boundary for reading-cursor persistence and learner-language context.
abstract interface class ReadingSessionRepository {
  bool get isAvailable;

  Future<ReadingPositionView?> readingPosition(String trackId);

  Future<void> saveReadingPosition({
    required String trackId,
    required String? mediaId,
    required String anchorCueId,
    required int paragraphIndex,
  });

  Future<String?> learnerL1Language();
}

class ReadingSessionRepositoryFailure implements Exception {
  const ReadingSessionRepositoryFailure(this.detail);

  final ApiFailure detail;
}

class LocalReadingSessionRepository implements ReadingSessionRepository {
  LocalReadingSessionRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Reading session API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw ReadingSessionRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<ReadingPositionView?> readingPosition(String trackId) =>
      _request((api) => api.readingPosition(trackId));

  @override
  Future<void> saveReadingPosition({
    required String trackId,
    required String? mediaId,
    required String anchorCueId,
    required int paragraphIndex,
  }) => _request(
    (api) => api.saveReadingPosition(
      trackId: trackId,
      mediaId: mediaId,
      anchorCueId: anchorCueId,
      paragraphIndex: paragraphIndex,
    ),
  );

  @override
  Future<String?> learnerL1Language() =>
      _request((api) async => (await api.learnerProfile()).l1Language);
}
