import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

abstract interface class MediaSessionRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);
  Future<void> saveProgress(String mediaId, Duration position);
  Future<MediaItem> registerMedia(String path);
  Future<Duration?> readProgress(String mediaId);
  Future<SubtitleTrack> importSubtitle(String mediaId, String path);
  Future<SubtitleTrack> importTimeline({
    required String mediaId,
    required Map<String, dynamic> document,
    required bool allowMismatch,
  });
}

class LocalMediaSessionRepository implements MediaSessionRepository {
  LocalMediaSessionRepository(this._getApi);
  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Media session API is unavailable'));
  @override
  bool get isAvailable => _getApi() != null;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<void> saveProgress(String mediaId, Duration position) =>
      _api.saveProgress(mediaId, position);
  @override
  Future<MediaItem> registerMedia(String path) => _api.registerMedia(path);
  @override
  Future<Duration?> readProgress(String mediaId) => _api.readProgress(mediaId);
  @override
  Future<SubtitleTrack> importSubtitle(String mediaId, String path) =>
      _api.importSubtitle(mediaId, path);
  @override
  Future<SubtitleTrack> importTimeline({
    required String mediaId,
    required Map<String, dynamic> document,
    required bool allowMismatch,
  }) => _api.importLLTimelineForMedia(
    mediaId,
    document,
    allowMismatch: allowMismatch,
  );
}
