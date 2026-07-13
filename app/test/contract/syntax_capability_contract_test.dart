import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/syntax_capability.dart';

void main() {
  test(
    'parses persisted capability states without treating partial as ready',
    () {
      final view = SyntaxCapabilityView.fromJson(const {
        'status': 'partial',
        'progress': 0.75,
        'enabled': false,
        'runtime_version': '3.8.13',
        'provider_version': 'jsonl-v2',
        'model_version': '3.8.0',
        'model_checksum_sha256': 'abc',
        'expected_install_bytes': 162250752,
        'delivery_checksum_sha256': 'delivery',
        'installed_bytes': 120000000,
        'error': 'model missing',
      });
      expect(view.status, 'partial');
      expect(view.isReady, isFalse);
      expect(view.isInstalled, isTrue);
      expect(view.error, 'model missing');
    },
  );

  test('parses track cache result and cache reuse', () {
    final view = TrackSyntaxAnalysisView.fromJson(const {
      'status': 'partial',
      'fingerprint': 'f1',
      'cache_hit': true,
      'sentence_count': 10,
      'analyzed_sentence_count': 9,
      'fallback_sentence_count': 1,
    });
    expect(view.cacheHit, isTrue);
    expect(view.analyzedSentenceCount, 9);
    expect(view.fallbackSentenceCount, 1);
  });
}
