part of '../api_service.dart';

extension SemanticEmbeddingApi on LocalApi {
  Future<SemanticEmbeddingCapabilityView> semanticEmbeddingCapability() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('GET', '/v1/semantic-embedding/capability')
            as Map<String, dynamic>,
      );

  Future<SemanticEmbeddingCapabilityView> installSemanticEmbedding() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('POST', '/v1/semantic-embedding/install', {})
            as Map<String, dynamic>,
      );

  Future<SemanticEmbeddingCapabilityView> rebuildSemanticEmbedding() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('POST', '/v1/semantic-embedding/reindex', {})
            as Map<String, dynamic>,
      );

  Future<SemanticEmbeddingCapabilityView> disableSemanticEmbedding() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('POST', '/v1/semantic-embedding/disable', {})
            as Map<String, dynamic>,
      );

  Future<SemanticEmbeddingCapabilityView> enableSemanticEmbedding() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('POST', '/v1/semantic-embedding/enable', {})
            as Map<String, dynamic>,
      );

  Future<SemanticEmbeddingCapabilityView> uninstallSemanticEmbedding() async =>
      SemanticEmbeddingCapabilityView.fromJson(
        await _request('DELETE', '/v1/semantic-embedding')
            as Map<String, dynamic>,
      );

  Future<SemanticSearchResultView> semanticSearch({
    required String query,
    required String language,
    String source = 'all',
    String channel = 'all',
    int limit = 20,
  }) async {
    final params = Uri(
      queryParameters: {
        'query': query,
        'language': language,
        'source': source,
        'channel': channel,
        'limit': '$limit',
      },
    ).query;
    return SemanticSearchResultView.fromJson(
      await _request('GET', '/v1/semantic-search?$params')
          as Map<String, dynamic>,
    );
  }
}
