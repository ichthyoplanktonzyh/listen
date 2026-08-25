import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/local_realtime_speech_service.dart';

class _FakeProcess implements Process {
  _FakeProcess({int exitCodeVal = 0}) : _exitCompleter = Completer<int>() {
    if (exitCodeVal != 0) {
      _exitCompleter.complete(exitCodeVal);
    }
  }

  final Completer<int> _exitCompleter;
  bool killed = false;
  ProcessSignal? lastSignal;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    lastSignal = signal;
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(0);
    }
    return true;
  }

  @override
  int get pid => 12345;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  group('DefaultLocalRealtimeSpeechService', () {
    test('isInstalled probes via callback when provided', () async {
      var probeCalled = false;
      final service = DefaultLocalRealtimeSpeechService(
        isInstalledProbe: () async {
          probeCalled = true;
          return true;
        },
      );

      final result = await service.isInstalled();
      expect(result, isTrue);
      expect(probeCalled, isTrue);
    });

    test('isReady probes loopback endpoint via callback', () async {
      final service = DefaultLocalRealtimeSpeechService(
        readinessProbe: (uri) async => uri.port == 8765,
      );

      final result = await service.isReady();
      expect(result, isTrue);
    });

    test('ensureStarted returns immediately when already ready', () async {
      var processStarted = false;
      final service = DefaultLocalRealtimeSpeechService(
        readinessProbe: (_) async => true,
        processStarter: (exec, args, {environment, workingDirectory}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      await service.ensureStarted();
      expect(processStarted, isFalse);
    });

    test('ensureStarted throws when not installed', () async {
      final service = DefaultLocalRealtimeSpeechService(
        isInstalledProbe: () async => false,
        readinessProbe: (_) async => false,
      );

      await expectLater(
        service.ensureStarted(),
        throwsA(isA<LocalRealtimeSpeechNotInstalledException>()),
      );
    });

    test('ensureStarted spawns process and polls until ready', () async {
      var readyCount = 0;
      _FakeProcess? spawned;
      final service = DefaultLocalRealtimeSpeechService(
        isInstalledProbe: () async => true,
        readinessProbe: (_) async {
          readyCount++;
          return readyCount >= 2;
        },
        processStarter: (exec, args, {environment, workingDirectory}) async {
          spawned = _FakeProcess();
          return spawned!;
        },
      );

      await service.ensureStarted(timeout: const Duration(seconds: 5));
      expect(spawned, isNotNull);
      expect(readyCount, greaterThanOrEqualTo(2));
    });

    test('ensureStarted fails when process exits prematurely', () async {
      final service = DefaultLocalRealtimeSpeechService(
        isInstalledProbe: () async => true,
        readinessProbe: (_) async => false,
        processStarter: (exec, args, {environment, workingDirectory}) async {
          return _FakeProcess(exitCodeVal: 1);
        },
      );

      await expectLater(
        service.ensureStarted(timeout: const Duration(seconds: 2)),
        throwsA(isA<LocalRealtimeSpeechLaunchException>()),
      );
    });

    test('idle timeout automatically stops the managed process', () async {
      _FakeProcess? spawned;
      final service = DefaultLocalRealtimeSpeechService(
        idleTimeout: const Duration(milliseconds: 50),
        isInstalledProbe: () async => true,
        readinessProbe: (_) async => true,
        processStarter: (exec, args, {environment, workingDirectory}) async {
          spawned = _FakeProcess();
          return spawned!;
        },
      );

      // Start service
      var ready = false;
      final service2 = DefaultLocalRealtimeSpeechService(
        idleTimeout: const Duration(milliseconds: 50),
        isInstalledProbe: () async => true,
        readinessProbe: (_) async => ready,
        processStarter: (exec, args, {environment, workingDirectory}) async {
          spawned = _FakeProcess();
          ready = true;
          return spawned!;
        },
      );

      await service2.ensureStarted();
      expect(spawned, isNotNull);
      expect(spawned!.killed, isFalse);

      // Transition to inactive
      service2.markConversationInactive();

      // Wait for idle timeout
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(spawned!.killed, isTrue);

      service.dispose();
      service2.dispose();
    });

    test('markConversationActive cancels pending idle stop', () async {
      _FakeProcess? spawned;
      var ready = false;
      final service = DefaultLocalRealtimeSpeechService(
        idleTimeout: const Duration(milliseconds: 60),
        isInstalledProbe: () async => true,
        readinessProbe: (_) async => ready,
        processStarter: (exec, args, {environment, workingDirectory}) async {
          spawned = _FakeProcess();
          ready = true;
          return spawned!;
        },
      );

      await service.ensureStarted();
      service.markConversationInactive();

      // Cancel before timeout
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.markConversationActive();

      // Wait past original timeout
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(spawned!.killed, isFalse);

      service.dispose();
    });
  });
}
