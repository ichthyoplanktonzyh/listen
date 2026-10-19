import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

/// #46: the keyboard focus language — a thin signal-teal outline (1.5, same
/// weight as the input focus border) on whichever control holds focus, in
/// both themes. On the primary fill the ring flips to the on-color so it
/// never sinks into its own teal.
void main() {
  BorderSide? ringOf(ButtonStyle? style, {bool focused = true}) =>
      style?.side?.resolve({if (focused) WidgetState.focused});

  for (final (name, theme) in [
    ('light', ListenTheme.light()),
    ('dark', ListenTheme.dark()),
  ]) {
    test('$name: every button family rings on focus, and only on focus', () {
      final scheme = theme.colorScheme;
      final teal = BorderSide(color: scheme.primary, width: 1.5);

      expect(ringOf(theme.outlinedButtonTheme.style), teal);
      expect(ringOf(theme.textButtonTheme.style), teal);
      expect(ringOf(theme.iconButtonTheme.style), teal);
      // Filled: teal-on-teal would vanish, so the ring is the on-color.
      expect(
        ringOf(theme.filledButtonTheme.style),
        BorderSide(color: scheme.onPrimary, width: 1.5),
      );

      // At rest nothing rings; the outlined button keeps its resting outline.
      expect(ringOf(theme.filledButtonTheme.style, focused: false), isNull);
      expect(ringOf(theme.textButtonTheme.style, focused: false), isNull);
      expect(ringOf(theme.iconButtonTheme.style, focused: false), isNull);
      expect(
        ringOf(theme.outlinedButtonTheme.style, focused: false),
        BorderSide(color: scheme.outline),
      );

      // The focus ring and the input focus border are the same language.
      final inputFocus =
          (theme.inputDecorationTheme.focusedBorder as OutlineInputBorder)
              .borderSide;
      expect(inputFocus.color, scheme.primary);
      expect(inputFocus.width, 1.5);
    });
  }

  testWidgets('Tab walks the controls and the ring lands where focus is', (
    tester,
  ) async {
    final iconFocus = FocusNode();
    final outlinedFocus = FocusNode();
    addTearDown(iconFocus.dispose);
    addTearDown(outlinedFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              IconButton(
                focusNode: iconFocus,
                onPressed: () {},
                icon: const Icon(Icons.play_arrow),
              ),
              OutlinedButton(
                focusNode: outlinedFocus,
                onPressed: () {},
                child: const Text('second'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(iconFocus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(outlinedFocus.hasPrimaryFocus, isTrue);
  });
}
