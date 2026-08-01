import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/data/repositories/realtime_conversation_repository.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';

void main() {
  group('RealtimeConversationController', () {
    test('acquires microphone before opening the provider socket', () async {
      final harness = _Harness(transcripts: const []);

      await harness.start();

      expect(harness.lifecycle.take(3), [
        'audio_focus',
        'audio_start',
        'provider_connect',
      ]);
      expect(harness.audio.inputSampleRateHz, 24000);
      await harness.controller.cancel();
    });

    test('negotiates Qwen microphone input at 16 kHz', () async {
      final harness = _Harness(
        transcripts: const [],
        adapterKind: 'qwen_omni_realtime',
      );

      await harness.start();

      expect(harness.audio.inputSampleRateHz, 16000);
      await harness.controller.cancel();
    });

    test(
      'assembles and persists ordered multi-turn conversation history',
      () async {
        final harness = _Harness(
          transcripts: ['first learner', 'second learner'],
        );
        await harness.start();

        await harness.learnerTurn('user-1', 'provider first');
        await harness.assistantTurn('assistant-1', 'First reply');
        await harness.learnerTurn('user-2', 'provider second');
        await harness.assistantTurn('assistant-2', 'Second reply');
        await harness.finish();

        expect(harness.controller.state.items.map((item) => item.role), [
          'learner',
          'assistant',
          'learner',
          'assistant',
        ]);
        expect(harness.controller.state.items.map((item) => item.sequence), [
          1,
          2,
          3,
          4,
        ]);
        expect(
          harness.controller.state.items
              .where((item) => item.role == 'learner')
              .map((item) => item.localText),
          ['first learner', 'second learner'],
        );
        expect(harness.savedTurns.map((turn) => turn['sequence']).toSet(), {
          1,
          2,
          3,
          4,
        });
        expect(
          harness.savedTurns
              .where((turn) => turn['role'] == 'learner')
              .where((turn) => turn['status'] == 'finalized')
              .length,
          2,
        );
        expect(harness.lastSessionStatus, 'completed');
        expect(harness.audio.beginTurnCount, 2);
        expect(harness.audio.endTurnCount, 2);
        expect(
          harness.recordingRequests.map(
            (request) => (request['target'] as Map<String, dynamic>)['kind'],
          ),
          everyElement('segment'),
        );
      },
    );

    test(
      'keeps session completed when one local learner transcription fails',
      () async {
        final harness = _Harness(transcripts: ['kept learner output', null]);
        await harness.start();

        await harness.learnerTurn('user-1', 'provider first');
        await harness.assistantTurn('assistant-1', 'First reply');
        await harness.learnerTurn('user-2', 'provider second');
        await harness.assistantTurn('assistant-2', 'Second reply');
        await harness.finish();

        final learners = harness.controller.state.items
            .where((item) => item.role == 'learner')
            .toList();
        expect(learners[0].status, 'finalized');
        expect(learners[0].localText, 'kept learner output');
        expect(learners[1].status, 'failed');
        expect(harness.lastSessionStatus, 'completed');
        expect(
          harness.savedTurns
              .where((turn) => turn['role'] == 'learner')
              .where((turn) => turn['status'] == 'finalized')
              .length,
          1,
        );
      },
    );

    test('deduplicates repeated provider turn boundary events', () async {
      final harness = _Harness(transcripts: ['one learner']);
      await harness.start();

      harness.connection.emit(_event('speech_started', 'user-1'));
      harness.connection.emit(_event('speech_started', 'user-1'));
      await _settle();
      harness.connection.emit(_event('speech_stopped', 'user-1'));
      harness.connection.emit(_event('speech_stopped', 'user-1'));
      await _settle();
      await harness.assistantTurn(
        'assistant-1',
        'Only reply',
        duplicateFinal: true,
      );
      await harness.finish();

      expect(harness.controller.state.items.length, 2);
      expect(harness.audio.beginTurnCount, 1);
      expect(harness.audio.endTurnCount, 1);
      expect(
        harness.savedTurns.where((turn) => turn['role'] == 'assistant').length,
        1,
      );
    });

    test(
      'preserves provider speech onset when beginning local capture',
      () async {
        final harness = _Harness(transcripts: const []);
        await harness.start();

        harness.connection.emit(
          jsonEncode({
            'type': 'speech_started',
            'provider_item_id': 'user-1',
            'audio_start_ms': 3647,
          }),
        );
        await _settle();

        expect(harness.audio.beginTurnAudioStartMs, [3647]);
        await harness.controller.cancel();
      },
    );

    test('forwards every captured PCM frame to the provider socket', () async {
      final harness = _Harness(
        transcripts: const [],
        adapterKind: 'qwen_omni_realtime',
      );
      await harness.start();
      final pcm = Uint8List.fromList([0, 1, 2, 3]);

      harness.audio.emit(pcm);
      await _settle();

      expect(harness.connection.sent, contains(same(pcm)));
      await harness.controller.cancel();
    });

    test('publishes voice activity separately from committed turns', () async {
      final harness = _Harness(transcripts: const ['learner']);
      await harness.start();
      expect(
        harness.controller.state.activity,
        RealtimeConversationActivity.listening,
      );

      harness.connection.emit(_event('speech_started', 'user-1'));
      await _settle();
      expect(
        harness.controller.state.activity,
        RealtimeConversationActivity.learnerSpeaking,
      );

      harness.connection.emit(_event('speech_stopped', 'user-1'));
      await _settle();
      expect(
        harness.controller.state.activity,
        RealtimeConversationActivity.thinking,
      );

      harness.connection.emit(
        jsonEncode({
          'type': 'assistant_transcript_delta',
          'provider_item_id': 'assistant-1',
          'delta': 'Hello',
        }),
      );
      await _settle();
      expect(
        harness.controller.state.activity,
        RealtimeConversationActivity.assistantSpeaking,
      );

      harness.connection.emit(jsonEncode({'type': 'response_done'}));
      await _settle();
      expect(
        harness.controller.state.activity,
        RealtimeConversationActivity.listening,
      );
      await harness.controller.cancel();
    });

    test(
      'barge-in interrupts and persists the active assistant item',
      () async {
        final harness = _Harness(transcripts: ['first learner']);
        await harness.start();
        await harness.learnerTurn('user-1', 'provider first');
        harness.connection.emit(
          jsonEncode({
            'type': 'assistant_transcript_delta',
            'provider_item_id': 'assistant-1',
            'delta': 'unfinished reply',
          }),
        );
        await _settle();

        harness.connection.emit(_event('speech_started', 'user-2'));
        await _settle();

        final assistant = harness.controller.state.items.singleWhere(
          (item) => item.role == 'assistant',
        );
        expect(assistant.status, 'interrupted');
        expect(
          harness.savedTurns.any(
            (turn) =>
                turn['role'] == 'assistant' && turn['status'] == 'interrupted',
          ),
          isTrue,
        );
        await harness.controller.cancel();
      },
    );

    test(
      'cancel closes an active learner without starting local ASR',
      () async {
        final harness = _Harness(transcripts: const []);
        await harness.start();
        harness.connection.emit(_event('speech_started', 'user-1'));
        await _settle();

        await harness.controller.cancel();

        expect(harness.controller.state.phase, RealtimeConversationPhase.idle);
        expect(harness.controller.state.items.single.status, 'interrupted');
        expect(harness.recordingRequests, isEmpty);
        expect(
          harness.savedTurns.singleWhere(
            (turn) => turn['role'] == 'learner',
          )['status'],
          'interrupted',
        );
        expect(harness.lastSessionStatus, 'interrupted');
      },
    );

    test(
      'finish flushes an assistant transcript after response done',
      () async {
        final harness = _Harness(transcripts: ['learner']);
        await harness.start();
        await harness.learnerTurn('user-1', 'provider learner');
        harness.connection.emit(
          jsonEncode({
            'type': 'assistant_transcript_delta',
            'provider_item_id': 'assistant-1',
            'delta': 'drained reply',
          }),
        );
        await _settle();

        await harness.finish();

        final assistant = harness.controller.state.items.singleWhere(
          (item) => item.role == 'assistant',
        );
        expect(assistant.status, 'finalized');
        expect(assistant.providerText, 'drained reply');
        expect(
          harness.savedTurns.any(
            (turn) =>
                turn['role'] == 'assistant' && turn['status'] == 'finalized',
          ),
          isTrue,
        );
      },
    );

    test(
      'provider drain timeout preserves partial assistant as interrupted',
      () async {
        final harness = _Harness(
          transcripts: const ['learner'],
          providerDrainTimeout: Duration.zero,
        );
        await harness.start();
        await harness.learnerTurn('user-1', 'provider learner');
        harness.connection.emit(
          jsonEncode({
            'type': 'assistant_transcript_delta',
            'provider_item_id': 'assistant-1',
            'delta': 'partial reply',
          }),
        );
        await _settle();

        await harness.controller.finish();

        expect(harness.controller.state.phase, RealtimeConversationPhase.done);
        expect(
          harness.savedTurns.any(
            (turn) =>
                turn['role'] == 'assistant' &&
                turn['status'] == 'interrupted' &&
                turn['failure_kind'] == 'provider_drain_timeout',
          ),
          isTrue,
        );
        expect(harness.lastSessionStatus, 'completed');
      },
    );

    test('cancel fences a learner turn waiting to poll local ASR', () async {
      final harness = _Harness(
        transcripts: const ['must not finalize'],
        holdTranscription: true,
      );
      await harness.start();
      await harness.learnerTurn('user-1', 'provider learner');
      expect(harness.controller.state.postProcessingCount, 1);

      await harness.controller.cancel();
      harness.transcriptionGate.complete();
      await _settle();

      expect(harness.controller.state.phase, RealtimeConversationPhase.idle);
      expect(harness.controller.state.postProcessingCount, 0);
      expect(harness.controller.state.items.single.status, 'interrupted');
      expect(
        harness.savedTurns.where((turn) => turn['status'] == 'finalized'),
        isEmpty,
      );
      expect(harness.lastSessionStatus, 'interrupted');
    });

    test(
      'a failed provider connection can retry without stale session state',
      () async {
        final harness = _Harness(transcripts: const [], connectFailures: 1);
        await harness.controller.loadProfiles();

        await harness.controller.start(
          RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
          acquireAudioFocus: () async {},
        );
        expect(
          harness.controller.state.phase,
          RealtimeConversationPhase.failed,
        );

        await harness.controller.start(
          RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
          acquireAudioFocus: () async {},
        );

        expect(harness.controller.state.phase, RealtimeConversationPhase.live);
        expect(harness.controller.state.items, isEmpty);
        expect(harness.controller.state.postProcessingCount, 0);
        expect(
          harness.controller.state.activity,
          RealtimeConversationActivity.listening,
        );
        await harness.controller.cancel();
      },
    );

    test(
      'a failed microphone start can retry without stale session state',
      () async {
        final harness = _Harness(transcripts: const [], audioStartFailures: 1);
        await harness.controller.loadProfiles();

        await harness.controller.start(
          RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
          acquireAudioFocus: () async {},
        );
        expect(
          harness.controller.state.phase,
          RealtimeConversationPhase.failed,
        );
        expect(harness.lifecycle, isNot(contains('provider_connect')));

        await harness.controller.start(
          RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
          acquireAudioFocus: () async {},
        );

        expect(harness.controller.state.phase, RealtimeConversationPhase.live);
        expect(harness.controller.state.items, isEmpty);
        expect(harness.controller.state.postProcessingCount, 0);
        expect(
          harness.controller.state.activity,
          RealtimeConversationActivity.listening,
        );
        await harness.controller.cancel();
      },
    );

    test(
      'resetToIdle drops a finished conversation but keeps the chosen voice',
      () async {
        final harness = _Harness(
          transcripts: const ['learner'],
          providerDrainTimeout: Duration.zero,
        );
        await harness.start();
        await harness.learnerTurn('user-1', 'provider learner');
        await harness.assistantTurn('assistant-1', 'A reply');
        await harness.controller.finish();

        expect(harness.controller.state.phase, RealtimeConversationPhase.done);
        expect(harness.controller.state.items, isNotEmpty);
        final profiles = harness.controller.state.profiles;
        final selected = harness.controller.state.selectedProfileId;

        harness.controller.resetToIdle();

        // The controller outlives the route, so a terminal state left in place
        // would re-render the previous debrief on re-entry. What a returning
        // user must not lose is the voice they already picked.
        expect(harness.controller.state.phase, RealtimeConversationPhase.idle);
        expect(harness.controller.state.items, isEmpty);
        expect(harness.controller.state.profiles, profiles);
        expect(harness.controller.state.selectedProfileId, selected);
      },
    );

    test(
      'resetToIdle refuses to discard a conversation that is still live',
      () async {
        final harness = _Harness(transcripts: const ['learner']);
        await harness.start();
        await harness.learnerTurn('user-1', 'provider learner');

        expect(harness.controller.state.phase, RealtimeConversationPhase.live);
        final items = harness.controller.state.items;
        expect(items, isNotEmpty);

        harness.controller.resetToIdle();

        // canConfigure is the only state where dropping the turns cannot lose
        // anything; a live session is never silently discarded.
        expect(harness.controller.state.phase, RealtimeConversationPhase.live);
        expect(harness.controller.state.items, items);
        await harness.controller.cancel();
      },
    );
  });
}

class _Harness {
  _Harness({
    required List<String?> transcripts,
    this.adapterKind = 'open_ai_realtime',
    this.connectFailures = 0,
    this.audioStartFailures = 0,
    this.holdTranscription = false,
    this.providerDrainTimeout = const Duration(seconds: 15),
  }) : _transcripts = List<String?>.from(transcripts) {
    audio = _FakeAudio(
      onStart: () => lifecycle.add('audio_start'),
      startFailures: audioStartFailures,
    );
    controller = RealtimeConversationController(
      repository: LocalRealtimeConversationRepository(() => api),
      audio: audio,
      connect: (_, _) async {
        lifecycle.add('provider_connect');
        if (connectFailures > 0) {
          connectFailures--;
          throw StateError('fixture connection failure');
        }
        return connection;
      },
      delay: (_) =>
          holdTranscription ? transcriptionGate.future : Future<void>.value(),
      nowMs: _clock,
      providerDrainTimeout: providerDrainTimeout,
    );
    api = LocalApi.withTransport(
      baseUrl: 'http://127.0.0.1:4321',
      token: 'test-token',
      transport: _transport,
    );
  }

  static int _time = 1000;
  static int _clock() => _time++;

  final List<String?> _transcripts;
  final String adapterKind;
  int connectFailures;
  final int audioStartFailures;
  final bool holdTranscription;
  final Duration providerDrainTimeout;
  final Completer<void> transcriptionGate = Completer<void>();
  late final RealtimeConversationController controller;
  late final _FakeAudio audio;
  late final LocalApi api;
  final _FakeConnection connection = _FakeConnection();
  final List<Map<String, dynamic>> savedTurns = [];
  final List<Map<String, dynamic>> savedSessions = [];
  final List<Map<String, dynamic>> recordingRequests = [];
  final List<String> lifecycle = [];
  int _recordingCount = 0;
  int _transcriptionCount = 0;

  String? get lastSessionStatus =>
      savedSessions.isEmpty ? null : savedSessions.last['status'] as String?;

  Future<void> start() async {
    await controller.loadProfiles();
    await controller.start(
      RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
      acquireAudioFocus: () async => lifecycle.add('audio_focus'),
    );
    expect(controller.state.phase, RealtimeConversationPhase.live);
  }

  Future<void> learnerTurn(String itemId, String providerText) async {
    connection.emit(_event('speech_started', itemId));
    await _settle();
    connection.emit(
      jsonEncode({
        'type': 'provider_transcript_final',
        'provider_item_id': itemId,
        'transcript': providerText,
      }),
    );
    connection.emit(_event('speech_stopped', itemId));
    await _settle();
  }

  Future<void> assistantTurn(
    String itemId,
    String text, {
    bool duplicateFinal = false,
  }) async {
    connection.emit(
      jsonEncode({
        'type': 'assistant_transcript_delta',
        'provider_item_id': itemId,
        'delta': text.substring(0, 1),
      }),
    );
    connection.emit(
      jsonEncode({
        'type': 'assistant_transcript_final',
        'provider_item_id': itemId,
        'transcript': text,
      }),
    );
    if (duplicateFinal) {
      connection.emit(
        jsonEncode({
          'type': 'assistant_transcript_final',
          'provider_item_id': itemId,
          'transcript': text,
        }),
      );
    }
    await _settle();
  }

  Future<void> finish() async {
    final future = controller.finish();
    for (var attempt = 0; attempt < 20 && audio.stopCount == 0; attempt++) {
      await _settle();
    }
    expect(audio.stopCount, 1);
    expect(connection.sent, isNot(contains('commit')));
    connection.emit(jsonEncode({'type': 'response_done'}));
    await future;
  }

  Future<ApiResponse> _transport(
    String method,
    String path,
    String? body,
  ) async {
    if (method == 'GET' && path == '/v1/realtime/providers') {
      return (
        statusCode: 200,
        body: jsonEncode([
          {
            'id': 'profile-1',
            'display_name': 'Test provider',
            'adapter_kind': adapterKind,
            'base_url': 'wss://example.invalid/realtime',
            'model_id': 'realtime-model',
            'voice': 'voice',
            'has_credential': true,
            'timeout_ms': 30000,
          },
        ]),
      );
    }
    if (method == 'POST' && path == '/v1/realtime/sessions') {
      savedSessions.add(jsonDecode(body!) as Map<String, dynamic>);
      return (statusCode: 200, body: '{}');
    }
    if (method == 'POST' && path == '/v1/realtime/turns') {
      savedTurns.add(jsonDecode(body!) as Map<String, dynamic>);
      return (statusCode: 200, body: '{}');
    }
    if (method == 'POST' && path == '/v1/recordings') {
      final request = jsonDecode(body!) as Map<String, dynamic>;
      recordingRequests.add(request);
      _recordingCount++;
      return (
        statusCode: 200,
        body: jsonEncode({
          ...request,
          'id': 'recording-$_recordingCount',
          'created_at_ms': _clock(),
          'practice_attempt_id': null,
        }),
      );
    }
    if (method == 'POST' && path == '/v1/recording-transcriptions') {
      final request = jsonDecode(body!) as Map<String, dynamic>;
      if (holdTranscription) {
        _transcriptionCount++;
        return (
          statusCode: 200,
          body: jsonEncode({
            ..._job(
              id: 'job-$_transcriptionCount',
              recordingId: request['recording_id'] as String,
              transcript: null,
            ),
            'status': 'running',
            'error_code': null,
            'error_message': null,
            'completed_at_ms': null,
          }),
        );
      }
      final transcript = _transcripts[_transcriptionCount++];
      return (
        statusCode: 200,
        body: jsonEncode(
          _job(
            id: 'job-$_transcriptionCount',
            recordingId: request['recording_id'] as String,
            transcript: transcript,
          ),
        ),
      );
    }
    throw StateError('Unexpected request: $method $path');
  }
}

Map<String, dynamic> _job({
  required String id,
  required String recordingId,
  required String? transcript,
}) => {
  'id': id,
  'recording_asset_id': recordingId,
  'status': transcript == null ? 'failed' : 'completed',
  'raw_transcript': transcript,
  'segments': <dynamic>[],
  'provenance': {
    'provider_id': 'local',
    'provider_version': '1',
    'runtime_id': 'whisper.cpp',
    'runtime_version': '1',
    'model_id': 'asr-model',
    'model_revision': '1',
    'model_checksum_sha256': 'model-sha',
    'recording_content_sha256': 'recording-sha',
    'requested_language': 'en',
    'detected_language': 'en',
  },
  'error_code': transcript == null ? 'transcription_failed' : null,
  'error_message': transcript == null ? 'fixture failure' : null,
  'created_at_ms': 1,
  'started_at_ms': 2,
  'completed_at_ms': 3,
  'latency_ms': 1,
};

String _event(String type, String providerItemId) =>
    jsonEncode({'type': type, 'provider_item_id': providerItemId});

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeConnection implements RealtimeConnection {
  final _messages = StreamController<Object?>.broadcast();
  final sent = <Object>[];
  bool _open = true;

  void emit(Object message) => _messages.add(message);

  @override
  bool get isOpen => _open;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  void send(Object data) => sent.add(data);

  @override
  Future<void> close() async {
    _open = false;
  }
}

class _FakeAudio implements RealtimeAudioSession {
  _FakeAudio({required this.onStart, required this.startFailures});

  final void Function() onStart;
  int startFailures;
  final _pcm = StreamController<Uint8List>.broadcast();
  int beginTurnCount = 0;
  final List<int?> beginTurnAudioStartMs = [];
  int endTurnCount = 0;
  int _turn = 0;
  int? inputSampleRateHz;
  int stopCount = 0;

  @override
  Stream<Uint8List> get pcmInput => _pcm.stream;

  void emit(Uint8List pcm) => _pcm.add(pcm);

  @override
  Future<void> start({required int inputSampleRateHz}) async {
    this.inputSampleRateHz = inputSampleRateHz;
    onStart();
    if (startFailures > 0) {
      startFailures--;
      throw StateError('fixture microphone start failure');
    }
  }

  @override
  Future<void> beginTurn(String turnId, {int? audioStartMs}) async {
    beginTurnCount++;
    beginTurnAudioStartMs.add(audioStartMs);
  }

  @override
  Future<CapturedRecording> endTurn() async {
    endTurnCount++;
    _turn++;
    return CapturedRecording(
      path: '/tmp/realtime-turn-$_turn.wav',
      durationMs: 800,
      byteLength: 25600,
      contentSha256: 'sha-$_turn',
    );
  }

  @override
  Future<void> discardTurn() async {}

  @override
  Future<void> play(Uint8List pcm) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<CapturedRecording> stop() async {
    stopCount++;
    return const CapturedRecording(
      path: '/tmp/realtime-session.wav',
      durationMs: 2000,
      byteLength: 64000,
      contentSha256: 'session-sha',
    );
  }

  @override
  Future<void> cancel() async {}
}
