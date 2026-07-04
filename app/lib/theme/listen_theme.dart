import 'package:flutter/material.dart';

abstract final class ListenColors {
  static const fog = Color(0xfff3f5f4);
  static const surface = Color(0xffffffff);
  static const sidebar = Color(0xffe8eeeb);
  static const player = Color(0xff101715);
  static const primary = Color(0xff167c72);
  static const primaryPressed = Color(0xff11645d);
  static const selected = Color(0xffd9ece8);
  static const text = Color(0xff1d2623);
  static const muted = Color(0xff68746f);
  static const outline = Color(0xffaab5b0);
  static const border = Color(0xffd8dfdc);
  static const accent = Color(0xffd89a32);
  static const error = Color(0xffc95454);
  static const info = Color(0xff3f7399);
  static const infoSurface = Color(0xffdceaf2);
  static const disabled = Color(0xff98a39e);
}

abstract final class ListenTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: ListenColors.primary,
      onPrimary: Colors.white,
      primaryContainer: ListenColors.selected,
      onPrimaryContainer: Color(0xff0d504a),
      secondary: ListenColors.accent,
      onSecondary: Color(0xff2c1e05),
      secondaryContainer: Color(0xfff5e8ce),
      onSecondaryContainer: Color(0xff60420d),
      tertiary: ListenColors.info,
      onTertiary: Colors.white,
      tertiaryContainer: ListenColors.infoSurface,
      onTertiaryContainer: Color(0xff244e68),
      error: ListenColors.error,
      onError: Colors.white,
      errorContainer: Color(0xfff8dddd),
      onErrorContainer: Color(0xff7a2929),
      surface: ListenColors.surface,
      onSurface: ListenColors.text,
      surfaceContainerLowest: ListenColors.surface,
      surfaceContainerLow: Color(0xfff7f9f8),
      surfaceContainer: ListenColors.fog,
      surfaceContainerHigh: ListenColors.sidebar,
      surfaceContainerHighest: Color(0xffdde5e1),
      onSurfaceVariant: ListenColors.muted,
      outline: ListenColors.outline,
      outlineVariant: ListenColors.border,
      shadow: Color(0x24101715),
      scrim: Color(0x66000000),
      inverseSurface: ListenColors.player,
      onInverseSurface: Color(0xffeef3f1),
      inversePrimary: Color(0xff7ed0c4),
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
    );
    return base.copyWith(
      scaffoldBackgroundColor: ListenColors.fog,
      canvasColor: ListenColors.fog,
      splashColor: ListenColors.primary.withValues(alpha: 0.08),
      highlightColor: ListenColors.primary.withValues(alpha: 0.05),
      focusColor: ListenColors.primary.withValues(alpha: 0.12),
      hoverColor: ListenColors.primary.withValues(alpha: 0.06),
      appBarTheme: const AppBarTheme(
        backgroundColor: ListenColors.surface,
        foregroundColor: ListenColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: ListenColors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: ListenColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: ListenColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ListenColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(ListenColors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(rounded),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: ListenColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ListenColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: ListenColors.border,
          disabledForegroundColor: ListenColors.disabled,
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ListenColors.primaryPressed,
          side: const BorderSide(color: ListenColors.outline),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ListenColors.primaryPressed,
          shape: rounded,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ListenColors.text,
          disabledForegroundColor: ListenColors.disabled,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ListenColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ListenColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ListenColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ListenColors.primary, width: 1.5),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: ListenColors.primary,
        inactiveTrackColor: ListenColors.border,
        thumbColor: ListenColors.primary,
        overlayColor: ListenColors.primary.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ListenColors.primary,
        linearTrackColor: ListenColors.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : ListenColors.disabled,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ListenColors.primary
              : ListenColors.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ListenColors.primary
              : Colors.transparent,
        ),
        side: const BorderSide(color: ListenColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: ListenColors.fog,
        selectedColor: ListenColors.selected,
        side: const BorderSide(color: ListenColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ListenColors.player,
          borderRadius: BorderRadius.circular(5),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: ListenColors.primary,
        selectionColor: Color(0x667ed0c4),
        selectionHandleColor: ListenColors.primary,
      ),
    );
  }
}
