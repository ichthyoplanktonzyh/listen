import '../../models/semantic_embedding.dart';
import '../../services/api_service.dart';

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

  @override
  Future<SemanticEmbeddingCapabilityView> capability() =>
      _api.semanticEmbeddingCapability();

  @override
  Future<SemanticEmbeddingCapabilityView> install() =>
      _api.installSemanticEmbedding();

  @override
  Future<SemanticEmbeddingCapabilityView> rebuild() =>
      _api.rebuildSemanticEmbedding();

  @override
  Future<SemanticEmbeddingCapabilityView> disable() =>
      _api.disableSemanticEmbedding();

  @override
  Future<SemanticEmbeddingCapabilityView> enable() =>
      _api.enableSemanticEmbedding();

  @override
  Future<SemanticEmbeddingCapabilityView> uninstall() =>
      _api.uninstallSemanticEmbedding();

  @override
  Future<SemanticSearchResultView> search({
    required String query,
    required String language,
  }) => _api.semanticSearch(query: query, language: language);
}
