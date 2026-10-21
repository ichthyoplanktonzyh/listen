import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:llplayer_next/services/realtime_audio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'realtime audio requests microphone permission before capture',
    () async {
      const channel = MethodChannel('test/realtime_audio');
      final calls = <String>[];
      var permissionGranted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestPermission') {
              permissionGranted = true;
              return true;
            }
            if (call.method == 'start') {
              if (!permissionGranted) {
                throw PlatformException(
                  code: 'microphone_permission',
                  message: 'Microphone permission is not granted.',
                );
              }
              return true;
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final directory = await Directory.systemTemp.createTemp(
        'listen-realtime-audio-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bridge = RealtimeAudioBridge(
        methods: channel,
        recordingsDirectory: directory,
      );

      await bridge.start(inputSampleRateHz: 16000);

      expect(calls, ['requestPermission', 'start']);
    },
  );

  test(
    'realtime audio stops before capture when permission is denied',
    () async {
      const channel = MethodChannel('test/realtime_audio_denied');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestPermission') return false;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final directory = await Directory.systemTemp.createTemp(
        'listen-realtime-audio-denied-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bridge = RealtimeAudioBridge(
        methods: channel,
        recordingsDirectory: directory,
      );

      await expectLater(
        bridge.start(inputSampleRateHz: 16000),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'microphone_permission')
              .having(
                (error) => error.message,
                'message',
                contains('System Settings'),
              ),
        ),
      );

      expect(calls, ['requestPermission']);
      await bridge.cancel();
      expect(calls, ['requestPermission']);
    },
  );

  test(
    'cancel during permission prevents a late native microphone start',
    () async {
      const channel = MethodChannel('test/realtime_audio_cancel_permission');
      final calls = <String>[];
      final permissionRequest = Completer<void>();
      final permissionResult = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestPermission') {
              permissionRequest.complete();
              return permissionResult.future;
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final directory = await Directory.systemTemp.createTemp(
        'listen-realtime-audio-cancel-permission-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bridge = RealtimeAudioBridge(
        methods: channel,
        recordingsDirectory: directory,
      );

      final start = bridge.start(inputSampleRateHz: 16000);
      await permissionRequest.future;
      final cancel = bridge.cancel();
      permissionResult.complete(true);
      await Future.wait([start, cancel]);

      expect(calls, ['requestPermission', 'cancel']);
    },
  );

  test(
    'cancel waits for native start then releases the opened capture',
    () async {
      const channel = MethodChannel('test/realtime_audio_cancel_start');
      final calls = <String>[];
      final startRequest = Completer<void>();
      final nativeStartResult = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestPermission') return true;
            if (call.method == 'start') {
              startRequest.complete();
              return nativeStartResult.future;
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final directory = await Directory.systemTemp.createTemp(
        'listen-realtime-audio-cancel-start-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bridge = RealtimeAudioBridge(
        methods: channel,
        recordingsDirectory: directory,
      );

      final start = bridge.start(inputSampleRateHz: 16000);
      await startRequest.future;
      final cancel = bridge.cancel();
      nativeStartResult.complete(true);
      await Future.wait([start, cancel]);

      expect(calls, ['requestPermission', 'start', 'cancel']);
    },
  );

  test(
    'stop validates the captured file and removes an unreadable artifact',
    () async {
      const channel = MethodChannel('test/realtime_audio_stop_read_failure');
      final directory = await Directory.systemTemp.createTemp(
        'listen-realtime-audio-stop-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final missingPath = p.join(directory.path, 'missing.wav');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'requestPermission') return true;
            if (call.method == 'stop') {
              return {'path': missingPath, 'durationMs': 1200};
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bridge = RealtimeAudioBridge(
        methods: channel,
        recordingsDirectory: directory,
      );

      await bridge.start(inputSampleRateHz: 16000);
      await expectLater(bridge.stop(), throwsA(isA<FileSystemException>()));

      expect(await File(missingPath).exists(), isFalse);
      await bridge.shutdown();
    },
  );
}
