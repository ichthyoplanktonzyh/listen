import 'package:flutter/material.dart';

import '../theme/radii.dart';
import '../theme/typography.dart';

/// App-wide appearance preference, mirrored from the persisted `themeMode`
/// setting. Mirrors the `appLanguage` notifier so `ListenApp` can rebuild the
/// single `MaterialApp` without threading the value through the widget tree.
/// Defaults to dark — "暗色为家" per the design charter
/// (design-notes/listen-design-charter.md) — so the first frame is already the
/// dimmed room instead of flashing a bright theme before settings load.
final appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

/// Maps the persisted `system` / `light` / `dark` string onto [ThemeMode],
/// degrading unknown values to [ThemeMode.system].
ThemeMode themeModeFromSetting(String value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

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

  // Media overlays use a separate dark-surface vocabulary so learning signals
  // remain legible over arbitrary video frames.
  static const overlaySurface = Color(0xd9101715);
  static const overlaySurfaceSoft = Color(0xb8101715);
  static const overlayBorder = Color(0x30ffffff);
  static const overlayText = Color(0xfff2f5f4);
  static const overlayTextMuted = Color(0xaaeef3f1);
  static const overlayTextFaint = Color(0x76eef3f1);
  static const overlayInk = Color(0xdc101715);

  /// The charter signal teal for content rendered over video. Overlays keep
  /// one dark vocabulary in both themes, so the "current word" light source
  /// must not flip to the light theme's deep teal — it would sink into the
  /// overlay ink (#30).
  static const overlaySignal = Color(0xff4db8a8);

  static const soundCitation = Color(0xff8fd3ff);
  static const soundConnected = Color(0xff6dd6c3);
  static const soundConnectedStrong = Color(0xffa7f3e8);
  static const soundActual = Color(0xffffd166);
  static const soundPredicted = Color(0xffffa94d);
  static const soundPredictedText = Color(0xffffc98a);
  static const soundNucleus = Color(0xffff8fb7);

  static const phonemeTextVowel = Color(0xff5b8def);
  static const phonemeTextApproximant = Color(0xff7bc47f);
  static const phonemeTextConsonant = Color(0xffe8935a);
  static const phonemeSoundVowel = Color(0xff00a8a8);
  static const phonemeSoundApproximant = Color(0xffb76eae);
  static const phonemeSoundConsonant = Color(0xffd79d2a);
  static const learningNeedsReview = Color(0xffffbf47);
  static const learningRecognized = Color(0xff68d391);

  // ── Dark theme surfaces ──
  // Anchored on [player] so chrome recedes toward the same near-black the video
  // stage already uses, keeping the brand teal readable at AA on every surface.
  static const darkSurface = Color(0xff141b19);
  static const darkFog = Color(0xff1b2422);
  static const darkSidebar = Color(0xff202a27);
  static const darkText = Color(0xffe6ecea);
  static const darkMuted = Color(0xffa3b0ac);
  static const darkOutline = Color(0xff6d7a76);
  static const darkBorder = Color(0xff333f3b);
  static const darkDisabled = Color(0xff6b7874);
  // Charter signal teal (design-notes/listen-design-charter.md): the one
  // color that means "this is the content speaking" — current word, progress,
  // selection. Calibrated from #5cc6b8 in Slice 2 (#30).
  static const darkPrimary = Color(0xff4db8a8);
  static const darkPrimaryPressed = Color(0xff8bdcd0);
  static const darkSelected = Color(0xff1d4f49);
  static const darkAccent = Color(0xffe6b45c);
  static const darkInfo = Color(0xff7fb0d4);
  static const darkInfoSurface = Color(0xff23415a);
  static const darkError = Color(0xffef8a8a);
}

/// The two product shades [ColorScheme] has no slot for. Exposing them here
/// keeps call sites brightness-agnostic: read them off `Theme.of(context)
/// .colorScheme` exactly like the standard roles instead of reaching for a
/// light-only constant.
extension ListenSchemeShades on ColorScheme {
  /// Foreground for disabled controls and inert secondary text.
  Color get disabledForeground => brightness == Brightness.light
      ? ListenColors.disabled
      : ListenColors.darkDisabled;

  /// Primary shade for text/outline buttons, which sit on a surface rather
  /// than on [primary] and so need the deeper (light) or lifted (dark) tone.
  Color get pressedPrimary => brightness == Brightness.light
      ? ListenColors.primaryPressed
      : ListenColors.darkPrimaryPressed;
}

abstract final class ListenTheme {
  static ThemeData light() => _build(_lightScheme);

  static ThemeData dark() => _build(_darkScheme);

  static const _lightScheme = ColorScheme(
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

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: ListenColors.darkPrimary,
    onPrimary: Color(0xff00302b),
    primaryContainer: ListenColors.darkSelected,
    onPrimaryContainer: Color(0xffb3ebe2),
    secondary: ListenColors.darkAccent,
    onSecondary: Color(0xff3a2905),
    secondaryContainer: Color(0xff4a3a12),
    onSecondaryContainer: Color(0xfff5dfae),
    tertiary: ListenColors.darkInfo,
    onTertiary: Color(0xff10293b),
    tertiaryContainer: ListenColors.darkInfoSurface,
    onTertiaryContainer: Color(0xffcde3f2),
    error: ListenColors.darkError,
    onError: Color(0xff4a1313),
    errorContainer: Color(0xff5e2727),
    onErrorContainer: Color(0xffffd9d9),
    surface: ListenColors.darkSurface,
    onSurface: ListenColors.darkText,
    surfaceContainerLowest: Color(0xff0d1412),
    surfaceContainerLow: Color(0xff171f1d),
    surfaceContainer: ListenColors.darkFog,
    surfaceContainerHigh: ListenColors.darkSidebar,
    surfaceContainerHighest: Color(0xff26312e),
    onSurfaceVariant: ListenColors.darkMuted,
    outline: ListenColors.darkOutline,
    outlineVariant: ListenColors.darkBorder,
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
    inverseSurface: ListenColors.darkText,
    onInverseSurface: ListenColors.text,
    inversePrimary: ListenColors.primary,
    surfaceTint: Colors.transparent,
  );

  /// Both themes share one component-theme structure; only the [ColorScheme]
  /// differs (plus the two shades it has no slot for, which
  /// [ListenSchemeShades] derives from it), so a component styled once stays
  /// consistent across brightnesses.
  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final rounded = RoundedRectangleBorder(
      borderRadius: ListenRadii.controlBorder,
    );
    // The keyboard focus language (#46): a thin signal-teal outline — the one
    // color that means "this is where you are" — drawn on whichever control
    // holds focus. One resolver shared by the button families so Tab reads
    // identically everywhere; text fields already speak it via
    // `focusedBorder`. Width pairs with the input focus border (1.5).
    WidgetStateProperty<BorderSide?> focusRing([BorderSide? restingSide]) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: scheme.primary, width: 1.5)
              : restingSide,
        );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      scaffoldBackgroundColor: scheme.surfaceContainer,
      canvasColor: scheme.surfaceContainer,
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: scheme.primary.withValues(alpha: 0.05),
      focusColor: scheme.primary.withValues(alpha: 0.12),
      hoverColor: scheme.primary.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: ListenRadii.surfaceBorder,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: ListenRadii.surfaceBorder),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(rounded),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              disabledBackgroundColor: scheme.outlineVariant,
              disabledForegroundColor: scheme.disabledForeground,
              shape: rounded,
            ).copyWith(
              // On the primary fill the teal ring would vanish into its own
              // color, so this one family rings in the on-color instead.
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: scheme.onPrimary, width: 1.5)
                    : null,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: scheme.pressedPrimary,
              shape: rounded,
            ).copyWith(
              side: focusRing(BorderSide(color: scheme.outline)),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: scheme.pressedPrimary,
              shape: rounded,
            ).copyWith(side: focusRing()),
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              foregroundColor: scheme.onSurface,
              disabledForegroundColor: scheme.disabledForeground,
              shape: RoundedRectangleBorder(
                borderRadius: ListenRadii.controlBorder,
              ),
            ).copyWith(side: focusRing()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: ListenRadii.controlBorder,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ListenRadii.controlBorder,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ListenRadii.controlBorder,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.disabledForeground,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outlineVariant,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: ListenRadii.tightBorder),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: ListenRadii.controlBorder),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: ListenRadii.tightBorder,
        ),
        textStyle: ListenType.body.copyWith(color: scheme.onInverseSurface),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.inversePrimary.withValues(alpha: 0.4),
        selectionHandleColor: scheme.primary,
      ),
    );
  }

  /// Projects the [ListenType] ladder onto Material's `textTheme` slots and
  /// pins the bundled families ([ListenFonts.sans], SC fallback for mixed
  /// 中英 runs), so `Theme.of(context).textTheme` sites and the constants
  /// agree. Slots beyond the ladder (display/headline) keep Material's
  /// geometry — nothing in the app uses them yet, so they earn no bespoke
  /// values.
  static TextTheme _textTheme(TextTheme base) => base
      .copyWith(
        labelSmall: base.labelSmall?.merge(ListenType.caption),
        labelMedium: base.labelMedium?.merge(ListenType.body),
        bodySmall: base.bodySmall?.merge(ListenType.body),
        bodyMedium: base.bodyMedium?.merge(ListenType.reading),
        bodyLarge: base.bodyLarge?.merge(ListenType.emphasis),
        titleSmall: base.titleSmall?.merge(ListenType.emphasis),
        titleMedium: base.titleMedium?.merge(ListenType.title),
        titleLarge: base.titleLarge?.merge(ListenType.hero),
      )
      .apply(
        fontFamily: ListenFonts.sans,
        fontFamilyFallback: const [ListenFonts.sansSC],
      );
}
