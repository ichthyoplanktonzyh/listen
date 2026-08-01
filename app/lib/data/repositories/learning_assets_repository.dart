import '../../models/runtime_resources.dart';
import '../../models/types.dart';
import '../../models/api_failure.dart';
import '../../services/api_service.dart';

abstract interface class LearningAssetsRepository {
  ApiFailure failureDetail(Object error);
  Future<List<LexicalEntryDetails>> lexicalEntries({
    required String language,
    required String kind,
    String? status,
    required String search,
  });

  Future<LexicalEntryDetails> upsertLexicalEntry(Map<String, dynamic> value);

  Future<List<LearningResourceDescriptor>> learningResources();

  Future<void> installLearningResource(String id);

  Future<void> removeLearningResource(String id);

  Future<String> openSubtitlesMovieHash(String mediaPath);

  Future<List<OpenSubtitleCandidate>> searchOpenSubtitles({
    required String apiKey,
    String? query,
    String? moviehash,
  });

  Future<String> downloadOpenSubtitle({
    required String apiKey,
    required int fileId,
  });
}

final class LocalLearningAssetsRepository implements LearningAssetsRepository {
  const LocalLearningAssetsRepository(this._api);

  final LocalApi _api;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<List<LexicalEntryDetails>> lexicalEntries({
    required String language,
    required String kind,
    String? status,
    required String search,
  }) => _api.lexicalEntries(
    language: language,
    kind: kind,
    status: status,
    search: search,
  );

  @override
  Future<LexicalEntryDetails> upsertLexicalEntry(Map<String, dynamic> value) =>
      _api.upsertLexicalEntry(value);

  @override
  Future<List<LearningResourceDescriptor>> learningResources() =>
      _api.learningResources();

  @override
  Future<void> installLearningResource(String id) =>
      _api.installLearningResource(id);

  @override
  Future<void> removeLearningResource(String id) =>
      _api.removeLearningResource(id);

  @override
  Future<String> openSubtitlesMovieHash(String mediaPath) =>
      _api.openSubtitlesMovieHash(mediaPath);

  @override
  Future<List<OpenSubtitleCandidate>> searchOpenSubtitles({
    required String apiKey,
    String? query,
    String? moviehash,
  }) => _api.searchOpenSubtitles(
    apiKey: apiKey,
    query: query,
    moviehash: moviehash,
  );

  @override
  Future<String> downloadOpenSubtitle({
    required String apiKey,
    required int fileId,
  }) => _api.downloadOpenSubtitle(apiKey: apiKey, fileId: fileId);
}
