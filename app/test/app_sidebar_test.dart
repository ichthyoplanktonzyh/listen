import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/navigation/app_sidebar.dart';

/// The rail carries two kinds of entry and must not blur them: a destination
/// swaps the shell pane and can be "where you are"; the conversation stage is
/// launched over the shell and never can. These cases pin that split at the
/// type level (an [AppRoute] the shell cannot render must not exist) and at
/// the visual level (the launch action never draws a selection).
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

/// Rows painted with the selected fill — the sidebar's only "you are here"
/// signal.
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
  test('AppRoute admits only destinations the shell can render', () {
    // Conversation is launched over the shell, so it is not a route value:
    // the shell's route switch would need an unreachable arm to survive it.
    expect(
      AppRoute.values.map((route) => route.name),
      isNot(contains('conversation')),
    );
    // Four destinations. The rail used to carry seven under three headings;
    // the headings were the symptom of a list nobody could hold in their
    // head, and they grouped by the system's object model rather than by what
    // the learner came to do. Growing this back past four means asking that
    // question again, not adding a heading.
    expect(AppRoute.values, hasLength(4));
  });

  testWidgets('conversation is a launch action, not a destination', (
    tester,
  ) async {
    final selectedRoutes = <AppRoute>[];
    var launches = 0;

    await tester.pumpWidget(
      _harness(
        AppSidebar(
          currentRoute: AppRoute.today,
          onRouteSelected: selectedRoutes.add,
          onOpenConversation: () => launches++,
        ),
      ),
    );

    await tester.tap(find.text('Start conversation'));
    await tester.pump();

    expect(launches, 1, reason: 'the rail opens the stage directly');
    expect(
      selectedRoutes,
      isEmpty,
      reason: 'launching the stage must not move the shell route',
    );
  });

  testWidgets('the launch action sits below the destination list and never '
      'draws a selection', (tester) async {
    for (final route in AppRoute.values) {
      await tester.pumpWidget(
        _harness(
          AppSidebar(
            currentRoute: route,
            onRouteSelected: (_) {},
            onOpenConversation: () {},
            onOpenSettings: () {},
          ),
        ),
      );

      expect(
        _selectedRowCount(tester),
        1,
        reason:
            'exactly one destination is "here" on $route; neither the launch '
            'action nor settings may claim it',
      );

      // The launch affordance reads as a door: it leaves the grouped
      // destination list behind and is tipped with a leaving arrow.
      final launchLabel = tester.getTopLeft(find.text('Start conversation'));
      final lastDestination = tester.getTopLeft(find.text('Coach'));
      expect(launchLabel.dy, greaterThan(lastDestination.dy));
      expect(find.byIcon(Icons.arrow_outward), findsOneWidget);

      // No group headings: four destinations explain themselves.
      for (final heading in const ['Content', 'Learning', 'Insight']) {
        expect(find.text(heading), findsNothing);
      }
    }
  });
}
