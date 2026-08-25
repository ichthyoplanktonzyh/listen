import '../../models/api_failure.dart';
import '../../models/saved_vocabulary_count.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

abstract interface class MediaLibraryRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);

  Future<SavedVocabularyCount> savedVocabularyCount({required String language});
  Future<List<MediaLibraryEntry>> listMediaLibrary();
  Future<MediaItem> readMedia(String mediaId);

  /// The registered media with [mediaId], or null when Core holds no such
  /// media.
  ///
  /// Distinct from [listMediaLibrary], which is the Personal Library
  /// projection and therefore lists retained media only. Media registered as
  /// Temporary Material — an opened file, a scanned folder, an adopted
  /// download — is readable here and absent there, so a caller asking "does
  /// Core still know this media" must ask this and not the library listing.
  ///
  /// Null is Core's definitive "no such media". A lookup that could not be
  /// made throws, so a broken connection is never reported as an absence.
  Future<MediaItem?> findRegisteredMedia(String mediaId);
  Future<MediaLibraryEntry> setTriageIntent(String mediaId, String? intent);
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  });
}

class LocalMediaLibraryRepository implements MediaLibraryRepository {
  LocalMediaLibraryRepository(this._getApi);

  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Media library API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) => _api.savedVocabularyCount(language: language);
  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() => _api.listMediaLibrary();
  @override
  Future<MediaItem> readMedia(String mediaId) => _api.readMedia(mediaId);
  @override
  Future<MediaItem?> findRegisteredMedia(String mediaId) async {
    try {
      return await _api.readMedia(mediaId);
    } catch (error) {
      // Only Core's typed not-found is an absence. Anything else — transport,
      // an unreadable envelope, a core that went away mid-request — is a
      // lookup that did not happen, and answering "gone" for it would let a
      // caller delete its own record of a file that is still there.
      if (describeApiFailure(error).code == 'not_found') return null;
      rethrow;
    }
  }
  @override
  Future<MediaLibraryEntry> setTriageIntent(String mediaId, String? intent) =>
      _api.setMediaTriageIntent(mediaId, intent);
  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) => _api.registerMedia(path, durationMs: durationMs, retain: retain);
}
