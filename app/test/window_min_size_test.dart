import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/widgets/app_bar/player_app_bar.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';

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

  test('the minimum clears the AppBar hard floor', () {
    // Measured in #19: the icon-only AppBar overflows at 470 and is clean at
    // 480, in both locales. A minimum at or below that floor would let #18's
    // overflow back in through the window edge.
    expect(ListenBreakpoints.minWindowWidth, greaterThan(480.0));
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
    home: Scaffold(
      appBar: PlayerAppBar(
        onOpenSubtitleResources: () {},
        onOpenVocabulary: () {},
        onOpenReview: () {},
        onOpenMedia: () {},
        onOpenOnline: () {},
        onImportPrimarySubtitle: () {},
        onGeneratePrimarySubtitles: () {},
        onSearchPrimarySubtitles: () {},
        onImportSecondarySubtitle: () {},
        onGenerateSecondarySubtitles: () {},
        onSearchSecondarySubtitles: () {},
        onImportEmbeddedSubtitle: () {},
        onOpenSettings: () {},
        onExportLogs: () {},
        onExportVocabulary: () {},
        onImportVocabulary: () {},
        onImportWordList: () {},
        onArchiveMedia: () {},
        onOpenTranscriptionCenter: () {},
        onOpenPhoneticAnalysisCenter: () {},
        onOpenLearningAssets: () {},
        onOpenLearningResources: () {},
      ),
      body: ListeningHome(
        onOpenMedia: () {},
        onOpenOnline: () {},
        onContinue: () {},
        onOpenSubtitleResources: () {},
        onOpenVocabulary: () {},
        onOpenPersonalExpressions: () {},
        onOpenConversation: () {},
        onOpenReview: () {},
        onOpenCoach: () {},
        onOpenSettings: () {},
      ),
    ),
  );

  testWidgets('app bar and home render clean at exactly the minimum', (
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
