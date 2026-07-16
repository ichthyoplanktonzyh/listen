part of '../api_service.dart';

extension ProductionCorpusApi on LocalApi {
  Future<List<ProductionCorpusHitView>> searchProductionCorpus({
    required String language,
    required String query,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = Uri(
      queryParameters: {
        'language': language,
        'query': query,
        'limit': '$limit',
        'offset': '$offset',
      },
    ).query;
    return ((await _request('GET', '/v1/production-corpus/search?$params'))
            as List<dynamic>)
        .map(
          (value) =>
              ProductionCorpusHitView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<int> reindexProductionCorpus() async {
    final json = await _request('POST', '/v1/production-corpus/reindex', {});
    return (json as Map<String, dynamic>)['indexed_rubrics'] as int;
  }
}
