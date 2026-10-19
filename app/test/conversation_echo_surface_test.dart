import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';
import 'package:llplayer_next/widgets/panels/conversation_stage_shell.dart';

/// The 回声水面 (#84 · S7). The surface breathes at the ambient tempo, so the
/// widget tests pump fixed durations — `pumpAndSettle` would time out — except
/// under reduce motion, where settling is exactly the property under test.
void main() {
  test('each activity gets its own light, on three separable axes', () {
    EchoSurfaceLevels levels(RealtimeConversationActivity activity) =>
        conversationEchoLevelsOf(activity);

    final listening = levels(RealtimeConversationActivity.listening);
    final speaking = levels(RealtimeConversationActivity.learnerSpeaking);
    final thinking = levels(RealtimeConversationActivity.thinking);
    final assistant = levels(RealtimeConversationActivity.assistantSpeaking);

    // 你在说 is the brightest moment of the flow, and the only state where the
    // moon is gone entirely — your voice owns the surface.
    expect(speaking.learner, 1);
    expect(speaking.moon, 0);
    expect(speaking.learner, greaterThan(listening.learner));
    expect(speaking.learner, greaterThan(assistant.learner));

    // 对方在说: moonlight falls, and your side keeps a visible resting swell
    // so the open channel is an affordance rather than a surprise (D5).
    expect(assistant.moon, 1);
    expect(assistant.moon, greaterThan(listening.moon));
    expect(assistant.learner, greaterThan(0));

    // 微澜 vs 涟漪: only thinking ripples, and no other state does.
    expect(thinking.ripple, 1);
    for (final other in [listening, speaking, assistant]) {
      expect(other.ripple, 0);
    }

    // Nothing on the water before the conversation is live.
    expect(
      levels(RealtimeConversationActivity.inactive),
      EchoSurfaceLevels.still,
    );

    // All four states differ as painted values, so the shape alone tells them
    // apart — the label is a second copy, not the only copy (D2).
    expect({listening, speaking, thinking, assistant}.length, 4);
  });

  testWidgets('you speaking takes the surface within the tap budget while the '
      'moonlight is pulled under', (tester) async {
    Future<void> show(RealtimeConversationActivity activity) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ConversationEchoSurface(
                  levels: conversationEchoLevelsOf(activity),
                ),
              ),
            ),
          ),
        );

    await show(RealtimeConversationActivity.assistantSpeaking);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final moonAtRest = _painter(tester).levels.moon;
    expect(moonAtRest, moreOrLessEquals(1, epsilon: 0.001));

    // You cut in. One frame later the interruption is already under way, and
    // by the tap budget (90ms) your echo has fully taken the surface while the
    // moonlight has visibly receded — it keeps draining over the slow exit.
    await show(RealtimeConversationActivity.learnerSpeaking);
    await tester.pump();
    await tester.pump(ListenMotion.tap);
    final interrupted = _painter(tester).levels;
    expect(interrupted.learner, moreOrLessEquals(1, epsilon: 0.001));
    expect(interrupted.moon, lessThan(moonAtRest));

    await tester.pump(ListenMotion.slow);
    expect(_painter(tester).levels.moon, moreOrLessEquals(0, epsilon: 0.001));
  });

  testWidgets('reduce motion leaves a still surface', (tester) async {
    Future<void> show(RealtimeConversationActivity activity) =>
        tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: Center(
                  child: ConversationEchoSurface(
                    levels: conversationEchoLevelsOf(activity),
                  ),
                ),
              ),
            ),
          ),
        );

    await show(RealtimeConversationActivity.assistantSpeaking);
    // Settling at all is the assertion: no ambient drift, no pending frames.
    await tester.pumpAndSettle();
    expect(_painter(tester).phase, 0);
    expect(
      _painter(tester).levels,
      conversationEchoLevelsOf(RealtimeConversationActivity.assistantSpeaking),
    );

    // A state change still lands — it just arrives without motion.
    await show(RealtimeConversationActivity.learnerSpeaking);
    await tester.pump();
    expect(
      _painter(tester).levels,
      conversationEchoLevelsOf(RealtimeConversationActivity.learnerSpeaking),
    );
    await tester.pumpAndSettle();
    expect(_painter(tester).phase, 0);
  });
}

EchoSurfacePainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<EchoSurfacePainter>()
    .single;
