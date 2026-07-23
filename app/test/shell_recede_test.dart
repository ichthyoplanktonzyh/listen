import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/motion.dart';
import 'package:llplayer_next/widgets/layout/shell_recede.dart';

/// #46 signature action "the shell recedes": while media plays and the
/// pointer rests, chrome fades (base·exit); activity or chrome focus brings
/// it back (base·enter). Mirrors motion-spec demo 3 (`:hover, :focus-within`).
void main() {
  const idle = Duration(seconds: 3);

  Widget app({required bool active, FocusNode? buttonFocus}) => MaterialApp(
    theme: ListenTheme.dark(),
    home: ShellRecede(
      active: active,
      idleDelay: idle,
      builder: (context, shellVisible) => Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            ShellFade(
              visible: shellVisible,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: ElevatedButton(
                    focusNode: buttonFocus,
                    onPressed: () {},
                    child: const Text('transport'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  double chromeOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('transport'),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('inactive shell never recedes', (tester) async {
    await tester.pumpWidget(app(active: false));
    await tester.pump(idle * 2);
    expect(chromeOpacity(tester), 1);
  });

  testWidgets('resting pointer fades the chrome; movement brings it back', (
    tester,
  ) async {
    await tester.pumpWidget(app(active: true));
    expect(chromeOpacity(tester), 1);

    // The pointer rests past the idle threshold: chrome leaves.
    await tester.pump(idle + const Duration(milliseconds: 1));
    expect(chromeOpacity(tester), 0);

    // While hidden the chrome must not swallow the first click. (Outermost
    // IgnorePointer inside ShellFade is the one ShellFade owns.)
    final ignore = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(ShellFade),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignore.ignoring, isTrue);

    // Any mouse movement wakes it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await mouse.moveTo(const Offset(200, 200));
    await tester.pump();
    expect(chromeOpacity(tester), 1);
    await mouse.removePointer();
    await tester.pump(ListenMotion.base);
  });

  testWidgets('keyboard focus inside the chrome holds it visible', (
    tester,
  ) async {
    final buttonFocus = FocusNode();
    addTearDown(buttonFocus.dispose);
    await tester.pumpWidget(app(active: true, buttonFocus: buttonFocus));

    buttonFocus.requestFocus();
    await tester.pump();
    await tester.pump(idle * 2);
    expect(chromeOpacity(tester), 1);

    // Focus leaves: the idle clock has long expired, so the chrome recedes
    // again. (Focus changes apply in a post-frame microtask, so the release
    // lands one frame after the unfocus.)
    buttonFocus.unfocus();
    await tester.pump();
    await tester.pump();
    expect(chromeOpacity(tester), 0);
  });

  testWidgets('pausing playback (active false) restores the chrome', (
    tester,
  ) async {
    await tester.pumpWidget(app(active: true));
    await tester.pump(idle + const Duration(milliseconds: 1));
    expect(chromeOpacity(tester), 0);

    await tester.pumpWidget(app(active: false));
    expect(chromeOpacity(tester), 1);
  });
}
