import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

const _workspaceErrorText = 'Enter the Workspace ID to complete the endpoint.';

void main() {
  testWidgets('saving without a Qwen workspace ID reports the missing field '
      'instead of silently doing nothing', (tester) async {
    // The provider dialog stacks eight fields; give it room so the test
    // exercises feedback, not viewport overflow.
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final registerBodies = <Map<String, dynamic>>[];
    final controller = RealtimeConversationController(audio: _FakeAudio());
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (method == 'GET' && path == '/v1/realtime/providers') {
          return (
            statusCode: 200,
            body: registerBodies.isEmpty ? '[]' : '[${_profileJson()}]',
          );
        }
        if (method == 'POST' && path == '/v1/realtime/providers') {
          registerBodies.add(jsonDecode(body!) as Map<String, dynamic>);
          return (statusCode: 200, body: _profileJson());
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

    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    expect(find.text('Add realtime provider'), findsOneWidget);

    // The default Qwen endpoint still carries the <workspace-id>
    // placeholder: saving must surface the missing field and keep the
    // dialog open rather than no-op silently.
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(find.text(_workspaceErrorText), findsOneWidget);
    expect(find.text('Add realtime provider'), findsOneWidget);
    expect(registerBodies, isEmpty);

    // Typing a workspace ID clears the error and unblocks saving.
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace ID'),
      'ws-123',
    );
    await tester.pumpAndSettle();
    expect(find.text(_workspaceErrorText), findsNothing);

    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(find.text('Add realtime provider'), findsNothing);
    expect(registerBodies, hasLength(1));
    expect(
      registerBodies.single['base_url'],
      'wss://ws-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
    );

    controller.dispose();
  });
}

// Short display/model strings: the panel's provider dropdown lacks
// `isExpanded`, so realistically long labels overflow its row and fail the
// test on an unrelated layout bug.
String _profileJson() => jsonEncode({
  'id': 'profile-1',
  'display_name': 'Qwen',
  'adapter_kind': 'qwen_omni_realtime',
  'base_url': 'wss://ws-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
  'model_id': 'qwen',
  'voice': 'Tina',
  'has_credential': true,
  'timeout_ms': 30000,
});

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
