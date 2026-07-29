import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

/// The conversation's *notice* channel — the red strip, as opposed to the turn
/// card.
///
/// The turn card's leak was fixed first, and fixing only that would have been
/// a false victory: the controller was still building
/// `'Realtime connection failed: $error'` and friends at eleven sites, and the
/// panel rendered them at five. A learner whose sidecar rejected a request saw
/// exactly the same `HttpException` / `correlation_id` / `127.0.0.1` string —
/// same screen, a few hundred pixels higher.
///
/// So every one of these drives a *real* failure through the *real* transport,
/// rather than hand-building a notice: that is the only way the assertion
/// covers `describeApiFailure` and the exception's own `toString` (which is
/// what appends `uri = …`) instead of just the widget.
void main() {
  /// The body the field actually reported. `_api` serves it from
  /// 127.0.0.1:62645 — the address the field actually used — so the exception's
  /// own `toString` carries the same sidecar URI the learner saw.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Everything that is transport detail and must never reach the strip.
  Future<void> expectNoTransportLeak(WidgetTester tester) async {
    for (final leak in const [
      'HttpException',
      'Exception',
      'correlation_id',
      '127.0.0.1',
      '62645',
      'validation_error',
      'recording metadata must not be empty',
      'uri =',
      '/v1/realtime',
      'retryable',
      // The sentence fragments the controller used to interpolate into.
      'Could not load realtime providers',
      'Could not load conversation history',
      'Could not load conversation turns',
      'Could not start realtime conversation',
      'Realtime connection failed',
      'Invalid realtime provider event',
      'Could not finish realtime conversation',
    ]) {
      expect(
        find.textContaining(leak, findRichText: true),
        findsNothing,
        reason:
            '"$leak" is transport detail; the notice strip is not a place to '
            'print it.',
      );
    }
  }

  testWidgets('a voice list that fails to load says so — it does not print '
      'the exception', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    await _pump(
      tester,
      controller,
      _api(onProviders: () => (statusCode: 500, body: envelope)),
    );

    expect(
      find.text('The realtime voices could not be loaded.'),
      findsOneWidget,
    );
    // The reference id survives, because a bug report needs it. Nothing else
    // from the exchange does.
    expect(find.text('Reference api-853'), findsOneWidget);
    await expectNoTransportLeak(tester);

    controller.dispose();
  });

  testWidgets('a history list that fails to load says so', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    await _pump(
      tester,
      controller,
      _api(onSessions: () => (statusCode: 503, body: envelope)),
    );

    expect(
      find.text('Your past conversations could not be loaded.'),
      findsOneWidget,
    );
    await expectNoTransportLeak(tester);

    controller.dispose();
  });

  testWidgets('a past conversation that fails to open says so', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    final api = _api(onTurns: () => (statusCode: 500, body: envelope));
    await _pump(tester, controller, api);

    await controller.openHistorySession(api, 'session-1');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('This conversation could not be opened.'), findsOneWidget);
    await expectNoTransportLeak(tester);

    controller.dispose();
  });

  testWidgets('a conversation that cannot start says so', (tester) async {
    final controller = RealtimeConversationController(
      audio: _FakeAudio(),
      connect: (uri, headers) async => throw const HttpException(envelope),
    );
    final api = _api();
    await _pump(tester, controller, api);

    await controller.start(
      api,
      RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
      acquireAudioFocus: () async {},
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('The conversation could not be started.'), findsOneWidget);
    expect(find.text('Reference api-853'), findsOneWidget);
    await expectNoTransportLeak(tester);

    controller.dispose();
  });

  testWidgets('a socket that errors mid-conversation says so', (tester) async {
    final connection = _FakeConnection();
    final controller = RealtimeConversationController(
      audio: _FakeAudio(),
      connect: (uri, headers) async => connection,
    );
    final api = _api();
    await _pump(tester, controller, api);

    await controller.start(
      api,
      RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
      acquireAudioFocus: () async {},
    );
    await tester.pump();

    // The failure arrives the way a dropped socket really arrives: as an
    // exception on the message stream.
    await _emit(
      tester,
      () => connection.messages$.addError(const HttpException(envelope)),
    );

    expect(
      find.text('The connection to the voice service failed.'),
      findsOneWidget,
    );
    await expectNoTransportLeak(tester);

    controller.dispose();
  });

  testWidgets('the provider\'s own error text is not passed through either', (
    tester,
  ) async {
    final connection = _FakeConnection();
    final controller = RealtimeConversationController(
      audio: _FakeAudio(),
      connect: (uri, headers) async => connection,
    );
    final api = _api();
    await _pump(tester, controller, api);

    await controller.start(
      api,
      RealtimeConversationLaunch.free(language: 'en', modelId: 'asr-model'),
      acquireAudioFocus: () async {},
    );
    await tester.pump();

    connection.messages$.add(
      '{"type":"provider_error","error":"upstream 429 quota_exhausted at '
      'pod-77 (trace 9f2c)"}',
    );
    await _emit(tester, () {});

    expect(
      find.text('The voice service reported a problem with this conversation.'),
      findsOneWidget,
    );
    // Whatever the provider decided to put in that field, it is not our copy.
    expect(find.textContaining('quota_exhausted'), findsNothing);
    expect(find.textContaining('pod-77'), findsNothing);
    expect(find.textContaining('9f2c'), findsNothing);

    controller.dispose();
  });

  testWidgets('a notice with no reference id shows only the sentence', (
    tester,
  ) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    // A body that is not the envelope at all: nothing is typed out of it, so
    // there is nothing to reference — and still nothing to leak.
    await _pump(
      tester,
      controller,
      _api(
        onProviders: () =>
            (statusCode: 502, body: '<html>502 Bad Gateway</html>'),
      ),
    );

    expect(
      find.text('The realtime voices could not be loaded.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('realtime-notice-reference')),
      findsNothing,
    );
    expect(find.textContaining('Bad Gateway'), findsNothing);
    expect(find.textContaining('html'), findsNothing);

    controller.dispose();
  });
}

/// Pushes a socket event and lets the controller's teardown actually run.
///
/// `runAsync` is required, not decorative: the failure path cancels the
/// message subscription from inside that subscription's own error handler, and
/// under `testWidgets`' FakeAsync zone that cancel never completes, so the
/// notice would never be assigned. Real async resolves it exactly as
/// production does.
Future<void> _emit(WidgetTester tester, VoidCallback emit) async {
  await tester.runAsync(() async {
    emit();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pump(
  WidgetTester tester,
  RealtimeConversationController controller,
  LocalApi api,
) async {
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
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

LocalApi _api({
  ApiResponse Function()? onProviders,
  ApiResponse Function()? onSessions,
  ApiResponse Function()? onTurns,
}) => LocalApi.withTransport(
  baseUrl: 'http://127.0.0.1:62645',
  token: 'token',
  transport: (method, path, body) async {
    if (path == '/v1/realtime/providers') {
      return onProviders?.call() ??
          (
            statusCode: 200,
            body:
                '[{"id":"profile-1","display_name":"test","adapter_kind":'
                '"qwen_omni_realtime","base_url":"wss://example.com/ws",'
                '"model_id":"qwen3.5-omni-plus-realtime","voice":"marin",'
                '"has_credential":true,"timeout_ms":30000}]',
          );
    }
    if (path == '/v1/realtime/sessions' && method == 'GET') {
      return onSessions?.call() ?? (statusCode: 200, body: '[]');
    }
    if (path.endsWith('/turns') && method == 'GET') {
      return onTurns?.call() ?? (statusCode: 200, body: '[]');
    }
    return (statusCode: 200, body: '{}');
  },
);

class _FakeConnection implements RealtimeConnection {
  final messages$ = StreamController<Object?>.broadcast();

  @override
  Stream<Object?> get messages => messages$.stream;

  @override
  bool get isOpen => true;

  @override
  void send(Object data) {}

  /// Deliberately does not *await* the controller's close. The cleanup this
  /// triggers runs from inside the stream's own error dispatch, and awaiting a
  /// broadcast controller's close from there never completes — a stall the
  /// fake would invent and a real socket would not.
  @override
  Future<void> close() async {
    if (!messages$.isClosed) unawaited(messages$.close());
  }
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
