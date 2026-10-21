part of '../api_service.dart';

// Core LLM provider profiles, local media corpus search, and learning
// resources. Split out of api_service.dart to keep transport methods grouped.
extension LlmCorpusResourcesApi on LocalApi {
  /// Lists configured provider profiles (secret-free views).
  Future<List<LlmProviderProfileView>> listLlmProviders() async =>
      ((await _request('GET', '/v1/llm/providers')) as List<dynamic>)
          .map(
            (value) =>
                LlmProviderProfileView.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

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

  Future<List<LearningResourceDescriptor>> learningResources() async =>
      ((await _request('GET', '/v1/learning-resources')) as List<dynamic>)
          .map(
            (value) => LearningResourceDescriptor.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<LearningResourceDescriptor> installLearningResource(String id) async =>
      LearningResourceDescriptor.fromJson(
        (await _request(
              'POST',
              '/v1/learning-resources/${Uri.encodeComponent(id)}/install',
            ))
            as Map<String, dynamic>,
      );

  Future<LearningResourceDescriptor> removeLearningResource(String id) async =>
      LearningResourceDescriptor.fromJson(
        (await _request(
              'DELETE',
              '/v1/learning-resources/${Uri.encodeComponent(id)}',
            ))
            as Map<String, dynamic>,
      );
}
