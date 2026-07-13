// Phase 3.12 vendor-neutral LLM provider DTOs.
//
// Handwritten per ADR 0014; committed fixture contract tests
// (test/contract/llm_provider_contract_test.dart) pin these shapes to
// contracts/openapi/v1.yaml. Secrets never appear here: the API only ever
// returns LlmProviderProfileView, which exposes `hasCredential`, never the
// key or its keychain reference.

/// One capability claim with provenance. Only a probed+supported claim is
/// usable for a hard requirement; declared is advisory; unknown is ignorance.
class LlmCapabilityClaim {
  const LlmCapabilityClaim({
    required this.state,
    this.supported,
    this.probedAtMs,
  });

  /// One of `declared`, `probed`, `unknown`.
  final String state;
  final bool? supported;
  final int? probedAtMs;

  bool get isProbedSupported => state == 'probed' && supported == true;

  factory LlmCapabilityClaim.fromJson(Map<String, dynamic> json) =>
      LlmCapabilityClaim(
        state: json['state'] as String? ?? 'unknown',
        supported: json['supported'] as bool?,
        probedAtMs: (json['probed_at_ms'] as num?)?.toInt(),
      );
}

class LlmProviderCapability {
  const LlmProviderCapability({
    required this.structuredOutput,
    required this.streaming,
    required this.multilingual,
    required this.audioInput,
    this.maxContextTokens,
  });

  final LlmCapabilityClaim structuredOutput;
  final LlmCapabilityClaim streaming;
  final LlmCapabilityClaim multilingual;
  final LlmCapabilityClaim audioInput;
  final int? maxContextTokens;

  static LlmCapabilityClaim _claim(dynamic value) => value is Map<String, dynamic>
      ? LlmCapabilityClaim.fromJson(value)
      : const LlmCapabilityClaim(state: 'unknown');

  factory LlmProviderCapability.fromJson(Map<String, dynamic> json) =>
      LlmProviderCapability(
        structuredOutput: _claim(json['structured_output']),
        streaming: _claim(json['streaming']),
        multilingual: _claim(json['multilingual']),
        audioInput: _claim(json['audio_input']),
        maxContextTokens: (json['max_context_tokens'] as num?)?.toInt(),
      );
}

/// Secret-free view of a configured provider profile.
class LlmProviderProfileView {
  const LlmProviderProfileView({
    required this.id,
    required this.displayName,
    required this.adapterKind,
    this.protocolVersion,
    required this.baseUrl,
    required this.modelId,
    required this.hasCredential,
    required this.timeoutMs,
    required this.maxRetries,
    required this.retention,
    required this.allowedUses,
    required this.capability,
    required this.createdAtMs,
  });

  final String id;
  final String displayName;

  /// `openai_chat_completions` or `anthropic_messages`.
  final String adapterKind;
  final String? protocolVersion;
  final String baseUrl;
  final String modelId;

  /// Whether a credential is stored for this provider — never the secret.
  final bool hasCredential;
  final int timeoutMs;
  final int maxRetries;

  /// `no_retention`, `provider_default`, or `unknown`.
  final String retention;
  final List<String> allowedUses;
  final LlmProviderCapability capability;
  final int createdAtMs;

  factory LlmProviderProfileView.fromJson(Map<String, dynamic> json) =>
      LlmProviderProfileView(
        id: json['id'] as String,
        displayName: json['display_name'] as String? ?? '',
        adapterKind: json['adapter_kind'] as String? ?? '',
        protocolVersion: json['protocol_version'] as String?,
        baseUrl: json['base_url'] as String? ?? '',
        modelId: json['model_id'] as String? ?? '',
        hasCredential: json['has_credential'] as bool? ?? false,
        timeoutMs: (json['timeout_ms'] as num?)?.toInt() ?? 0,
        maxRetries: (json['max_retries'] as num?)?.toInt() ?? 0,
        retention: json['retention'] as String? ?? 'unknown',
        allowedUses:
            (json['allowed_uses'] as List<dynamic>? ?? const [])
                .map((e) => e as String)
                .toList(),
        capability: LlmProviderCapability.fromJson(
          (json['capability'] as Map<String, dynamic>?) ?? const {},
        ),
        createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      );
}

/// Result of the connectivity + capability probe.
class LlmProbeResult {
  const LlmProbeResult({required this.structuredOutput});

  final LlmCapabilityClaim structuredOutput;

  factory LlmProbeResult.fromJson(Map<String, dynamic> json) => LlmProbeResult(
        structuredOutput: LlmCapabilityClaim.fromJson(
          (json['structured_output'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}
