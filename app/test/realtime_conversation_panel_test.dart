import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/localization.dart';
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

  test('a history row is named by when it happened, how long it ran and how '
      'many turns it took — never by what was said first', () {
    final session =
        _session(
          status: 'completed',
          startedAtMs: DateTime(2026, 7, 28, 14, 43).millisecondsSinceEpoch,
          endedAtMs: DateTime(2026, 7, 28, 14, 46).millisecondsSinceEpoch,
        ).withTurns([
          const RealtimeConversationItem(
            sequence: 1,
            role: 'learner',
            status: 'finalized',
            startedAtMs: 1,
            localText: 'Hello',
          ),
          const RealtimeConversationItem(
            sequence: 2,
            role: 'assistant',
            status: 'finalized',
            startedAtMs: 2,
            providerText: 'Hello! How are you doing today?',
          ),
        ]);

    final title = realtimeHistoryTitle(session, _en);
    expect(title, '7/28 14:43 · 3 min · 2 turns');
    // The opening utterance is what made five of six rows read "Hello"; it is
    // no longer what identifies a conversation.
    expect(title, isNot(contains('Hello')));
    // A conversation that ended normally carries no badge at all, and the raw
    // status enum never reaches the screen.
    expect(title, isNot(contains('completed')));
  });

  test('an abnormal outcome is described, never printed as its raw enum', () {
    for (final (status, described) in const [
      ('failed', 'ended with an error'),
      ('interrupted', 'left partway'),
      ('active', 'never finished'),
    ]) {
      final title = realtimeHistoryTitle(
        _session(status: status).withTurns([
          const RealtimeConversationItem(
            sequence: 1,
            role: 'learner',
            status: 'finalized',
            startedAtMs: 1,
            localText: 'Hello',
          ),
        ]),
        _en,
      );
      expect(title, contains(described));
      expect(title, isNot(contains(status)));
    }
    // An outcome this build has never heard of contributes nothing rather
    // than leaking the token.
    expect(realtimeHistoryStatusText('some_new_backend_status', _en), isNull);
  });

  test('a session that recorded nothing says so instead of claiming a '
      'duration or a turn count', () {
    final title = realtimeHistoryTitle(
      _session(status: 'failed').withTurns(const []),
      _en,
    );
    expect(title, contains('nothing was captured'));
    expect(title, isNot(contains('turns')));
    expect(title, isNot(contains('min')));
  });

  test('a session with no end timestamp states no duration rather than '
      'guessing one', () {
    final title = realtimeHistoryTitle(
      _session(status: 'active').withTurns([
        const RealtimeConversationItem(
          sequence: 1,
          role: 'learner',
          status: 'finalized',
          startedAtMs: 1,
          localText: 'Hello',
        ),
      ]),
      _en,
    );
    expect(title, isNot(contains('min')));
    expect(title, contains('1 turns'));
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

    // First glance: an invitation and one action. Not a form.
    expect(tester.takeException(), isNull);
    expect(find.text('Ready when you are'), findsOneWidget);
    final start = find.byKey(const ValueKey('realtime-start'));
    expect(start, findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Start conversation'),
      findsOneWidget,
    );
    // The one primary action is the biggest control on the screen.
    expect(tester.getSize(start).height, greaterThanOrEqualTo(56));

    // The voice is a line of text you may tap, not a dropdown demanding a
    // decision before you are allowed to speak.
    expect(
      find.text('In the voice of Realtime provider · Tina'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    // The picker (and the way to settings) only exist once asked for.
    expect(find.byKey(const ValueKey('realtime-manage-voices')), findsNothing);

    // The endpoint/workspace/region/API-key form lives in settings (#87).
    expect(find.text('Add provider'), findsNothing);
    expect(find.widgetWithText(TextField, 'WebSocket endpoint'), findsNothing);
    expect(find.widgetWithText(TextField, 'Workspace ID'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('realtime-voice-choice')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('realtime-voice-option-profile-long')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('realtime-manage-voices')));
    await tester.pumpAndSettle();
    expect(manageVoicesTaps, 1);

    controller.dispose();
  });

  testWidgets('the lobby shows the last five conversations and folds the '
      'rest behind 全部对话', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (method == 'GET' && path == '/v1/realtime/providers') {
          return (statusCode: 200, body: '[]');
        }
        if (method == 'GET' && path == '/v1/realtime/sessions') {
          return (
            statusCode: 200,
            body: jsonEncode([
              for (var index = 0; index < 7; index++)
                {
                  'id': 'session-$index',
                  'profile_id': 'profile-1',
                  'language': 'en',
                  'status': 'completed',
                  'started_at_ms': DateTime(
                    2026,
                    7,
                    28,
                    10 + index,
                  ).millisecondsSinceEpoch,
                  'ended_at_ms': DateTime(
                    2026,
                    7,
                    28,
                    10 + index,
                    5,
                  ).millisecondsSinceEpoch,
                  'context': {'surface_kind': 'open_chat'},
                },
            ]),
          );
        }
        if (method == 'GET' && path.endsWith('/turns')) {
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

    expect(find.byType(ListTile), findsNWidgets(5));
    final showAll = find.byKey(const ValueKey('realtime-history-show-all'));
    expect(showAll, findsOneWidget);

    await tester.ensureVisible(showAll);
    await tester.pumpAndSettle();
    await tester.tap(showAll);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(7));

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

const _en = AppLocalizations(Locale('en'));

RealtimeConversationSessionView _session({
  String status = 'failed',
  int startedAtMs = 1,
  int? endedAtMs,
}) => RealtimeConversationSessionView(
  id: 'session-1',
  profileId: 'profile-1',
  language: 'en',
  surfaceKind: 'topic_anchored',
  status: status,
  startedAtMs: startedAtMs,
  endedAtMs: endedAtMs,
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
