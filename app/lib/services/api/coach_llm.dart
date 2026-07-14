part of '../api_service.dart';

// Corpus search, LLM providers, learning resources, coach dashboard.
// Split out of api_service.dart (mechanical decomposition).

extension CoachLlmApi on LocalApi {
  /// Lists configured provider profiles (secret-free views).
  Future<List<dynamic>> listLlmProviders() async =>
      (await _request('GET', '/v1/llm/providers')) as List<dynamic>;

  /// Registers or updates a provider. When [secret] is non-empty it is stored
  /// in the OS keychain and never echoed back.
  Future<LlmProviderProfileView> registerLlmProvider({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required List<String> allowedUses,
    String? secret,
    String? protocolVersion,
    String retention = 'unknown',
  }) async => LlmProviderProfileView.fromJson(
    (await _request('POST', '/v1/llm/providers', {
          'display_name': displayName,
          'adapter_kind': adapterKind,
          'base_url': baseUrl,
          'model_id': modelId,
          'allowed_uses': allowedUses,
          'retention': retention,
          if (protocolVersion != null && protocolVersion.isNotEmpty)
            'protocol_version': protocolVersion,
          if (secret != null && secret.isNotEmpty) 'secret': secret,
        }))
        as Map<String, dynamic>,
  );

  /// Deletes a provider and removes its credential from the secure store.
  Future<void> deleteLlmProvider(String id) async {
    await _request('DELETE', '/v1/llm/providers/${Uri.encodeComponent(id)}');
  }

  /// Connectivity + capability test: actually measures structured-output
  /// support against the endpoint. Diagnostic only, never learning feedback.
  Future<LlmProbeResult> probeLlmProvider(String id) async =>
      LlmProbeResult.fromJson(
        (await _request(
              'POST',
              '/v1/llm/providers/${Uri.encodeComponent(id)}/probe',
            ))
            as Map<String, dynamic>,
      );

  /// Searches the rebuildable local corpus projection. A whitespace-free
  /// query matches exact normalized word keys; a multi-word query substring
  /// matches sentence and chunk text.
  Future<List<CorpusOccurrence>> searchCorpus({
    required String language,
    required String query,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = [
      'language=${Uri.encodeQueryComponent(language)}',
      'query=${Uri.encodeQueryComponent(query)}',
      'limit=$limit',
      'offset=$offset',
    ].join('&');
    final values =
        await _request('GET', '/v1/corpus/search?$params') as List<dynamic>;
    return values
        .map(
          (value) => CorpusOccurrence.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// Rebuilds the corpus projection for every imported subtitle track and
  /// returns the number of reindexed tracks.
  Future<int> reindexCorpus() async {
    final result =
        await _request('POST', '/v1/corpus/reindex', {})
            as Map<String, dynamic>;
    return result['indexed_tracks'] as int;
  }

  Future<List<Map<String, dynamic>>> learningResources() async =>
      ((await _request('GET', '/v1/learning-resources')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> installLearningResource(String id) async =>
      (await _request(
            'POST',
            '/v1/learning-resources/${Uri.encodeComponent(id)}/install',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> removeLearningResource(String id) async =>
      (await _request(
            'DELETE',
            '/v1/learning-resources/${Uri.encodeComponent(id)}',
          ))
          as Map<String, dynamic>;

  Future<CoachDashboard> coachDashboard({int days = 7}) async =>
      CoachDashboard.fromJson(
        (await _request('GET', '/v1/coach/dashboard?days=$days'))
            as Map<String, dynamic>,
      );

  Future<void> graduateCoachMaterial(String mediaId) async {
    await _request(
      'POST',
      '/v1/coach/materials/${Uri.encodeComponent(mediaId)}/graduate',
    );
  }

  Future<List<CoachEvidenceItem>> coachEvidence(
    String metric, {
    int days = 7,
  }) async =>
      ((await _request(
                'GET',
                '/v1/coach/evidence?metric=${Uri.encodeQueryComponent(metric)}&days=$days',
              ))
              as List<dynamic>)
          .map(
            (item) => CoachEvidenceItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();
}
