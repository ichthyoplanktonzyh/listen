import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

/// A release service that stands in for the byte-verified bundle: it hands the
/// process service the path of a shell script to launch and the tool version
/// machine events must carry. Release verification itself is covered by
/// `listen_gen_release_service_test.dart`.
final class _FakeReleaseService implements ListenGenReleaseService {
  _FakeReleaseService({
    required this.artifactPath,
    this.toolVersion = '0.1.0',
    this.configured = true,
    this.failure,
  });

  final String artifactPath;
  final String toolVersion;
  final bool configured;
  final ListenGenProcessFailure? failure;
  bool verifyCalled = false;

  @override
  bool get isConfigured => configured;

  @override
  Future<VerifiedListenGenRelease> verify() async {
    verifyCalled = true;
    if (failure != null) throw failure!;
    return VerifiedListenGenRelease(
      artifactPath: artifactPath,
      toolVersion: toolVersion,
      sourceCommit: 'a' * 40,
      artifactSha256: 'sha256:${'0' * 64}',
    );
  }
}

LocalListenGenProcessService _service(
  String artifactPath, {
  String toolVersion = '0.1.0',
  List<String> providerArgs = const ['--provider', 'fixture'],
}) => LocalListenGenProcessService(
  releaseService: _FakeReleaseService(
    artifactPath: artifactPath,
    toolVersion: toolVersion,
  ),
  providerArgs: providerArgs,
);

Matcher _failsWith(String code, {required bool retryable}) => throwsA(
  isA<ListenGenProcessFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.retryable, 'retryable', retryable),
);

void main() {
  const request = ContentPackageGenerationRequest(
    mediaPath: '/tmp/media.wav',
    title: 'Lesson',
    mediaKind: 'audio',
    durationMs: 2200,
    createdAtMs: 1785542400000,
  );

  test('waits for a valid completed terminal before exposing output', () async {
    final script = await _script('''
output=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--output" ]; then shift; output="\$1"; fi
  shift
done
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_event(2, 'phase', extra: ',"phase":"building_package"')}'
printf x > "\$output"
printf '%s\n' '${_completedEvent(3)}'
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final service = _service(
      script.path,
      providerArgs: const ['--provider', 'fixture', '--fixture', '/tmp/a.json'],
    );

    final run = await service.start(request);
    final eventsFuture = run.events.toList();
    final path = await run.packagePath;

    expect(await File(path).readAsString(), 'x');
    expect((await eventsFuture).last.kind, ListenGenEventKind.completed);
    await run.cleanUp();
    expect(await File(path).exists(), isFalse);
  });

  test(
    'rejects non-contiguous sequence even when exit and output look valid',
    () async {
      final script = await _script('''
output=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--output" ]; then shift; output="\$1"; fi
  shift
done
printf x > "\$output"
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(2, 'started')}'
printf '%s\n' '${_completedEvent(3)}'
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(request);
      run.events.listen((_) {}, onError: (_) {});

      await expectLater(
        run.packagePath,
        throwsA(
          isA<ListenGenProcessFailure>().having(
            (failure) => failure.code,
            'code',
            'generator_protocol_invalid',
          ),
        ),
      );
      await run.cleanUp();
    },
  );

  test(
    'protocol failure is prompt while cleanup reclaims a hung process',
    () async {
      final script = await _script('''
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(2, 'started')}'
trap '' INT TERM
while :; do :; done
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(request);
      run.events.listen((_) {}, onError: (_) {});

      await expectLater(
        run.packagePath.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<ListenGenProcessFailure>().having(
            (failure) => failure.code,
            'code',
            'generator_protocol_invalid',
          ),
        ),
      );
      await run.cleanUp().timeout(const Duration(seconds: 7));
    },
  );

  test('package completion does not require an event subscriber', () async {
    final script = await _script('''
output=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--output" ]; then shift; output="\$1"; fi
  shift
done
printf x > "\$output"
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_completedEvent(2)}'
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await _service(script.path).start(request);

    expect(
      await run.packagePath.timeout(const Duration(seconds: 2)),
      isNotEmpty,
    );
    await run.cleanUp();
  });

  test('rejects a completed event with the wrong archive digest', () async {
    final script = await _script('''
output=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--output" ]; then shift; output="\$1"; fi
  shift
done
printf x > "\$output"
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_event(2, 'completed', extra: ',"package_sha256":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","media_fingerprint":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","resources":[],"warnings":[]')}'
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await _service(script.path).start(request);
    run.events.listen((_) {});

    await expectLater(
      run.packagePath,
      throwsA(
        isA<ListenGenProcessFailure>().having(
          (failure) => failure.code,
          'code',
          'generator_package_digest_mismatch',
        ),
      ),
    );
    await run.cleanUp();
  });

  test('preserves a stable, retryable failed terminal code', () async {
    final script = await _script('''
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_event(2, 'failed', extra: ',"code":"provider_timeout","message":"Provider timed out"')}'
exit 2
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await _service(script.path).start(request);
    run.events.listen((_) {});

    // Provider runtime failures keep the default retryable semantics.
    await expectLater(
      run.packagePath,
      _failsWith('provider_timeout', retryable: true),
    );
    await run.cleanUp();
  });

  test('cancellation waits for terminal process cleanup', () async {
    final script = await _script('''
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
cancel_event='${_event(2, 'cancelled')}'
trap 'printf "%s\\n" "\$cancel_event"; exit 130' INT TERM
while :; do :; done
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await _service(script.path).start(request);
    final started = Completer<void>();
    run.events.listen((event) {
      if (event.kind == ListenGenEventKind.started && !started.isCompleted) {
        started.complete();
      }
    });
    await started.future.timeout(const Duration(seconds: 2));

    run.cancel();

    await expectLater(
      run.packagePath.timeout(const Duration(seconds: 7)),
      throwsA(
        isA<ListenGenProcessFailure>().having(
          (failure) => failure.code,
          'code',
          'cancelled',
        ),
      ),
    );
    await run.cleanUp();
  });

  test(
    'cancellation escalates when the generator ignores soft signals',
    () async {
      final script = await _script('''
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
trap '' INT TERM
while :; do :; done
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(request);
      final started = Completer<void>();
      run.events.listen((event) {
        if (event.kind == ListenGenEventKind.started && !started.isCompleted) {
          started.complete();
        }
      });
      await started.future.timeout(const Duration(seconds: 2));

      run.cancel();

      await expectLater(
        run.packagePath.timeout(const Duration(seconds: 7)),
        throwsA(
          isA<ListenGenProcessFailure>().having(
            (failure) => failure.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await run.cleanUp();
    },
  );

  test(
    'does not start the generator when release verification fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'listen-gen-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final marker = '${directory.path}/launched';
      final script = File('${directory.path}/listen-gen')
        ..writeAsStringSync('#!/bin/sh\ntouch "$marker"\n');
      await Process.run('/bin/chmod', ['+x', script.path]);

      final service = LocalListenGenProcessService(
        releaseService: _FakeReleaseService(
          artifactPath: script.path,
          failure: const ListenGenProcessFailure(
            'generator_release_lock_invalid',
            retryable: false,
          ),
        ),
        providerArgs: const ['--provider', 'fixture'],
      );

      // A release failure is non-retryable and aborts before any launch.
      await expectLater(
        service.start(request),
        _failsWith('generator_release_lock_invalid', retryable: false),
      );
      expect(File(marker).existsSync(), isFalse);
    },
  );

  test(
    'rejects machine events whose tool version is not the verified one',
    () async {
      // The bundle is verified as 0.1.0 but the events claim 9.9.9.
      final script = await _script('''
printf '%s\n' '${_event(0, 'protocol', version: '9.9.9')}'
printf '%s\n' '${_event(1, 'started', version: '9.9.9')}'
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(
        script.path,
        toolVersion: '0.1.0',
      ).start(request);
      run.events.listen((_) {}, onError: (_) {});

      await expectLater(
        run.packagePath,
        _failsWith('generator_protocol_invalid', retryable: true),
      );
      await run.cleanUp();
    },
  );

  test(
    'accepts machine events stamped with the verified tool version',
    () async {
      final script = await _script('''
output=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--output" ]; then shift; output="\$1"; fi
  shift
done
printf x > "\$output"
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_completedEvent(2)}'
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(
        script.path,
        toolVersion: '0.1.0',
      ).start(request);

      expect(
        await run.packagePath.timeout(const Duration(seconds: 2)),
        isNotEmpty,
      );
      await run.cleanUp();
    },
  );

  test('configuration needs both a configured release and provider args', () {
    // There is no executable override: LISTEN_GEN_EXECUTABLE cannot configure
    // this service. Only a configured release plus provider args can.
    LocalListenGenProcessService build({
      required bool releaseConfigured,
      required List<String> providerArgs,
    }) => LocalListenGenProcessService(
      releaseService: _FakeReleaseService(
        artifactPath: '/unused',
        configured: releaseConfigured,
      ),
      providerArgs: providerArgs,
    );

    expect(
      build(
        releaseConfigured: true,
        providerArgs: const ['--provider'],
      ).isConfigured,
      isTrue,
    );
    expect(
      build(
        releaseConfigured: false,
        providerArgs: const ['--provider'],
      ).isConfigured,
      isFalse,
    );
    expect(
      build(releaseConfigured: true, providerArgs: const []).isConfigured,
      isFalse,
    );
  });
}

String _event(
  int sequence,
  String event, {
  String extra = '',
  String version = '0.1.0',
}) =>
    '{"schema":"listen_gen.machine-event.v1","protocol_version":1,'
    '"sequence":$sequence,"tool":{"id":"listen-gen","version":"$version"},'
    '"event":"$event"${event == 'protocol' && extra.isEmpty ? ',"capabilities":{}' : ''}$extra}';

String _completedEvent(int sequence) => _event(
  sequence,
  'completed',
  extra:
      ',"package_sha256":"sha256:2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881"'
      ',"media_fingerprint":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
      ',"resources":[],"warnings":[]',
);

Future<File> _script(String body) async {
  final directory = await Directory.systemTemp.createTemp('listen-gen-test-');
  final file = File('${directory.path}/listen-gen')
    ..writeAsStringSync('#!/bin/sh\nset -eu\n$body');
  await Process.run('/bin/chmod', ['+x', file.path]);
  return file;
}
