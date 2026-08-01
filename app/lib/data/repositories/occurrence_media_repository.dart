import '../../models/types.dart';

/// Data operations needed to locate and re-link occurrence media.
abstract interface class OccurrenceMediaRepository {
  Future<MediaItem> readMedia(String mediaId);
  Future<String> fingerprintFile(String path);
  Future<void> registerMedia(String path);
}
