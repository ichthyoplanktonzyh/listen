import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

void main() {
  test('listen theme exposes the product palette through ColorScheme', () {
    final theme = ListenTheme.light();
    final colors = theme.colorScheme;

    expect(theme.scaffoldBackgroundColor, ListenColors.fog);
    expect(colors.primary, ListenColors.primary);
    expect(colors.primaryContainer, ListenColors.selected);
    expect(colors.secondary, ListenColors.accent);
    expect(colors.tertiary, ListenColors.info);
    expect(colors.error, ListenColors.error);
    expect(colors.onSurface, ListenColors.text);
    expect(colors.onSurfaceVariant, ListenColors.muted);
    expect(colors.outlineVariant, ListenColors.border);
  });

  testWidgets('the themed surface and primary button use listen colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.light(),
        home: Scaffold(
          body: FilledButton(onPressed: () {}, child: const Text('Listen')),
        ),
      ),
    );

    final buttonContext = tester.element(find.byType(FilledButton));
    final theme = Theme.of(buttonContext);
    final states = <WidgetState>{};

    expect(theme.scaffoldBackgroundColor, ListenColors.fog);
    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve(states),
      ListenColors.primary,
    );
    expect(tester.takeException(), isNull);
  });
}
