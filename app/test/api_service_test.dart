import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('accepts compatible versioned sidecar handshake', () {
    expect(
      () => validateSidecarHandshake({
        'event': 'api.started',
        'api_version': 1,
        'contract_version': '1.3.0',
        'runtime_version': '0.7.0',
      }),
      returnsNormally,
    );
  });

  test('rejects missing or incompatible contract metadata', () {
    expect(
      () => validateSidecarHandshake({'event': 'api.started'}),
      throwsFormatException,
    );
    expect(
      () => validateSidecarHandshake({
        'event': 'api.started',
        'api_version': 1,
        'contract_version': '2.0.0',
        'runtime_version': '0.7.0',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('supports 1.x'),
        ),
      ),
    );
  });

  test('development sidecar candidate stays inside frontend checkout', () {
    final candidates = sidecarCandidatesFrom(Directory('/tmp/listen-app'));

    expect(candidates, ['/tmp/listen-app/.backend/runtime/bin/api-http']);
    expect(candidates.single, isNot(contains('/target/')));
  });
}
