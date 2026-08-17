import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/home/home_pane.dart';

import 'discovery_test_helpers.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    String? recentTitle,
    String? recentPath,
    VoidCallback? onContinue,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final discovery = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      TestMediaLibraryRepository(),
    );
    addTearDown(discovery.dispose);
    await tester.runAsync(discovery.load);

    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HomePane(
            discovery: discovery,
            recentMediaTitle: recentTitle,
            recentMediaPath: recentPath,
            recentPosition: const Duration(minutes: 3),
            recentDuration: const Duration(minutes: 10),
            recentSubtitleCount: 42,
            onContinue: onContinue ?? () {},
            onOpenMedia: () {},
            onPlayMedia: (_) {},
            onOpenDocument: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('puts resume context before discovery when history exists', (
    tester,
  ) async {
    var continued = false;
    await pumpHome(
      tester,
      recentTitle: 'My recent lesson',
      recentPath: '/tmp/recent.mp3',
      onContinue: () => continued = true,
    );

    expect(find.text('Continue learning'), findsOneWidget);
    expect(find.text('My recent lesson'), findsOneWidget);
    expect(find.text('Find something to learn'), findsOneWidget);

    await tester.tap(find.text('My recent lesson'));
    expect(continued, isTrue);
  });

  testWidgets('starts with discovery instead of an empty resume prompt', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('Continue learning'), findsNothing);
    expect(find.text('No recent media yet'), findsNothing);
    expect(find.text('Find something to learn'), findsOneWidget);
  });
}
