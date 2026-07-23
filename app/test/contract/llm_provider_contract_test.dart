import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/llm_provider.dart';

/// Committed fixture contract tests for the Phase 3.12 provider DTOs.
/// Pins the Dart shapes to the Rust API responses in contracts/openapi/v1.yaml.
void main() {
  group('LlmProviderProfileView', () {
    test('parses a full secret-free view', () {
      final view = LlmProviderProfileView.fromJson(const {
        'id': 'abc123',
        'display_name': 'My OpenAI',
        'adapter_kind': 'openai_chat_completions',
        'protocol_version': null,
        'base_url': 'https://api.example.com/v1',
        'model_id': 'gpt-x',
        'has_credential': true,
        'timeout_ms': 30000,
        'max_retries': 1,
        'retention': 'unknown',
        'allowed_uses': ['semantic_judgment'],
        'capability': {
          'structured_output': {
            'state': 'probed',
            'supported': true,
            'probed_at_ms': 100,
          },
          'streaming': {'state': 'unknown'},
          'multilingual': {'state': 'declared', 'supported': true},
          'audio_input': {'state': 'unknown'},
          'max_context_tokens': null,
        },
        'created_at_ms': 1800000000000,
      });
      expect(view.id, 'abc123');
      expect(view.displayName, 'My OpenAI');
      expect(view.adapterKind, 'openai_chat_completions');
      expect(view.hasCredential, isTrue);
      expect(view.allowedUses, ['semantic_judgment']);
      expect(view.capability.structuredOutput.isProbedSupported, isTrue);
      expect(view.capability.streaming.state, 'unknown');
    });

    test('degrades gracefully on a sparse payload', () {
      final view = LlmProviderProfileView.fromJson(const {'id': 'x'});
      expect(view.hasCredential, isFalse);
      expect(view.allowedUses, isEmpty);
      expect(view.retention, 'unknown');
      expect(view.capability.structuredOutput.state, 'unknown');
    });
  });

  group('LlmCapabilityClaim', () {
    test('only probed+supported is usable', () {
      expect(
        LlmCapabilityClaim.fromJson(const {
          'state': 'probed',
          'supported': true,
        }).isProbedSupported,
        isTrue,
      );
      expect(
        LlmCapabilityClaim.fromJson(const {
          'state': 'declared',
          'supported': true,
        }).isProbedSupported,
        isFalse,
      );
      expect(
        LlmCapabilityClaim.fromJson(const {
          'state': 'unknown',
        }).isProbedSupported,
        isFalse,
      );
    });
  });

  group('LlmProbeResult', () {
    test('parses the probe response', () {
      final result = LlmProbeResult.fromJson(const {
        'structured_output': {
          'state': 'probed',
          'supported': false,
          'probed_at_ms': 5,
        },
      });
      expect(result.structuredOutput.state, 'probed');
      expect(result.structuredOutput.supported, isFalse);
    });
  });
}
