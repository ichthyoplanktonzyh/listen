import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/common/content_settle.dart';

/// #46 signature action "content settles in": entering content fades in while
/// rising 8px into place (base·enter, no overshoot); a settleKey change
/// re-runs the settle; reduce motion drops straight to settled.
void main() {
  Widget app(Object? settleKey, {bool disableAnimations = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: ContentSettle(
            settleKey: settleKey,
            child: const Text('panel'),
          ),
        ),
      );

  double settleOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(ContentSettle),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  testWidgets('content fades and rises into place on entry', (tester) async {
    await tester.pumpWidget(app('a'));

    // Mid-flight: partially transparent, still below its resting place.
    await tester.pump(ListenMotion.base * 0.5);
    final midOpacity = settleOpacity(tester);
    expect(midOpacity, greaterThan(0));
    expect(midOpacity, lessThan(1));

    await tester.pump(ListenMotion.base);
    expect(settleOpacity(tester), 1);
  });

  testWidgets('a settleKey change re-runs the settle', (tester) async {
    await tester.pumpWidget(app('a'));
    await tester.pump(ListenMotion.base);
    expect(settleOpacity(tester), 1);

    await tester.pumpWidget(app('b'));
    await tester.pump(ListenMotion.base * 0.25);
    expect(settleOpacity(tester), lessThan(1));
    await tester.pump(ListenMotion.base);
    expect(settleOpacity(tester), 1);
  });

  testWidgets('reduce motion: content appears already settled', (
    tester,
  ) async {
    await tester.pumpWidget(app('a', disableAnimations: true));
    expect(settleOpacity(tester), 1);

    await tester.pumpWidget(app('b', disableAnimations: true));
    expect(settleOpacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
