import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/navigation/app_sidebar.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Row(children: [child])),
);

int _selectedRowCount(WidgetTester tester) {
  final selectedFill = ListenTheme.light().colorScheme.secondaryContainer;
  return tester
      .widgetList<Container>(find.byType(Container))
      .where(
        (container) =>
            container.decoration is BoxDecoration &&
            (container.decoration as BoxDecoration).color == selectedFill,
      )
      .length;
}

void main() {
  test('the rail contains the three current shell destinations', () {
    expect(AppRoute.values.map((route) => route.name), [
      'home',
      'library',
      'language',
    ]);
  });

  testWidgets('selecting a destination reports the route to the shell', (
    tester,
  ) async {
    final selectedRoutes = <AppRoute>[];

    await tester.pumpWidget(
      _harness(
        AppSidebar(
          currentRoute: AppRoute.home,
          onRouteSelected: selectedRoutes.add,
        ),
      ),
    );

    await tester.tap(find.text('My language'));

    expect(selectedRoutes, [AppRoute.language]);
  });

  testWidgets('only the selected destination is highlighted', (tester) async {
    for (final route in AppRoute.values) {
      await tester.pumpWidget(
        _harness(AppSidebar(currentRoute: route, onRouteSelected: (_) {})),
      );

      expect(_selectedRowCount(tester), 1, reason: 'selected $route');
    }
  });

  testWidgets('the rail names the current destinations', (tester) async {
    await tester.pumpWidget(
      _harness(
        AppSidebar(currentRoute: AppRoute.home, onRouteSelected: (_) {}),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('My language'), findsOneWidget);
    expect(find.text('Coach'), findsNothing);
    expect(find.text('Start conversation'), findsNothing);
  });
}
