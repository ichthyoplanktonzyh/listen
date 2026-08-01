import '../../models/types.dart';
import '../../services/api_service.dart';

/// Data operations needed to locate and re-link occurrence media.
abstract interface class OccurrenceMediaRepository {
  Future<MediaItem> readMedia(String mediaId);
  Future<String> fingerprintFile(String path);
  Future<void> registerMedia(String path);
}

final class LocalOccurrenceMediaRepository
    implements OccurrenceMediaRepository {
  LocalOccurrenceMediaRepository(this._api);

  final LocalApi _api;

  @override
  Future<MediaItem> readMedia(String mediaId) => _api.readMedia(mediaId);

  @override
  Future<String> fingerprintFile(String path) => _api.fingerprintFile(path);

  @override
  Future<void> registerMedia(String path) async {
    await _api.registerMedia(path);
  }
}
