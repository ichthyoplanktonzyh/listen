import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio between a foreground and background pair.
double _contrast(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

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

  test(
    'the dark theme is a real dark scheme anchored on the product palette',
    () {
      final theme = ListenTheme.dark();
      final colors = theme.colorScheme;

      expect(theme.brightness, Brightness.dark);
      expect(colors.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ListenColors.darkFog);
      expect(colors.surface, ListenColors.darkSurface);
      expect(colors.onSurface, ListenColors.darkText);
      expect(colors.onSurfaceVariant, ListenColors.darkMuted);
      expect(colors.outlineVariant, ListenColors.darkBorder);
      expect(colors.primary, ListenColors.darkPrimary);
      // The light brand teal stays reachable as the inverse accent, so the two
      // themes remain recognizably the same product.
      expect(colors.inversePrimary, ListenColors.primary);
    },
  );

  test('both themes share one component-theme structure', () {
    final light = ListenTheme.light();
    final dark = ListenTheme.dark();

    // Same shapes and metrics; only the colors differ.
    expect(
      (dark.cardTheme.shape as RoundedRectangleBorder).borderRadius,
      (light.cardTheme.shape as RoundedRectangleBorder).borderRadius,
    );
    expect(dark.dialogTheme.shape, light.dialogTheme.shape);
    expect(dark.dividerTheme.thickness, light.dividerTheme.thickness);
    expect(dark.appBarTheme.elevation, light.appBarTheme.elevation);
    expect(dark.useMaterial3, light.useMaterial3);

    // Every surface-bound component follows its scheme in both brightnesses.
    for (final theme in [light, dark]) {
      final colors = theme.colorScheme;
      expect(theme.appBarTheme.backgroundColor, colors.surface);
      expect(theme.cardTheme.color, colors.surface);
      expect(theme.dialogTheme.backgroundColor, colors.surface);
      expect(theme.popupMenuTheme.color, colors.surface);
      expect(theme.scaffoldBackgroundColor, colors.surfaceContainer);
      expect(theme.dividerTheme.color, colors.outlineVariant);
      expect(
        (theme.cardTheme.shape as RoundedRectangleBorder).side.color,
        colors.outlineVariant,
      );
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        colors.primary,
      );
    }
  });

  test('dark foregrounds clear WCAG AA on the surfaces they sit on', () {
    final colors = ListenTheme.dark().colorScheme;

    // Body and secondary text: AA normal text.
    expect(_contrast(colors.onSurface, colors.surface), greaterThan(4.5));
    expect(
      _contrast(colors.onSurfaceVariant, colors.surface),
      greaterThan(4.5),
    );
    expect(
      _contrast(colors.onSurfaceVariant, colors.surfaceContainer),
      greaterThan(4.5),
    );

    // Status/brand colors are used for labels and icons, not just fills.
    for (final accent in [
      colors.primary,
      colors.secondary,
      colors.tertiary,
      colors.error,
    ]) {
      expect(_contrast(accent, colors.surface), greaterThan(4.5));
      expect(_contrast(accent, colors.surfaceContainer), greaterThan(4.5));
    }

    // Container pairs stay legible.
    expect(
      _contrast(colors.onPrimaryContainer, colors.primaryContainer),
      greaterThan(4.5),
    );
    expect(_contrast(colors.onPrimary, colors.primary), greaterThan(4.5));

    // Disabled text is deliberately low-emphasis but must stay perceivable.
    expect(
      _contrast(colors.disabledForeground, colors.surface),
      greaterThan(3.0),
    );
  });

  test('verdict shades clear WCAG AA as small bold text in both themes', () {
    // #22: covered/partial verdict labels are 12px w700 — below the WCAG
    // large-text exemption — so 4.5:1 applies on every chrome surface they
    // can sit on. (The third verdict, missing, reads `error`, whose dark
    // value is asserted above; recalibrating the light error tone is the
    // deferred light-theme pass, not this slice.)
    for (final theme in [ListenTheme.light(), ListenTheme.dark()]) {
      final colors = theme.colorScheme;
      for (final verdict in [colors.verdictCovered, colors.verdictPartial]) {
        expect(_contrast(verdict, colors.surface), greaterThan(4.5));
        expect(_contrast(verdict, colors.surfaceContainer), greaterThan(4.5));
        expect(
          _contrast(verdict, colors.surfaceContainerHigh),
          greaterThan(4.5),
        );
      }
      // The two verdicts stay distinguishable from each other and from the
      // error slot used by "missing" — three verdicts, three colors.
      expect(colors.verdictCovered, isNot(colors.verdictPartial));
      expect(colors.verdictPartial, isNot(colors.error));
    }
  });

  test('themeModeFromSetting maps persisted values and degrades unknowns', () {
    expect(themeModeFromSetting('system'), ThemeMode.system);
    expect(themeModeFromSetting('light'), ThemeMode.light);
    expect(themeModeFromSetting('dark'), ThemeMode.dark);
    expect(themeModeFromSetting('sepia'), ThemeMode.system);
    expect(themeModeFromSetting(''), ThemeMode.system);
  });

  testWidgets('themeMode selects the dark theme for the whole app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.light(),
        darkTheme: ListenTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Text('Listen')),
      ),
    );

    final theme = Theme.of(tester.element(find.text('Listen')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, ListenColors.darkFog);
    expect(tester.takeException(), isNull);
  });
}
