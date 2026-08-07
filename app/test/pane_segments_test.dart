import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/navigation/pane_segments.dart';

/// Two destinations hold several surfaces as segments — "listen" (discovery /
/// media library) and "my language" (vocabulary / expressions / review).
///
/// The rule these cases pin: a segmented pane is **controlled**. The shell
/// owns the selection, so a caller that has to reach a specific surface — the
/// coach's suggestions land on review, on vocabulary, on expressions — can
/// open the pane there. A pane that owned its own selection could only ever
/// be entered at its first segment, which would put the coach's doors back
/// where this restructure found them: pointing at a page and hoping.
Widget _harness({
  required LanguageSegment selected,
  required ValueChanged<LanguageSegment> onSelected,
}) => MaterialApp(
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
    body: SegmentedPane<LanguageSegment>(
      selected: selected,
      onSelected: onSelected,
      segments: [
        PaneSegment(
          value: LanguageSegment.vocabulary,
          label: 'Vocabulary',
          builder: (context) => const Text('vocabulary body'),
        ),
        PaneSegment(
          value: LanguageSegment.expressions,
          label: 'Expressions',
          builder: (context) => const Text('expressions body'),
        ),
        PaneSegment(
          value: LanguageSegment.review,
          label: 'Review',
          builder: (context) => const Text('review body'),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('the pane opens at the segment it was given', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The coach's "review this" suggestion has to arrive at review, not at
    // whichever segment happens to be first.
    await tester.pumpWidget(
      _harness(selected: LanguageSegment.review, onSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('review body'), findsOneWidget);
    expect(find.text('vocabulary body'), findsNothing);
    expect(find.text('expressions body'), findsNothing);
  });

  testWidgets('only the selected segment is built', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Switching disposes the previous body, which is what the route-scoped
    // controller hosts expect: build on entry, dispose on leave. Building all
    // three would keep three sets of controllers alive on a page showing one.
    await tester.pumpWidget(
      _harness(selected: LanguageSegment.vocabulary, onSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('vocabulary body'), findsOneWidget);
    expect(find.text('review body'), findsNothing);
  });

  testWidgets('choosing a segment reports up instead of self-selecting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chosen = <LanguageSegment>[];

    await tester.pumpWidget(
      _harness(selected: LanguageSegment.vocabulary, onSelected: chosen.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(chosen, [LanguageSegment.review]);
    // The pane did not move itself: the shell owns the selection, so a stale
    // `selected` must keep showing the surface the shell asked for.
    expect(find.text('vocabulary body'), findsOneWidget);
    expect(find.text('review body'), findsNothing);
  });
}
