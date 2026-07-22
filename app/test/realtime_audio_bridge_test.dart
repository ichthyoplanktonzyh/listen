import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final bridge = RealtimeAudioBridge(methods: channel);

      await bridge.start();

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
      final bridge = RealtimeAudioBridge(methods: channel);

      await expectLater(
        bridge.start(),
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
}
