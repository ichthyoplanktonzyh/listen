import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

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
printf '%s\n' '${_event(3, 'completed', extra: ',"package_sha256":"sha256:aaa","media_fingerprint":"sha256:bbb","resources":[],"warnings":[]')}'
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final service = LocalListenGenProcessService(
      executable: script.path,
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
printf '%s\n' '${_event(3, 'completed', extra: ',"package_sha256":"sha256:aaa","media_fingerprint":"sha256:bbb","resources":[],"warnings":[]')}'
''');
      addTearDown(() => script.parent.delete(recursive: true));
      final run = await LocalListenGenProcessService(
        executable: script.path,
        providerArgs: const ['--provider', 'fixture'],
      ).start(request);
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
printf '%s\n' '${_event(2, 'completed', extra: ',"package_sha256":"sha256:aaa","media_fingerprint":"sha256:bbb","resources":[],"warnings":[]')}'
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await LocalListenGenProcessService(
      executable: script.path,
      providerArgs: const ['--provider', 'fixture'],
    ).start(request);

    expect(
      await run.packagePath.timeout(const Duration(seconds: 2)),
      isNotEmpty,
    );
    await run.cleanUp();
  });

  test('preserves a stable failed terminal code', () async {
    final script = await _script('''
printf '%s\n' '${_event(0, 'protocol')}'
printf '%s\n' '${_event(1, 'started')}'
printf '%s\n' '${_event(2, 'failed', extra: ',"code":"provider_timeout","message":"Provider timed out"')}'
exit 2
''');
    addTearDown(() => script.parent.delete(recursive: true));
    final run = await LocalListenGenProcessService(
      executable: script.path,
      providerArgs: const ['--provider', 'fixture'],
    ).start(request);
    run.events.listen((_) {});

    await expectLater(
      run.packagePath,
      throwsA(
        isA<ListenGenProcessFailure>().having(
          (failure) => failure.code,
          'code',
          'provider_timeout',
        ),
      ),
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
    final run = await LocalListenGenProcessService(
      executable: script.path,
      providerArgs: const ['--provider', 'fixture'],
    ).start(request);
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
      final run = await LocalListenGenProcessService(
        executable: script.path,
        providerArgs: const ['--provider', 'fixture'],
      ).start(request);
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
}

String _event(int sequence, String event, {String extra = ''}) =>
    '{"schema":"listen_gen.machine-event.v1","protocol_version":1,'
    '"sequence":$sequence,"tool":{"id":"listen-gen","version":"0.1.0"},'
    '"event":"$event"${event == 'protocol' && extra.isEmpty ? ',"capabilities":{}' : ''}$extra}';

Future<File> _script(String body) async {
  final directory = await Directory.systemTemp.createTemp('listen-gen-test-');
  final file = File('${directory.path}/listen-gen')
    ..writeAsStringSync('#!/bin/sh\nset -eu\n$body');
  await Process.run('/bin/chmod', ['+x', file.path]);
  return file;
}
