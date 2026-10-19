import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/common/listen_error_state.dart';

/// #46: the unified error containers — panel-level state (sibling of the
/// empty state, glyph in the error role) and the quiet inline notice. Form
/// only; hues stay theme roles (#22 owns their calibration).
void main() {
  Widget app(Widget child) => MaterialApp(
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('panel error state: glyph in the error role, retry action', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      app(
        ListenErrorState(
          message: 'Backend unreachable',
          action: OutlinedButton(
            onPressed: () => retried = true,
            child: const Text('Retry'),
          ),
        ),
      ),
    );

    expect(find.text('Backend unreachable'), findsOneWidget);
    final context = tester.element(find.byType(ListenErrorState));
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, Theme.of(context).colorScheme.error);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('inline notice: error surface, message, nothing else', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const ListenErrorNotice(message: 'Save failed')),
    );

    expect(find.text('Save failed'), findsOneWidget);
    final context = tester.element(find.byType(ListenErrorNotice));
    final colors = Theme.of(context).colorScheme;
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ListenErrorNotice),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, colors.errorContainer);
    final text = tester.widget<Text>(find.text('Save failed'));
    expect(text.style?.color, colors.onErrorContainer);
  });
}
