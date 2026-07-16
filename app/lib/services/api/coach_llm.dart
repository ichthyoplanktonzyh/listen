part of '../api_service.dart';

// Corpus search, LLM providers, learning resources, coach dashboard.
// Split out of api_service.dart (mechanical decomposition).

extension CoachLlmApi on LocalApi {
  /// Lists configured provider profiles (secret-free views).
  Future<List<dynamic>> listLlmProviders() async =>
      (await _request('GET', '/v1/llm/providers')) as List<dynamic>;

  /// Typed provider list (secret-free), convenience over [listLlmProviders].
  Future<List<LlmProviderProfileView>> llmProviders() async =>
      (await listLlmProviders())
          .map((e) => LlmProviderProfileView.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  /// Generates a rubric draft (information points only) for one source segment
  /// through the provider (Phase 3.12.2). The draft is not persisted; the
  /// client shows it for review/edit and saves an approved rubric through the
  /// normal create path. Throws on any provider error.
  Future<RubricDraftView> generateRubricViaLlmProvider(
    String providerId, {
    required String purpose,
    required String sourceLanguage,
    required String responseLanguage,
    required String transcriptSnapshot,
  }) async => RubricDraftView.fromJson(
    (await _request(
          'POST',
          '/v1/llm/providers/${Uri.encodeComponent(providerId)}/rubric',
          {
            'purpose': purpose,
            'source_language': sourceLanguage,
            'response_language': responseLanguage,
            'transcript_snapshot': transcriptSnapshot,
          },
        ))
        as Map<String, dynamic>,
  );

  /// Judges one stored attempt response through a configured provider and
  /// records the result server-side as an unqualified `heuristic_proxy`
  /// judgment (Phase 3.12.2 display-honesty boundary: correctable assist, no
  /// observation/projection). On any provider error nothing is recorded and
  /// this throws — a cut-off or refused answer never becomes a stored verdict.
  Future<SemanticJudgmentView> judgeViaLlmProvider(
    String providerId, {
    required String attemptId,
    required int responseRevision,
  }) async => SemanticJudgmentView.fromJson(
    (await _request(
          'POST',
          '/v1/llm/providers/${Uri.encodeComponent(providerId)}/judge',
          {'attempt_id': attemptId, 'response_revision': responseRevision},
        ))
        as Map<String, dynamic>,
  );

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
