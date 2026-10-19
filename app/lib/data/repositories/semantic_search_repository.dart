import '../../models/api_failure.dart';
import '../../models/semantic_embedding.dart';
import '../../services/api_service.dart';

class SemanticSearchRepositoryFailure implements Exception {
  const SemanticSearchRepositoryFailure(this.detail);

  final ApiFailure detail;
}

/// Data boundary for the optional local semantic-search capability.
abstract interface class SemanticSearchRepository {
  Future<SemanticEmbeddingCapabilityView> capability();

  Future<SemanticEmbeddingCapabilityView> install();

  Future<SemanticEmbeddingCapabilityView> rebuild();

  Future<SemanticEmbeddingCapabilityView> disable();

  Future<SemanticEmbeddingCapabilityView> enable();

  Future<SemanticEmbeddingCapabilityView> uninstall();

  Future<SemanticSearchResultView> search({
    required String query,
    required String language,
  });
}

/// [LocalApi]-backed implementation kept out of the presentation layer.
class LocalSemanticSearchRepository implements SemanticSearchRepository {
  LocalSemanticSearchRepository(this._api);

  final LocalApi _api;

  Future<T> _request<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw SemanticSearchRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<SemanticEmbeddingCapabilityView> capability() =>
      _request(_api.semanticEmbeddingCapability);

  @override
  Future<SemanticEmbeddingCapabilityView> install() =>
      _request(_api.installSemanticEmbedding);

  @override
  Future<SemanticEmbeddingCapabilityView> rebuild() =>
      _request(_api.rebuildSemanticEmbedding);

  @override
  Future<SemanticEmbeddingCapabilityView> disable() =>
      _request(_api.disableSemanticEmbedding);

  @override
  Future<SemanticEmbeddingCapabilityView> enable() =>
      _request(_api.enableSemanticEmbedding);

  @override
  Future<SemanticEmbeddingCapabilityView> uninstall() =>
      _request(_api.uninstallSemanticEmbedding);

  @override
  Future<SemanticSearchResultView> search({
    required String query,
    required String language,
  }) => _request(() => _api.semanticSearch(query: query, language: language));
}
