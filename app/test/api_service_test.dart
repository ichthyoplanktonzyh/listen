import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('accepts the Core 5.1 channel contract and later minor versions', () {
    // This branch calls the channel, recording, semantic-task, and Anki routes
    // introduced in Core 5.1, so a 5.0 sidecar must fail at startup.
    for (final version in const [
      '5.1.0',
      '5.1.1',
      '5.2.0',
      '5.10.0',
      '5.1.0-rc.1',
      '5.1.1+build.7',
    ]) {
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        returnsNormally,
        reason: '$version satisfies the Core 5.1+ contract',
      );
    }
  });

  test('rejects missing or incompatible contract metadata', () {
    expect(
      () => validateSidecarHandshake({'event': 'api.started'}),
      throwsFormatException,
    );
    for (final version in const ['1.3.0', '2.3.0', '3.2.0', '4.0.0', '6.0.0']) {
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('supports 5.x'),
          ),
        ),
        reason: '$version is outside the supported 5.x contract major',
      );
    }
    for (final version in const ['5.0.0', '5.0.99']) {
      // The 5.0 contract predates the restored app routes.
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        throwsA(isA<FormatException>()),
        reason: '$version predates the Core 5.1 channel contract',
      );
    }
    for (final version in const ['three.two.zero', '4', '4.0', '']) {
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        throwsFormatException,
        reason: '$version is not a well-formed semantic contract version',
      );
    }
  });

  test('development sidecar candidate stays inside frontend checkout', () {
    final candidates = sidecarCandidatesFrom(Directory('/tmp/listen-app'));

    expect(candidates, ['/tmp/listen-app/.backend/runtime/bin/api-http']);
    expect(candidates.single, isNot(contains('/target/')));
  });
}
