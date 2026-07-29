import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/panels/conversation_afterglow_caption.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

void main() {
  group('honest layering', () {
    test('only the other person reaches the stage — the learner never '
        'does', () {
      // A learner turn whose provider caption is streaming *and* whose local
      // Whisper transcript already landed: neither may be shown live. The
      // provider version is guidance about your own speech, the local one is
      // learner output and belongs to the debrief (S9).
      final line = conversationAfterglowLineOf(
        RealtimeConversationState(
          phase: RealtimeConversationPhase.live,
          items: const [
            RealtimeConversationItem(
              sequence: 1,
              role: 'learner',
              status: 'streaming',
              startedAtMs: 1,
              providerText: 'i think the weather',
            ),
            RealtimeConversationItem(
              sequence: 2,
              role: 'learner',
              status: 'finalized',
              startedAtMs: 2,
              providerText: 'guidance version',
              localText: 'local whisper version',
            ),
          ],
        ),
      );
      expect(line, isNull);
    });

    test('the newest assistant line wins, and a learner turn on top does not '
        'promote a learner caption', () {
      RealtimeConversationState stateWith(
        List<RealtimeConversationItem> items,
      ) => RealtimeConversationState(
        phase: RealtimeConversationPhase.live,
        items: items,
      );

      const first = RealtimeConversationItem(
        sequence: 1,
        role: 'assistant',
        status: 'finalized',
        startedAtMs: 1,
        providerText: 'What did you do today?',
      );
      const second = RealtimeConversationItem(
        sequence: 3,
        role: 'assistant',
        status: 'streaming',
        startedAtMs: 3,
        providerText: 'That sounds',
      );
      const learner = RealtimeConversationItem(
        sequence: 4,
        role: 'learner',
        status: 'streaming',
        startedAtMs: 4,
        providerText: 'i went running',
      );

      expect(
        conversationAfterglowLineOf(stateWith([first])),
        const ConversationCaptionLine(
          text: 'What did you do today?',
          settled: true,
        ),
      );
      // Still being spoken: nothing to count the afterglow down from yet.
      expect(
        conversationAfterglowLineOf(stateWith([first, second])),
        const ConversationCaptionLine(text: 'That sounds', settled: false),
      );
      expect(
        conversationAfterglowLineOf(stateWith([first, second, learner])),
        const ConversationCaptionLine(text: 'That sounds', settled: false),
      );
    });

    test('an empty provider caption is not a line', () {
      expect(
        conversationAfterglowLineOf(
          const RealtimeConversationState(
            phase: RealtimeConversationPhase.live,
            items: [
              RealtimeConversationItem(
                sequence: 1,
                role: 'assistant',
                status: 'streaming',
                startedAtMs: 1,
              ),
            ],
          ),
        ),
        isNull,
      );
    });
  });

  testWidgets('a finished line fades out after the 2.6s afterglow and leaves '
      'no history behind', (tester) async {
    Future<void> show(ConversationCaptionLine? line) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConversationAfterglowCaption(line: line)),
        ),
      );
      await tester.pump();
    }

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    await show(
      const ConversationCaptionLine(text: 'That sounds fun', settled: false),
    );
    expect(find.text('That sounds fun'), findsOneWidget);
    expect(opacity(), 1);

    // While the provider keeps speaking the line stays put, however long the
    // turn runs.
    await tester.pump(ListenMotion.ambient * 2);
    expect(opacity(), 1);

    await show(
      const ConversationCaptionLine(text: 'That sounds fun', settled: true),
    );
    expect(opacity(), 1);
    await tester.pump(ListenMotion.ambient - const Duration(milliseconds: 100));
    expect(opacity(), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 0);

    // Only ever one line: the next thing said replaces it rather than
    // stacking under it.
    await show(
      const ConversationCaptionLine(text: 'And then?', settled: false),
    );
    expect(find.text('That sounds fun'), findsNothing);
    expect(find.text('And then?'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(opacity(), 1);

    // Settle the pending timer before the test ends.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });

  testWidgets('the fade drops to zero duration under reduce motion', (
    tester,
  ) async {
    Future<Duration> fadeDuration({required bool disableAnimations}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const Scaffold(
              body: ConversationAfterglowCaption(
                line: ConversationCaptionLine(text: 'hello', settled: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .duration;
    }

    expect(await fadeDuration(disableAnimations: false), ListenMotion.base);
    expect(await fadeDuration(disableAnimations: true), Duration.zero);
  });

  testWidgets('the stage carries no caption by default', (tester) async {
    final controller = _liveController();
    await tester.pumpWidget(_panel(controller));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ConversationAfterglowCaption), findsNothing);
    expect(find.text('That sounds fun'), findsNothing);
    // And nothing the learner said, either — at any status.
    expect(find.text('i went running'), findsNothing);

    controller.dispose();
  });

  testWidgets('with the switch on, the stage shows the other person only', (
    tester,
  ) async {
    final controller = _liveController();
    await tester.pumpWidget(_panel(controller, captionEnabled: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('That sounds fun'), findsOneWidget);
    expect(find.text('i went running'), findsNothing);

    controller.dispose();
  });

  testWidgets('the lobby switch is off by default and reports the change so '
      'the host can remember it', (tester) async {
    final controller = RealtimeConversationController(audio: _FakeAudio());
    bool? persisted;
    await tester.pumpWidget(
      _panel(controller, onCaptionEnabledChanged: (v) => persisted = v),
    );
    await tester.pump();

    // The switch is a setting, so it lives behind the lobby's disclosure row
    // rather than in front of the start button. The row states the current
    // value without being opened.
    expect(find.text('What the other person says · not shown'), findsOneWidget);
    expect(find.byKey(const ValueKey('realtime-caption-toggle')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('realtime-caption-disclosure')));
    await tester.pump();

    final toggle = find.byKey(const ValueKey('realtime-caption-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(persisted, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    controller.dispose();
  });
}

RealtimeConversationController _liveController() {
  final controller = RealtimeConversationController(audio: _FakeAudio());
  controller.state = const RealtimeConversationState(
    phase: RealtimeConversationPhase.live,
    activity: RealtimeConversationActivity.listening,
    selectedProfileId: 'profile-1',
    items: [
      RealtimeConversationItem(
        sequence: 1,
        role: 'assistant',
        status: 'streaming',
        startedAtMs: 1,
        providerText: 'That sounds fun',
      ),
      RealtimeConversationItem(
        sequence: 2,
        role: 'learner',
        status: 'streaming',
        startedAtMs: 2,
        providerText: 'i went running',
      ),
    ],
  );
  return controller;
}

Widget _panel(
  RealtimeConversationController controller, {
  bool captionEnabled = false,
  ValueChanged<bool>? onCaptionEnabledChanged,
}) => MaterialApp(
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
    onCaptionEnabledChanged: onCaptionEnabledChanged,
  ),
);

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
