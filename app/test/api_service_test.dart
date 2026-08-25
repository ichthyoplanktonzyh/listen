import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('accepts a compatible versioned sidecar handshake (4.0+)', () {
    // The App consumes the Core 4.0 learning-material surface, so any 4.0.x
    // or later contract within major 4 (including prerelease/build forms the
    // semantic parser accepts) is compatible.
    for (final version in const [
      '4.0.0',
      '4.0.1',
      '4.1.0',
      '4.10.0',
      '4.0.0-rc.1',
      '4.0.1+build.7',
    ]) {
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        returnsNormally,
        reason: '$version satisfies the 4.0+ contract floor',
      );
    }
  });

  test('rejects missing or incompatible contract metadata', () {
    expect(
      () => validateSidecarHandshake({'event': 'api.started'}),
      throwsFormatException,
    );
    for (final version in const ['1.3.0', '2.3.0', '3.2.0', '5.0.0']) {
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
            contains('supports 4.x'),
          ),
        ),
        reason: '$version is outside the supported 4.x contract major',
      );
    }
    for (final version in const ['4.0.0-rc.1']) {
      // A prerelease within the supported major/minor still satisfies the
      // floor: the semantic parser keeps prerelease/build forms.
      expect(
        () => validateSidecarHandshake({
          'event': 'api.started',
          'api_version': 1,
          'contract_version': version,
          'runtime_version': '0.7.0',
        }),
        returnsNormally,
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
