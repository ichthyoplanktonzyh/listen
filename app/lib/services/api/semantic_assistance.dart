part of '../api_service.dart';

/// Optional, user-configured assistance for reading, writing, and speaking
/// tasks. Provider failures remain explicit to the requesting activity; they
/// do not change the learner's attempt or its stored judgment.
String? pickLlmProviderId(List<LlmProviderProfileView> providers, String use) {
  for (final provider in providers) {
    if (provider.hasCredential && provider.allowedUses.contains(use)) {
      return provider.id;
    }
  }
  for (final provider in providers) {
    if (provider.allowedUses.contains(use)) return provider.id;
  }
  return null;
}

extension SemanticAssistanceApi on LocalApi {
  Future<List<LlmProviderProfileView>> llmProviders() => listLlmProviders();

  Future<String?> preferredLlmProviderId(String use) async {
    try {
      return pickLlmProviderId(await listLlmProviders(), use);
    } on Object {
      return null;
    }
  }

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

  Future<String> feedbackViaLlmProvider(
    String providerId, {
    required String attemptId,
    required int responseRevision,
  }) async {
    final result =
        await _request(
              'POST',
              '/v1/llm/providers/${Uri.encodeComponent(providerId)}/feedback',
              {'attempt_id': attemptId, 'response_revision': responseRevision},
            )
            as Map<String, dynamic>;
    return result['feedback'] as String;
  }
}
