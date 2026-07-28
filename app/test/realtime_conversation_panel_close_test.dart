import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

void main() {
  testWidgets('route back confirms before cancelling an active conversation', (
    tester,
  ) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    controller.state = const RealtimeConversationState(
      phase: RealtimeConversationPhase.live,
      activity: RealtimeConversationActivity.listening,
      selectedProfileId: 'profile-1',
    );
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
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (routeContext) => RealtimeConversationPanel(
                  controller: controller,
                  api: api,
                  launch: RealtimeConversationLaunch.free(
                    language: 'en',
                    modelId: 'asr-model',
                  ),
                  acquireAudioFocus: () async {},
                  onClose: () => Navigator.pop(routeContext),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    // The live stage breathes at the ambient tempo (#83 S6), so it never
    // reaches a settled frame: pump fixed durations instead of settling.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Discard this conversation?'), findsOneWidget);

    await tester.tap(find.text('Keep talking'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RealtimeConversationPanel), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Discard and close'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RealtimeConversationPanel), findsNothing);
    expect(controller.state.phase, RealtimeConversationPhase.idle);
    controller.dispose();
  });
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
