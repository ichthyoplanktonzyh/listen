import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_shortcuts.dart';
import 'package:llplayer_next/widgets/player/shortcut_cheat_sheet.dart';

/// #25: the cheat sheet is a pure view of the shortcut table — every entry
/// shows up, localized, with its key caption.
void main() {
  Widget host(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: ShortcutCheatSheet()),
  );

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('renders every table entry in $locale', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(locale));

      final l = AppLocalizations(locale);
      for (final category in PlayerShortcutCategory.values) {
        expect(find.text(l.text(category.labelKey)), findsWidgets);
      }
      for (final shortcut in playerShortcuts) {
        expect(
          find.text(l.text(shortcut.labelKey)),
          findsWidgets,
          reason: '${shortcut.id} label missing in $locale',
        );
        expect(
          find.text(shortcutCaption(shortcut.activator)),
          findsWidgets,
          reason: '${shortcut.id} caption missing',
        );
      }
    });
  }
}
