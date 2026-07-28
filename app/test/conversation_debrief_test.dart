import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';
import 'package:llplayer_next/widgets/panels/conversation_debrief.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

void main() {
  test('the read-out counts turns off controller state and never rounds a '
      'running transcription up', () {
    final readout = conversationDebriefReadoutOf(_state());

    expect(readout.assistantTurns, 2);
    expect(readout.learnerTurns, 4);
    // Only a finalized turn carrying a local transcript is learner output.
    expect(readout.learnerOutputTurns, 1);
    expect(readout.transcribingTurns, 1);
    expect(readout.lostTurns, 2);
    expect(readout.settled, isFalse);

    final done = conversationDebriefReadoutOf(
      const RealtimeConversationState(
        phase: RealtimeConversationPhase.done,
        items: [
          RealtimeConversationItem(
            sequence: 1,
            role: 'learner',
            status: 'finalized',
            startedAtMs: 1,
            localText: 'my own words',
          ),
        ],
      ),
    );
    expect(done.settled, isTrue);
    expect(done.lostTurns, 0);
  });

  test('an amber target is a backend fact — a learner turn that ended without '
      'becoming output — and nothing else', () {
    final targets = conversationDebriefTargetsOf(_state());

    expect(targets.map((item) => item.sequence), [4, 6]);
    // The assistant's interrupted turn is not a target: barge-in is the
    // learner cutting in, which the stage actively invites (S7 · D5).
    expect(targets.every((item) => item.role == 'learner'), isTrue);
    // A turn still being transcribed is progress, not a target.
    expect(targets.map((item) => item.status), ['failed', 'interrupted']);
  });

  testWidgets('the debrief is three sections, and a turn still being '
      'transcribed says so instead of showing the provider caption as '
      'your words', (tester) async {
    final controller = _controller(_state());
    await _pumpDebrief(tester, controller);

    // 1 · 对话 — the local transcript is the body.
    expect(find.text('my own words'), findsOneWidget);
    // The unfinished turn reports progress. The provider's caption of that
    // same turn exists, but it is guidance and stays folded away: honest
    // layering (charter · D3) plus P4, never a placeholder standing in for a
    // transcript that has not arrived.
    expect(
      find.byKey(const ValueKey('conversation-debrief-pending-3')),
      findsOneWidget,
    );
    expect(find.text('provider guess at turn 3'), findsNothing);
    expect(
      find.byKey(const ValueKey('conversation-debrief-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-debrief-provisional')),
      findsOneWidget,
    );

    // The guidance version is reachable on demand, and only on demand.
    await tester.tap(
      find.byKey(const ValueKey('conversation-debrief-guidance-toggle-3')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('provider guess at turn 3'), findsOneWidget);

    // 2 · 靶子 and 3 · 回流.
    expect(
      find.byKey(const ValueKey('conversation-debrief-target-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-debrief-readout')),
      findsOneWidget,
    );

    // The water has stopped: the surface is gone, its residue is a static bar.
    expect(find.byType(ConversationEchoTally), findsOneWidget);
    expect(find.byType(ConversationEchoSurface), findsNothing);

    controller.dispose();
  });

  testWidgets('a target hands the learner on to 我的表达, and the read-out to '
      'the vocabulary book', (tester) async {
    final controller = _controller(_state());
    final saved = <String>[];
    var openedVocabulary = 0;
    await _pumpDebrief(
      tester,
      controller,
      onSaveExpression: (text) async => saved.add(text),
      onOpenVocabulary: () async => openedVocabulary++,
    );

    final save = find.byKey(
      const ValueKey('conversation-debrief-save-expression-4'),
    );
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 300));
    // All that survived that turn is the provider caption, and it is handed
    // over as a prefill for something the learner writes down — never as
    // learner output.
    expect(saved, ['provider guess at turn 4']);

    final vocabulary = find.byKey(
      const ValueKey('conversation-debrief-open-vocabulary'),
    );
    await tester.ensureVisible(vocabulary);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(vocabulary);
    await tester.pump(const Duration(milliseconds: 300));
    expect(openedVocabulary, 1);

    controller.dispose();
  });

  testWidgets('a clean conversation says so rather than inventing a target', (
    tester,
  ) async {
    final controller = _controller(
      const RealtimeConversationState(
        phase: RealtimeConversationPhase.done,
        items: [
          RealtimeConversationItem(
            sequence: 1,
            role: 'learner',
            status: 'finalized',
            startedAtMs: 1,
            localText: 'my own words',
          ),
        ],
      ),
    );
    await _pumpDebrief(tester, controller);

    expect(
      find.byKey(const ValueKey('conversation-debrief-targets-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-debrief-progress')),
      findsNothing,
    );

    controller.dispose();
  });

  testWidgets('the closing bar draws the turns that never came back rather '
      'than dropping them', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConversationEchoTally(
            moonTurns: 2,
            learnerTurns: 4,
            learnerOutputTurns: 1,
            barHeight: 64,
          ),
        ),
      ),
    );
    await tester.pump();

    double heightOf(String key) => tester
        .getSize(find.byKey(ValueKey(key)))
        .height;

    // Your four turns are the tallest thing on the bar; the one that came
    // back is lit, and the unlit rest of the dashed ghost is what this
    // conversation did not return — drawn, not computed away.
    expect(heightOf('conversation-tally-ghost'), 64);
    expect(heightOf('conversation-tally-learner'), 16);
    expect(heightOf('conversation-tally-moon'), 32);
  });
}

/// One conversation with every learner outcome in it: output, still
/// transcribing, failed, interrupted — plus an assistant turn the learner cut
/// into.
RealtimeConversationState _state() => const RealtimeConversationState(
  phase: RealtimeConversationPhase.postProcessing,
  postProcessingCount: 1,
  items: [
    RealtimeConversationItem(
      sequence: 1,
      role: 'assistant',
      status: 'finalized',
      startedAtMs: 1,
      providerText: 'the other voice',
    ),
    RealtimeConversationItem(
      sequence: 2,
      role: 'learner',
      status: 'finalized',
      startedAtMs: 2,
      providerText: 'provider guess at turn 2',
      localText: 'my own words',
    ),
    RealtimeConversationItem(
      sequence: 3,
      role: 'learner',
      status: 'local_transcription_pending',
      startedAtMs: 3,
      providerText: 'provider guess at turn 3',
    ),
    RealtimeConversationItem(
      sequence: 4,
      role: 'learner',
      status: 'failed',
      startedAtMs: 4,
      providerText: 'provider guess at turn 4',
      error: 'Could not process learner turn',
    ),
    RealtimeConversationItem(
      sequence: 5,
      role: 'assistant',
      status: 'interrupted',
      startedAtMs: 5,
      providerText: 'cut off mid sentence',
      error: 'learner_barge_in',
    ),
    RealtimeConversationItem(
      sequence: 6,
      role: 'learner',
      status: 'interrupted',
      startedAtMs: 6,
    ),
  ],
);

RealtimeConversationController _controller(RealtimeConversationState state) {
  final controller = RealtimeConversationController(audio: _FakeAudio());
  controller.state = state;
  return controller;
}

/// The stage keeps ambient animation alive elsewhere in this route, so every
/// pump here is a timed one — `pumpAndSettle` would never return.
Future<void> _pumpDebrief(
  WidgetTester tester,
  RealtimeConversationController controller, {
  Future<void> Function(String text)? onSaveExpression,
  Future<void> Function()? onOpenVocabulary,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RealtimeConversationPanel(
        controller: controller,
        api: _api(),
        launch: RealtimeConversationLaunch.free(
          language: 'en',
          modelId: 'asr-model',
        ),
        acquireAudioFocus: () async {},
        onClose: () {},
        onSaveExpression: onSaveExpression,
        onOpenVocabulary: onOpenVocabulary,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

LocalApi _api() => LocalApi.withTransport(
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
