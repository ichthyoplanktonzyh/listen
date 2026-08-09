import '../../models/api_failure.dart';
import '../../models/saved_vocabulary_count.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

abstract interface class MediaLibraryRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);

  Future<SavedVocabularyCount> savedVocabularyCount({required String language});
  Future<List<MediaLibraryEntry>> listMediaLibrary();
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
  Future<MediaLibraryEntry> setTriageIntent(String mediaId, String? intent) =>
      _api.setMediaTriageIntent(mediaId, intent);
  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) => _api.registerMedia(path, durationMs: durationMs, retain: retain);
}
