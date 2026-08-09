import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('accepts a compatible versioned sidecar handshake (3.2+)', () {
    // The App consumes the Core 3.2 learning-material surface, so any 3.2.x
    // or later contract within major 3 (including prerelease/build forms the
    // semantic parser accepts) is compatible.
    for (final version in const [
      '3.2.0',
      '3.2.1',
      '3.3.0',
      '3.10.0',
      '3.2.0-rc.1',
      '3.2.1+build.7',
    ]) {
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        returnsNormally,
        reason: '$version satisfies the 3.2+ contract floor',
      );
    }
  });

  test('rejects missing or incompatible contract metadata', () {
    expect(
      () => validateSidecarHandshake({'event': 'api.started'}),
      throwsFormatException,
    );
    for (final version in const ['1.3.0', '2.3.0', '4.0.0']) {
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
            contains('supports 3.x'),
          ),
        ),
        reason: '$version is outside the supported 3.x contract major',
      );
    }
    for (final version in const ['3.0.0', '3.0.9', '3.1.0', '3.1.9']) {
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
            contains('requires 3.2'),
          ),
        ),
        reason: '$version predates the 3.2 learning-material surface',
      );
    }
    for (final version in const ['three.two.zero', '3', '3.2', '']) {
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
