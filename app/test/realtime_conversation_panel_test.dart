import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';
import 'package:llplayer_next/widgets/settings/realtime_provider_settings.dart';

void main() {
  test('new realtime profiles use Qwen full-duplex as the baseline', () {
    expect(qwenRealtimeBaselineModel, 'qwen3.5-omni-plus-realtime');
  });

  test('OpenAI realtime remains available as a reference provider', () {
    expect(openAiRealtimeBaselineModel, 'gpt-realtime-2.1');
  });

  test('history title comes from conversation turns, not media topic', () {
    final session = _session().withTurns([
      const RealtimeConversationItem(
        sequence: 1,
        role: 'learner',
        status: 'finalized',
        startedAtMs: 1,
        localText: 'What should schools do in an emergency?',
      ),
    ]);

    expect(
      realtimeHistoryTitle(session),
      'What should schools do in an emergency?',
    );
    expect(realtimeHistoryTitle(session), isNot('Media subtitle snapshot'));
  });

  test('failed zero-turn sessions do not masquerade as conversations', () {
    expect(
      realtimeHistoryTitle(_session().withTurns(const [])),
      'No conversation captured',
    );
  });

  testWidgets('the lobby offers a voice choice, not a configuration form', (
    tester,
  ) async {
    var manageVoicesTaps = 0;
    final controller = RealtimeConversationController(audio: _FakeAudio());
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (method == 'GET' && path == '/v1/realtime/providers') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'id': 'profile-long',
                'display_name': 'Realtime provider',
                'adapter_kind': 'qwen_omni_realtime',
                'base_url': 'wss://example.com/api-ws/v1/realtime',
                'model_id': qwenRealtimeBaselineModel,
                'voice': 'Tina',
                'has_credential': true,
                'timeout_ms': 30000,
              },
            ]),
          );
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
          onManageVoices: () async => manageVoicesTaps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Voice, not model plumbing: the lobby asks only who speaks with you,
    // and long names ellipsize instead of overflowing the row (#87).
    expect(tester.takeException(), isNull);
    expect(find.text('Realtime provider · Tina'), findsOneWidget);
    expect(find.text('Which voice speaks with you'), findsOneWidget);

    // The endpoint/workspace/region/API-key form now lives in settings.
    expect(find.text('Add provider'), findsNothing);
    expect(find.widgetWithText(TextField, 'WebSocket endpoint'), findsNothing);
    expect(find.widgetWithText(TextField, 'Workspace ID'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('realtime-manage-voices')));
    await tester.pumpAndSettle();
    expect(manageVoicesTaps, 1);

    controller.dispose();
  });

  testWidgets('with no voice configured the lobby points at settings instead '
      'of dead-ending', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
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
          onManageVoices: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No realtime voice configured yet. '
        'Add one in Settings › Realtime voice.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('realtime-manage-voices')),
      findsOneWidget,
    );

    controller.dispose();
  });
}

RealtimeConversationSessionView _session() =>
    const RealtimeConversationSessionView(
      id: 'session-1',
      profileId: 'profile-1',
      language: 'en',
      surfaceKind: 'topic_anchored',
      status: 'failed',
      startedAtMs: 1,
      topic: 'Media subtitle snapshot',
    );

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
