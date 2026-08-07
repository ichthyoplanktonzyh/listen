import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

/// A release service that stands in for the byte-verified bundle. It reports
/// the path of a python stand-in script to launch and, by default, the real
/// SHA of that file's current bytes — so the process service's copy-and-rehash
/// step accepts it. Release verification itself is covered by
/// `listen_gen_release_service_test.dart`.
final class _FakeReleaseService implements ListenGenReleaseService {
  _FakeReleaseService({
    required this.artifactPath,
    this.toolVersion = '0.1.0',
    this.configured = true,
    this.failure,
    this.onVerify,
  });

  final String artifactPath;
  final String toolVersion;
  final bool configured;
  final ListenGenProcessFailure? failure;

  /// Runs inside verify(), after the verified SHA is taken but before it is
  /// returned — the seam a swap-after-verify test uses to replace the file.
  final Future<void> Function()? onVerify;

  bool verifyCalled = false;

  @override
  bool get isConfigured => configured;

  @override
  Future<VerifiedListenGenRelease> verify() async {
    verifyCalled = true;
    if (failure != null) throw failure!;
    final sha =
        'sha256:${sha256.convert(await File(artifactPath).readAsBytes())}';
    if (onVerify != null) await onVerify!();
    return VerifiedListenGenRelease(
      artifactPath: artifactPath,
      toolVersion: toolVersion,
      sourceCommit: 'a' * 40,
      artifactSha256: sha,
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
$_parseOutput
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
${_emit(_event(2, 'phase', extra: ',"phase":"building_package"'))}
open(out, 'w').write('x')
${_emit(_completedEvent(3))}
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
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(2, 'started'))}
${_emit(_completedEvent(3))}
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
${_emit(_event(0, 'protocol'))}
${_emit(_event(2, 'started'))}
signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(0.05)
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
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
${_emit(_completedEvent(2))}
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
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
${_emit(_event(2, 'completed', extra: ',"package_sha256":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","media_fingerprint":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","resources":[],"warnings":[]'))}
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
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
${_emit(_event(2, 'failed', extra: ',"code":"provider_timeout","message":"Provider timed out"'))}
sys.exit(2)
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
cancel_event = r\'\'\'${_event(2, 'cancelled')}\'\'\'
def handler(signum, frame):
    print(cancel_event, flush=True)
    sys.exit(130)
signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
while True:
    time.sleep(0.05)
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
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(0.05)
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
      final script = File('${directory.path}/listen-gen.py')
        ..writeAsStringSync('open(r"$marker", "w").write("x")\n');

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

  test('does not execute an artifact swapped after verification', () async {
    final directory = await Directory.systemTemp.createTemp('listen-gen-test-');
    addTearDown(() => directory.delete(recursive: true));
    final marker = '${directory.path}/executed';
    // The verified artifact A is replaced with B (which would create a marker
    // if it ever ran) between the verified SHA being taken and launch.
    final artifact = File('${directory.path}/listen-gen.py')
      ..writeAsStringSync('print("clean artifact A")\n');
    final swapped = 'open(r"$marker", "w").write("x")\n';

    final service = LocalListenGenProcessService(
      releaseService: _FakeReleaseService(
        artifactPath: artifact.path,
        onVerify: () async => artifact.writeAsStringSync(swapped),
      ),
      providerArgs: const ['--provider', 'fixture'],
    );

    // verified hash != later disk bytes → the process never starts.
    await expectLater(
      service.start(request),
      _failsWith('generator_release_artifact_invalid', retryable: false),
    );
    expect(File(marker).existsSync(), isFalse);
  });

  test(
    'rejects machine events whose tool version is not the verified one',
    () async {
      // The bundle is verified as 0.1.0 but the events claim 9.9.9.
      final script = await _script('''
${_emit(_event(0, 'protocol', version: '9.9.9'))}
${_emit(_event(1, 'started', version: '9.9.9'))}
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
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'started'))}
${_emit(_completedEvent(2))}
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

/// Parses `--output <path>` out of argv into `out`, like the real generator.
const _parseOutput = '''
out = None
_args = sys.argv[1:]
for _i, _v in enumerate(_args):
    if _v == '--output' and _i + 1 < len(_args):
        out = _args[_i + 1]''';

/// One `print(...)` of a pre-built NDJSON line, flushed immediately.
String _emit(String json) => "print(r'''$json''', flush=True)";

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

/// Writes a python stand-in generator. It is launched by the process service
/// with `/usr/bin/env python3 <copy>`, so no executable bit is required.
Future<File> _script(String body) async {
  final directory = await Directory.systemTemp.createTemp('listen-gen-test-');
  final file = File('${directory.path}/listen-gen.py')
    ..writeAsStringSync('import sys, signal, time\n$body');
  return file;
}
