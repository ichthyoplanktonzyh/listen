import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/data/repositories/realtime_conversation_repository.dart';
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
              {
                'id': 'profile-alt',
                'display_name': 'Alt provider',
                'adapter_kind': 'open_ai_realtime',
                'base_url': 'wss://example.com/api-ws/v1/realtime',
                'model_id': openAiRealtimeBaselineModel,
                'voice': 'Aria',
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
    final controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: _FakeAudio(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RealtimeConversationPanel(
          controller: controller,
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

    // First glance: the design's 门厅 — one heading naming the room, one
    // line naming the voice, one action. Not a configuration form.
    expect(tester.takeException(), isNull);
    expect(find.text('Listen Live'), findsOneWidget);
    expect(find.text('Immersive realtime voice conversation'), findsOneWidget);
    final start = find.byKey(const ValueKey('realtime-start'));
    expect(start, findsOneWidget);
    // The one primary action is the biggest control on the screen.
    expect(tester.getSize(start).height, greaterThanOrEqualTo(56));

    // The voice is a plain dropdown inside the settings card, not a form
    // field and not a settings page.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final dropdown = find.byType(DropdownButton<String>);
    expect(dropdown, findsOneWidget);
    expect(find.text('Realtime provider · Tina · cloud'), findsOneWidget);
    expect(find.byKey(const ValueKey('realtime-manage-voices')), findsNothing);

    // Selecting another voice takes effect immediately.
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt provider · Aria · cloud').last);
    await tester.pumpAndSettle();
    expect(controller.state.selectedProfileId, 'profile-alt');
    expect(find.text('Alt provider · Aria · cloud'), findsOneWidget);

    // The endpoint/workspace/region/API-key form lives in settings (#87).
    expect(find.text('Add provider'), findsNothing);
    expect(find.widgetWithText(TextField, 'WebSocket endpoint'), findsNothing);
    expect(find.widgetWithText(TextField, 'Workspace ID'), findsNothing);

    controller.dispose();
  });

  testWidgets('the lobby names local versus cloud before the voice is chosen', (
    tester,
  ) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (method == 'GET' && path == '/v1/realtime/providers') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'id': 'profile-cloud',
                'display_name': 'Cloud voice',
                'adapter_kind': 'qwen_omni_realtime',
                'base_url': 'wss://example.com/api-ws/v1/realtime',
                'model_id': qwenRealtimeBaselineModel,
                'voice': 'marin',
                'has_credential': true,
                'timeout_ms': 30000,
              },
              {
                'id': 'profile-local',
                'display_name': 'Local voice',
                'adapter_kind': 'local_cascade_realtime',
                'base_url': 'ws://127.0.0.1:8765/v1/realtime',
                'model_id': localRealtimeBaselineModel,
                'voice': 'default',
                'has_credential': false,
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
    final controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: _FakeAudio(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RealtimeConversationPanel(
          controller: controller,
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

    // The panel auto-picks the first voice; its one-line hint names what the
    // chosen voice is before anyone commits to speaking.
    expect(find.byKey(const ValueKey('realtime-provider-hint')), findsOneWidget);
    expect(
      find.text('Cloud voices process audio on the provider side and bill by usage.'),
      findsOneWidget,
    );

    // The picker itself tells the two kinds of voice apart. The auto-selected
    // cloud voice appears twice while open (button + menu item); the local
    // voice only in the menu.
    final dropdown = find.byType(DropdownButton<String>);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Cloud voice · marin · cloud'), findsNWidgets(2));
    expect(find.text('Local voice · default · local'), findsOneWidget);

    // Choosing the local voice swaps the hint to its privacy guarantee.
    await tester.tap(find.text('Local voice · default · local').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Local voice stays on this machine — no key, no cloud, fully offline.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Cloud voices process audio on the provider side and bill by usage.'),
      findsNothing,
    );

    // Choosing the cloud voice states its billing reality instead.
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloud voice · marin · cloud').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Cloud voices process audio on the provider side and bill by usage.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Local voice stays on this machine — no key, no cloud, fully offline.',
      ),
      findsNothing,
    );

    controller.dispose();
  });

  testWidgets('under a Chinese UI the lobby is Chinese — no mixed-language '
      'screen', (tester) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (method == 'GET' && path == '/v1/realtime/providers') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'id': 'profile-1',
                'display_name': 'test',
                'adapter_kind': 'qwen_omni_realtime',
                'base_url': 'wss://example.com/api-ws/v1/realtime',
                'model_id': qwenRealtimeBaselineModel,
                'voice': 'marin',
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
    final controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: _FakeAudio(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RealtimeConversationPanel(
          controller: controller,
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

    expect(find.text('对话 · Live 态'), findsOneWidget);
    expect(find.text('全屏沉浸式实时语音对话'), findsOneWidget);
    expect(find.text('对话角色音色'), findsOneWidget);
    expect(find.text('对方说话的声音风格'), findsOneWidget);
    expect(find.text('余音字幕'), findsOneWidget);
    expect(find.text('对方说话时显示淡出字幕'), findsOneWidget);
    expect(find.text('test · marin · 云端'), findsOneWidget);
    expect(find.text('开始对话'), findsOneWidget);
    // The English that used to sit on the same screen as the Chinese.
    for (final english in const [
      'Free conversation',
      'Listen Live',
      'Voice persona',
      'Afterglow Captions',
      'Start conversation',
      'Conversation history',
    ]) {
      expect(find.text(english), findsNothing);
    }

    controller.dispose();
  });

  testWidgets('the lobby shows the last five conversations and folds the '
      'rest behind 全部对话', (tester) async {
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
    final controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: _FakeAudio(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RealtimeConversationPanel(
          controller: controller,
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

    // History lives in the drawer (design note · 方案三), opened from the
    // app bar — the past is not stacked on top of the start action.
    expect(find.byType(ListTile), findsNothing);
    await tester.tap(find.byKey(const ValueKey('realtime-history-open')));
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
    final controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: _FakeAudio(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RealtimeConversationPanel(
          controller: controller,
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
