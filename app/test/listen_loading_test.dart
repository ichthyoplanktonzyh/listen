import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/common/listen_loading.dart';
import 'package:llplayer_next/widgets/listen_wordmark.dart';

/// #46: the unified waiting language — the mutual-wave mark breathing at the
/// ambient tempo. Loading is brand presence, not a spinner.
void main() {
  Widget app(Widget child, {bool disableAnimations = false}) => MaterialApp(
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  // The breathing FadeTransition inside ListenLoading (MaterialApp owns
  // unrelated ones of its own).
  final breath = find.descendant(
    of: find.byType(ListenLoading),
    matching: find.byType(FadeTransition),
  );

  testWidgets('panel loading renders the breathing mark and label', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ListenLoading(label: 'Fetching')));

    expect(find.byType(ListenWordmark), findsOneWidget);
    expect(find.text('Fetching'), findsOneWidget);

    // The breath is alive: opacity changes across half an ambient cycle.
    final fade = tester.widget<FadeTransition>(breath);
    final before = fade.opacity.value;
    await tester.pump(ListenMotion.ambient * 0.25);
    expect(fade.opacity.value, isNot(before));

    // And it never dips below the spec floor of 0.72.
    expect(fade.opacity.value, greaterThanOrEqualTo(0.72));
  });

  testWidgets('inline loading is the bare mark at icon size', (tester) async {
    await tester.pumpWidget(app(const ListenLoading.inline()));

    final mark = tester.widget<ListenWordmark>(find.byType(ListenWordmark));
    expect(mark.size, 18);
    expect(mark.withText, isFalse);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('reduce motion stops the breath and shows the mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const ListenLoading(), disableAnimations: true),
    );

    final fade = tester.widget<FadeTransition>(breath);
    expect(fade.opacity.value, 1.0);
    await tester.pump(ListenMotion.ambient);
    expect(fade.opacity.value, 1.0);
    // Nothing scheduled: the frame is settled (repeat() would keep pumping).
    expect(tester.hasRunningAnimations, isFalse);
  });
}
