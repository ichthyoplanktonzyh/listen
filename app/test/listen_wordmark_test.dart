import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/listen_wordmark.dart';

/// #32: the brand lockup — mutual-wave mark + lowercase wordmark. The mark's
/// two halves are brand constants that must not follow the theme: the
/// bright/dark relationship is the meaning.
void main() {
  Widget app(Widget child) => MaterialApp(
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('lockup renders the mark and the lowercase wordmark', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ListenWordmark()));

    expect(find.text('listen'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.size == const Size.square(22),
      ),
      findsOneWidget,
    );
  });

  testWidgets('withText false renders the bare mark', (tester) async {
    await tester.pumpWidget(app(const ListenWordmark(withText: false)));

    expect(find.text('listen'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('mark halves keep the drawn bright/dark relationship', () {
    // Guards against "helpfully" wiring the mark to colorScheme.primary,
    // which would flip the echo half in the light theme.
    expect(ListenWordmark.markContent, const Color(0xff4db8a8));
    expect(ListenWordmark.markEcho, const Color(0xff2f8578));
  });
}
