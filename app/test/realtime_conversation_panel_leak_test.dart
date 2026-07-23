import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

/// #27: the "Add provider" dialog builds six TextEditingControllers per open
/// (one of them holding the API key). Every open must release all six — the
/// leak tracker fails this test if any survives undisposed.
void main() {
  LeakTesting.enable();

  testWidgets(
    'reopening the provider dialog leaks no controllers',
    experimentalLeakTesting: LeakTesting.settings.withTrackedAll().withIgnored(
      // The trailing empty frame is still mounted when the test ends; its
      // own two framework objects are not what this test is guarding.
      notDisposed: {
        'SingleChildRenderObjectElement': 1,
        'RenderConstrainedBox': 1,
      },
    ),
    (tester) async {
      // The provider dialog is taller than the default 800×600 test surface;
      // give it a desktop-sized window so it lays out without overflowing.
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = RealtimeConversationController(audio: _FakeAudio());
      addTearDown(controller.dispose);
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          if (method == 'GET' && path == '/v1/realtime/providers') {
            return (statusCode: 200, body: '[]');
          }
          if (method == 'GET' && path == '/v1/realtime/sessions') {
            return (statusCode: 200, body: '[]');
          }
          throw StateError('Unexpected request: $method $path ${body ?? ''}');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RealtimeConversationPanel(
            controller: controller,
            api: api,
            launch: RealtimeConversationLaunch.free(
              language: 'en',
              modelId: 'asr-model',
            ),
            acquireAudioFocus: () async {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var round = 0; round < 3; round++) {
        await tester.tap(find.text('Add provider'));
        await tester.pumpAndSettle();
        expect(find.text('Add realtime provider'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Add realtime provider'), findsNothing);
      }

      // Unmount the tree so the only undisposed objects left are real leaks.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _FakeAudio implements RealtimeAudioSession {
  @override
  Stream<Uint8List> get pcmInput => const Stream.empty();

  @override
  Future<void> start({required int inputSampleRateHz}) async {}

  @override
  Future<void> beginTurn(String turnId, {int? audioStartMs}) async {}

  @override
  Future<CapturedRecording> endTurn() => throw UnimplementedError();

  @override
  Future<void> discardTurn() async {}

  @override
  Future<void> play(Uint8List pcm) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<CapturedRecording> stop() => throw UnimplementedError();

  @override
  Future<void> cancel() async {}
}
