import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/gen_machine_event.dart';
import 'package:llplayer_next/services/capability_generation_request.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

const _toolVersion = '0.5.0';

/// A release service that stands in for the byte-verified bundle. It reports
/// the path of a python stand-in script to launch and, by default, the real
/// SHA of that file's current bytes — so the process service's copy-and-rehash
/// step accepts it. Release verification itself is covered by
/// `listen_gen_release_service_test.dart`.
final class _FakeReleaseService implements ListenGenReleaseService {
  _FakeReleaseService({
    required this.artifactPath,
    this.toolVersion = _toolVersion,
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
      artifactFilename: 'listen-gen.pyz',
      toolVersion: toolVersion,
      sourceCommit: 'a' * 40,
      artifactSha256: sha,
    );
  }
}

LocalListenGenProcessService _service(
  String artifactPath, {
  String toolVersion = _toolVersion,
}) => LocalListenGenProcessService(
  releaseService: _FakeReleaseService(
    artifactPath: artifactPath,
    toolVersion: toolVersion,
  ),
);

/// A minimal v2 capability request. The process service never inspects the
/// document — it is written to disk and handed to `package from-capability` —
/// so the fixture only needs to be a plausible document.
const _request = CapabilityGenerationRequest(
  requestJson: {
    'schema': 'listen_gen.capability-request.v2',
    'version': 2,
    'request_id': 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'material_id': 'material-1',
    'material_revision_id':
        'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'edition_id': 'edition:material-1',
    'requested_capability': 'listen',
    'created_at_ms': 1785542400000,
  },
  providerArguments: ['--provider', 'fixture'],
);

Matcher _failsWith(String code, {required bool retryable}) => throwsA(
  isA<ListenGenProcessFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.retryable, 'retryable', retryable),
);

void main() {
  group('parseListenGenMachineEventV2', () {
    Map<String, dynamic> decode(String json) =>
        jsonDecode(json) as Map<String, dynamic>;

    test('rejects a wrong schema, protocol version, or tool identity', () {
      final line = _event(0, 'protocol');
      expect(
        () => parseListenGenMachineEventV2(
          decode(line.replaceFirst('machine-event.v2', 'machine-event.v1')),
          expectedToolVersion: _toolVersion,
        ),
        throwsFormatException,
      );
      expect(
        () => parseListenGenMachineEventV2(
          decode(line.replaceFirst('"protocol_version":2', '"protocol_version":1')),
          expectedToolVersion: _toolVersion,
        ),
        throwsFormatException,
      );
      expect(
        () => parseListenGenMachineEventV2(
          decode(line.replaceFirst('"id":"listen-gen"', '"id":"other"')),
          expectedToolVersion: _toolVersion,
        ),
        throwsFormatException,
      );
      expect(
        () => parseListenGenMachineEventV2(
          decode(line.replaceFirst('"version":"$_toolVersion"', '"version":"9.9.9"')),
          expectedToolVersion: _toolVersion,
        ),
        throwsFormatException,
      );
      expect(
        () => parseListenGenMachineEventV2(
          decode(line.replaceFirst('"protocol"', '"unknown"')),
          expectedToolVersion: _toolVersion,
        ),
        throwsFormatException,
      );
    });

    test('rejects events missing their kind-specific fields', () {
      final base = decode(_event(1, 'accepted'));
      base.remove('attempt_id');
      expect(
        () => parseListenGenMachineEventV2(base, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );

      final planned = decode(_event(2, 'planned'));
      planned.remove('plan');
      expect(
        () => parseListenGenMachineEventV2(planned, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );

      final running = decode(_event(3, 'running'));
      running.remove('stage');
      expect(
        () => parseListenGenMachineEventV2(running, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );

      final completed = decode(
        _event(4, 'completed', extra: ',"package_sha256":"$xDigest"'),
      );
      completed.remove('resources');
      expect(
        () => parseListenGenMachineEventV2(completed, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );

      final failed = decode(_event(1, 'failed', extra: ',"code":"x","message":"y"'));
      failed.remove('code');
      expect(
        () => parseListenGenMachineEventV2(failed, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );
    });

    test('rejects a malformed completed digest and rendition references', () {
      final badDigest = decode(
        _event(4, 'completed', extra: ',"package_sha256":"md5:abc"'),
      );
      expect(
        () => parseListenGenMachineEventV2(badDigest, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );

      final badRendition = decode(
        _event(4, 'completed', extra: ',"package_sha256":"$xDigest"'),
      );
      badRendition['media_renditions'] = [
        {'rendition_id': 'not-a-digest'},
      ];
      expect(
        () => parseListenGenMachineEventV2(badRendition, expectedToolVersion: _toolVersion),
        throwsFormatException,
      );
    });

    test('merges document and media renditions and keeps completion fields', () {
      final event = parseListenGenMachineEventV2(
        decode(
          _event(
            4,
            'completed',
            extra:
                ',"package_sha256":"$xDigest"'
                ',"document_renditions":[{"rendition_id":"sha256:${'a' * 64}"}]'
                ',"media_renditions":[{"rendition_id":"sha256:${'b' * 64}"}]'
                ',"resources":[{"resource_id":"sha256:${'c' * 64}"}]'
                ',"warnings":[{"code":"w1","message":"m1"}]',
          ),
        ),
        expectedToolVersion: _toolVersion,
      );
      expect(event.packageSha256, xDigest);
      expect(event.producedRenditions, ['sha256:${'a' * 64}', 'sha256:${'b' * 64}']);
      expect(event.producedResources, ['sha256:${'c' * 64}']);
      expect(event.completedWarnings, ['w1: m1']);
    });

    test('exposes a terminal for completed, failed, and cancelled events', () {
      final completed = parseListenGenMachineEventV2(
        decode(
          _event(
            4,
            'completed',
            extra:
                ',"package_sha256":"$xDigest"'
                ',"document_renditions":[],"media_renditions":[],'
                '"resources":[],"warnings":[]',
          ),
        ),
        expectedToolVersion: _toolVersion,
      );
      expect(completed.terminal, isNotNull);
      expect(completed.terminal!.kind, GenEventKind.completed);
      expect(completed.terminal!.packageSha256, xDigest);

      final failed = parseListenGenMachineEventV2(
        decode(_event(1, 'failed', extra: ',"code":"provider_timeout","message":"t"')),
        expectedToolVersion: _toolVersion,
      );
      expect(failed.terminal!.kind, GenEventKind.failed);
      expect(failed.terminal!.code, 'provider_timeout');

      final cancelled = parseListenGenMachineEventV2(
        decode(_event(3, 'cancelled')),
        expectedToolVersion: _toolVersion,
      );
      expect(cancelled.terminal!.kind, GenEventKind.cancelled);

      final running = parseListenGenMachineEventV2(
        decode(_event(3, 'running', extra: ',"stage":"transcribing"')),
        expectedToolVersion: _toolVersion,
      );
      expect(running.terminal, isNull);
    });
  });

  group('process lifecycle', () {
    test('waits for a valid completed terminal before exposing output', () async {
      final script = await _script('''
$_parseOutput
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'planned'))}
${_emit(_event(3, 'running', extra: ',"stage":"building_package"'))}
open(out, 'w').write('x')
${_emit(_completedEvent(4))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      final eventsFuture = run.events.toList();
      final path = await run.packagePath;

      expect(await File(path).readAsString(), 'x');
      final events = await eventsFuture;
      expect(events.last.kind, GenEventKind.completed);
      expect(events.map((event) => event.kind), [
        GenEventKind.protocol,
        GenEventKind.accepted,
        GenEventKind.planned,
        GenEventKind.running,
        GenEventKind.completed,
      ]);
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
${_emit(_event(2, 'accepted'))}
${_emit(_completedEvent(3))}
''');
        addTearDown(() => script.parent.delete(recursive: true));
        final run = await _service(script.path).start(_request);
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

    test('rejects events after the terminal event', () async {
      final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_completedEvent(2))}
${_emit(_event(3, 'running', extra: ',"stage":"late"'))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      run.events.listen((_) {}, onError: (_) {});

      await expectLater(
        run.packagePath,
        _failsWith('generator_protocol_invalid', retryable: true),
      );
      await run.cleanUp();
    });

    test('rejects running before planned', () async {
      final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'running', extra: ',"stage":"too_early"'))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      run.events.listen((_) {}, onError: (_) {});

      await expectLater(
        run.packagePath,
        _failsWith('generator_protocol_invalid', retryable: true),
      );
      await run.cleanUp();
    });

    test('accepts warnings between planned and the terminal', () async {
      final script = await _script('''
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'planned'))}
${_emit(_event(3, 'warning', extra: ',"code":"slow","message":"slow lane"'))}
${_emit(_completedEvent(4))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      final eventsFuture = run.events.toList();

      expect(await run.packagePath, isNotEmpty);
      expect(
        (await eventsFuture).map((event) => event.kind),
        contains(GenEventKind.warning),
      );
      await run.cleanUp();
    });

    test('failed right after protocol keeps its stable code', () async {
      final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'failed', extra: ',"code":"provider_timeout","message":"Provider timed out"'))}
sys.exit(2)
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      run.events.listen((_) {});

      // Provider runtime failures keep the default retryable semantics.
      await expectLater(
        run.packagePath,
        _failsWith('provider_timeout', retryable: true),
      );
      await run.cleanUp();
    });

    test('a completed event without a package digest is an empty plan', () async {
      final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'completed'))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      run.events.listen((_) {});

      await expectLater(
        run.packagePath,
        _failsWith('generator_plan_was_empty', retryable: true),
      );
      await run.cleanUp();
    });

    test('rejects a completed event with the wrong archive digest', () async {
      final script = await _script('''
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'completed', extra: ',"package_sha256":"sha256:${'a' * 64}","document_renditions":[],"media_renditions":[],"resources":[],"warnings":[]'))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      run.events.listen((_) {});

      await expectLater(
        run.packagePath,
        _failsWith('generator_package_digest_mismatch', retryable: true),
      );
      await run.cleanUp();
    });

    test('package completion does not require an event subscriber', () async {
      final script = await _script('''
$_parseOutput
open(out, 'w').write('x')
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_completedEvent(2))}
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);

      expect(
        await run.packagePath.timeout(const Duration(seconds: 2)),
        isNotEmpty,
      );
      await run.cleanUp();
    });

    test(
      'protocol failure is prompt while cleanup reclaims a hung process',
      () async {
        final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(2, 'accepted'))}
signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(0.05)
''');
        addTearDown(() => script.parent.delete(recursive: true));
        final run = await _service(script.path).start(_request);
        run.events.listen((_) {}, onError: (_) {});

        await expectLater(
          run.packagePath.timeout(const Duration(seconds: 1)),
          _failsWith('generator_protocol_invalid', retryable: true),
        );
        await run.cleanUp().timeout(const Duration(seconds: 7));
      },
    );

    test('cancellation reports cancelled promptly', () async {
      final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'planned'))}
while True:
    time.sleep(0.05)
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await _service(script.path).start(_request);
      final started = Completer<void>();
      run.events.listen((event) {
        if (event.kind == GenEventKind.planned && !started.isCompleted) {
          started.complete();
        }
      });
      await started.future.timeout(const Duration(seconds: 2));

      run.cancel();

      await expectLater(
        run.packagePath.timeout(const Duration(seconds: 2)),
        _failsWith('cancelled', retryable: true),
      );
      await run.cleanUp().timeout(const Duration(seconds: 7));
    });

    test(
      'cancellation escalates when the generator ignores soft signals',
      () async {
        final script = await _script('''
${_emit(_event(0, 'protocol'))}
${_emit(_event(1, 'accepted'))}
${_emit(_event(2, 'planned'))}
signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(0.05)
''');
        addTearDown(() => script.parent.delete(recursive: true));
        final run = await _service(script.path).start(_request);
        final started = Completer<void>();
        run.events.listen((event) {
          if (event.kind == GenEventKind.planned && !started.isCompleted) {
            started.complete();
          }
        });
        await started.future.timeout(const Duration(seconds: 2));

        run.cancel();

        await expectLater(
          run.packagePath.timeout(const Duration(seconds: 2)),
          _failsWith('cancelled', retryable: true),
        );
        await run.cleanUp().timeout(const Duration(seconds: 7));
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
        );

        // A release failure is non-retryable and aborts before any launch.
        await expectLater(
          service.start(_request),
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
      );

      // verified hash != later disk bytes → the process never starts.
      await expectLater(
        service.start(_request),
        _failsWith('generator_release_artifact_invalid', retryable: false),
      );
      expect(File(marker).existsSync(), isFalse);
    });

    test(
      'rejects machine events whose tool version is not the verified one',
      () async {
        // The bundle is verified as 0.5.0 but the events claim 9.9.9.
        final script = await _script('''
${_emit(_event(0, 'protocol', version: '9.9.9'))}
${_emit(_event(1, 'accepted', version: '9.9.9'))}
''');
        addTearDown(() => script.parent.delete(recursive: true));
        final run = await _service(script.path).start(_request);
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
${_emit(_event(1, 'accepted'))}
${_emit(_completedEvent(2))}
''');
        addTearDown(() => script.parent.delete(recursive: true));
        final run = await _service(script.path).start(_request);

        expect(
          await run.packagePath.timeout(const Duration(seconds: 2)),
          isNotEmpty,
        );
        await run.cleanUp();
      },
    );

    test('configuration needs a configured release', () {
      LocalListenGenProcessService build({required bool releaseConfigured}) =>
          LocalListenGenProcessService(
            releaseService: _FakeReleaseService(
              artifactPath: '/unused',
              configured: releaseConfigured,
            ),
          );

      expect(build(releaseConfigured: true).isConfigured, isTrue);
      expect(build(releaseConfigured: false).isConfigured, isFalse);
    });
  });
}

/// SHA-256 of the single byte 'x', the content every stand-in writes to the
/// output file. The completed event must declare exactly this digest.
const xDigest =
    'sha256:2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881';

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
  String version = _toolVersion,
}) =>
    '{"schema":"listen_gen.machine-event.v2","protocol_version":2,'
    '"sequence":$sequence,"tool":{"id":"listen-gen","version":"$version"},'
    '"event":"$event"${_defaults(event, extra)}$extra}';

/// Kind-specific required fields, supplied unless the caller overrides them
/// through [extra].
String _defaults(String event, String extra) {
  if (extra.isNotEmpty) return '';
  return switch (event) {
    'protocol' => ',"capabilities":{}',
    'accepted' => ',"attempt_id":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"',
    'planned' => ',"plan":{"steps":[]}',
    'running' => ',"stage":"transcribing"',
    'completed' =>
      ',"document_renditions":[],"media_renditions":[],"resources":[],"warnings":[]',
    'failed' => ',"code":"generator_failed","message":"failed"',
    _ => '',
  };
}

String _completedEvent(int sequence) => _event(
  sequence,
  'completed',
  extra:
      ',"package_sha256":"$xDigest"'
      ',"document_renditions":[],"media_renditions":[],"resources":[],"warnings":[]',
);

/// Writes a python stand-in generator. It is launched by the process service
/// with `/usr/bin/env python3 <copy>`, so no executable bit is required.
Future<File> _script(String body) async {
  final directory = await Directory.systemTemp.createTemp('listen-gen-test-');
  final file = File('${directory.path}/listen-gen.py')
    ..writeAsStringSync('import sys, signal, time\n$body');
  return file;
}
