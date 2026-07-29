import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/panels/conversation_stage_shell.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

void main() {
  test('the on-screen room is derived from the controller phase, never '
      'invented', () {
    ConversationStageSegment segment(
      RealtimeConversationPhase phase, {
      bool withTurns = false,
      bool dismissed = false,
    }) => conversationStageSegmentOf(
      RealtimeConversationState(
        phase: phase,
        items: withTurns
            ? const [
                RealtimeConversationItem(
                  sequence: 1,
                  role: 'learner',
                  status: 'finalized',
                  startedAtMs: 1,
                  localText: 'hello',
                ),
              ]
            : const [],
      ),
      debriefDismissed: dismissed,
    );

    expect(
      segment(RealtimeConversationPhase.idle),
      ConversationStageSegment.lobby,
    );
    for (final phase in const [
      RealtimeConversationPhase.connecting,
      RealtimeConversationPhase.live,
      RealtimeConversationPhase.draining,
    ]) {
      expect(segment(phase), ConversationStageSegment.stage);
    }
    expect(
      segment(RealtimeConversationPhase.postProcessing, withTurns: true),
      ConversationStageSegment.debrief,
    );
    // A conversation that produced nothing has nothing to debrief, and a
    // dismissed debrief returns to the lobby without touching the controller.
    expect(
      segment(RealtimeConversationPhase.done),
      ConversationStageSegment.lobby,
    );
    expect(
      segment(RealtimeConversationPhase.done, withTurns: true, dismissed: true),
      ConversationStageSegment.lobby,
    );
  });

  testWidgets('the stage is a dark room, not a page of chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.light(),
        home: const ConversationStageShell(
          segment: ConversationStageSegment.stage,
          child: Text('body'),
        ),
      ),
    );
    await tester.pump();

    // The ground is compressed to `ground2` and the subtree stays dark even
    // under the light theme — stage mode dims the room in both brightnesses.
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ConversationStageShell),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, ListenColors.stageGround);
    expect(
      Theme.of(tester.element(find.text('body'))).colorScheme.brightness,
      Brightness.dark,
    );
  });

  testWidgets('the two-stage entrance drops to zero duration under '
      'reduce motion', (tester) async {
    Future<Duration> switcherDuration({required bool disableAnimations}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const ConversationStageShell(
              segment: ConversationStageSegment.lobby,
              child: Text('body'),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
          .duration;
    }

    expect(await switcherDuration(disableAnimations: false), ListenMotion.slow);
    expect(await switcherDuration(disableAnimations: true), Duration.zero);
  });

  testWidgets('entering a live conversation lands on the stage, not on the '
      'lobby form', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    controller.state = const RealtimeConversationState(
      phase: RealtimeConversationPhase.live,
      activity: RealtimeConversationActivity.listening,
      selectedProfileId: 'profile-1',
    );
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The stage: one glowing shape and the way out. No voice picker, no
    // history list, and — per the charter — no transcript of your own words.
    expect(
      find.byKey(const ValueKey('conversation-echo-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('realtime-finish')), findsOneWidget);
    expect(find.byKey(const ValueKey('realtime-voice-choice')), findsNothing);
    expect(find.text('Recent conversations'), findsNothing);
    expect(find.byKey(const ValueKey('realtime-start')), findsNothing);

    controller.dispose();
  });

  testWidgets('the stage keeps one light source: the controls do not compete '
      'with the water', (tester) async {
    final controller = _liveController();
    await _pumpStage(tester, controller);

    // 「唯一光源」(charter · 舞台态 2). A FilledButton here was the second
    // brightest thing on screen; the teal belongs to the surface. The
    // destructive way out stays plain text, as it already was.
    expect(
      tester.widget(find.byKey(const ValueKey('realtime-finish'))),
      isA<OutlinedButton>(),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(
      tester.widget(find.byKey(const ValueKey('realtime-cancel'))),
      isA<TextButton>(),
    );

    controller.dispose();
  });

  testWidgets('the live composition sits near the vertical centre, whether or '
      'not the caption is on', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final captionEnabled in [false, true]) {
      final controller = _liveController();
      await _pumpStage(tester, controller, captionEnabled: captionEnabled);

      final surface = tester.getRect(
        find.byKey(const ValueKey('conversation-echo-surface')),
      );
      final label = tester.getRect(
        find.byKey(const ValueKey('realtime-activity')),
      );
      // The水面 is the subject, so its centre — not the centre of the whole
      // text block — is what has to land near the middle of the room.
      expect(
        surface.center.dy / 900,
        inInclusiveRange(0.42, 0.52),
        reason: 'caption=$captionEnabled left the water off-centre',
      );
      // The label follows the shape rather than clinging to it.
      expect(label.top - surface.bottom, greaterThanOrEqualTo(24));

      controller.dispose();
    }
  });
}

RealtimeConversationController _liveController() {
  final controller = RealtimeConversationController(audio: _FakeAudio());
  controller.state = const RealtimeConversationState(
    phase: RealtimeConversationPhase.live,
    activity: RealtimeConversationActivity.listening,
    selectedProfileId: 'profile-1',
  );
  return controller;
}

/// The stage breathes at the ambient tempo, so every pump here is a timed
/// one — `pumpAndSettle` would never return.
Future<void> _pumpStage(
  WidgetTester tester,
  RealtimeConversationController controller, {
  bool captionEnabled = false,
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
        captionEnabled: captionEnabled,
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
