import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('sidecar candidates include ancestor repository targets', () {
    final candidates = sidecarCandidatesFrom(
      Directory(
        '/tmp/LLPlayerNext/apps/desktop/build/macos/Build/Products/Debug/'
        'LLPlayerNext.app/Contents/MacOS',
      ),
    );

    expect(candidates, contains('/tmp/LLPlayerNext/target/debug/api-http'));
    expect(candidates, contains('/tmp/LLPlayerNext/target/release/api-http'));
    expect(
      candidates.indexOf('/tmp/LLPlayerNext/target/debug/api-http'),
      lessThan(candidates.indexOf('/tmp/LLPlayerNext/target/release/api-http')),
    );
  });
}
