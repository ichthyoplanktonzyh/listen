import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';
import 'package:llplayer_next/widgets/navigation/app_sidebar.dart';
import 'package:llplayer_next/widgets/navigation/shell_tools_menu.dart';

/// The window minimum is declared twice — once in Dart so the layout code can
/// reason about it, once in Swift where the platform actually enforces it.
/// Two languages means the pair can silently drift, so one test pins the
/// numbers together and another proves the number is actually big enough.
void main() {
  test('the Swift shell enforces the Dart-side window minimum', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final declaration = RegExp(
      r'contentMinimumSize\s*=\s*NSSize\(width:\s*(\d+),\s*height:\s*(\d+)\)',
    ).firstMatch(source);

    expect(
      declaration,
      isNotNull,
      reason:
          'MainFlutterWindow.swift no longer declares contentMinimumSize as a '
          'literal NSSize; update this test alongside it.',
    );
    expect(
      double.parse(declaration!.group(1)!),
      ListenBreakpoints.minWindowWidth,
      reason: 'Swift width drifted from ListenBreakpoints.minWindowWidth',
    );
    expect(
      double.parse(declaration.group(2)!),
      ListenBreakpoints.minWindowHeight,
      reason: 'Swift height drifted from ListenBreakpoints.minWindowHeight',
    );
  });

  test('the minimum leaves a usable pane beside the rail', () {
    // The floor used to be the icon-only AppBar, measured in #19 at 470/480.
    // That bar is gone; the rail is the shell chrome now, and it is a fixed
    // 240 wide. The number stays where it was, but what it has to clear is
    // the rail plus a pane wide enough to be worth rendering.
    expect(ListenBreakpoints.minWindowWidth, greaterThan(480.0));
    expect(
      ListenBreakpoints.minWindowWidth - AppSidebar.railWidth,
      greaterThan(240.0),
      reason: 'the rail must not eat the window it lives in',
    );
  });

  Widget app(Locale locale) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    // The shell at its narrowest: the rail (with its full footer) beside a
    // pane. There is no app bar to overflow any more, so what this has to
    // prove is that the rail and a real page still fit side by side.
    home: Scaffold(
      body: Row(
        children: [
          AppSidebar(
            currentRoute: AppRoute.library,
            onRouteSelected: (_) {},
            onOpenConversation: () {},
            onOpenSettings: () {},
            toolsMenu: ShellToolsMenu(
              onOpenLearningAssets: () {},
              onOpenLearningResources: () {},
              onExportLogs: () {},
              onExportVocabulary: () {},
              onImportVocabulary: () {},
              onImportWordList: () {},
            ),
          ),
          const Expanded(
            child: ListeningHome(onOpenMedia: _noop, onOpenOnline: _noop),
          ),
        ],
      ),
    ),
  );

  testWidgets('the rail and a page render clean at exactly the minimum', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('zh')]) {
      await tester.binding.setSurfaceSize(
        const Size(
          ListenBreakpoints.minWindowWidth,
          ListenBreakpoints.minWindowHeight,
        ),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$locale at the minimum');
    }
  });
}

void _noop() {}
