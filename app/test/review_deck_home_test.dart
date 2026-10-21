import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_deck_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/screens/review_deck_home_screen.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

import 'support/review_repository_fake.dart';

class _FakeDeckRepository extends FakeReviewRepositoryBase {
  _FakeDeckRepository({this.overview});

  ReviewDeckOverview? overview;
  int overviewCalls = 0;
  ReviewDailyLimits? savedLimits;

  @override
  Future<ReviewDeckOverview> deckOverview() async {
    overviewCalls++;
    final value = overview;
    if (value == null) throw StateError('no overview');
    return value;
  }

  @override
  Future<ReviewDailyLimits> updateDailyLimits(ReviewDailyLimits limits) async {
    savedLimits = limits;
    return limits;
  }
}

ReviewStateCounts _counts({int newCards = 0, int learning = 0, int due = 0}) =>
    ReviewStateCounts(newCards: newCards, learning: learning, due: due);

ReviewDeckOverview _overview({
  List<ReviewChannelDeck>? channels,
  ReviewLimitStatus? limitStatus,
}) => ReviewDeckOverview(
  channels:
      channels ??
      [
        ReviewChannelDeck(
          channel: 'listening',
          counts: _counts(newCards: 12, learning: 3, due: 9),
        ),
      ],
  limitStatus: limitStatus ?? fakeLimitStatus(),
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeDeckRepository repository,
  void Function(CustomStudyRequest request)? onStartCustomStudy,
  VoidCallback? onStartSession,
}) async {
  final controller = ReviewDeckController(repository);
  addTearDown(controller.dispose);
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
      home: ReviewDeckHomeScreen(
        controller: controller,
        onStartSession: onStartSession ?? () {},
        onStartCustomStudy: onStartCustomStudy ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('audio-linked cards form the listening review queue', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    await _pump(tester, repository: repository);

    expect(find.text('Cards from your media'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('waiting today'), findsOneWidget);
    expect(find.text('Speaking'), findsNothing);
    expect(find.text('Writing'), findsNothing);
  });

  testWidgets('a spent budget is named as such, not as an empty queue', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(
        channels: const [],
        limitStatus: fakeLimitStatus(
          newCompleted: 20,
          reviewsCompleted: 200,
          newLimitReached: true,
          reviewLimitReached: true,
        ),
      ),
    );
    await _pump(tester, repository: repository);

    expect(find.text('That is enough for today'), findsOneWidget);
    expect(find.text('No sound cards due right now'), findsNothing);
    expect(find.textContaining('20/20 new · 200/200 reviews'), findsOneWidget);
  });

  testWidgets('an empty queue under an unspent budget says nothing is due', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(channels: const []),
    );
    await _pump(tester, repository: repository);

    expect(find.text('No sound cards due right now'), findsOneWidget);
    expect(find.text('That is enough for today'), findsNothing);
  });

  testWidgets('a failed load shows the failure instead of zero counts', (
    tester,
  ) async {
    final repository = _FakeDeckRepository();
    await _pump(tester, repository: repository);

    expect(find.text('Could not load review decks'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('waiting today'), findsNothing);
  });

  testWidgets('custom study keeps every extra queue in listening', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    final requests = <CustomStudyRequest>[];
    await _pump(
      tester,
      repository: repository,
      onStartCustomStudy: requests.add,
    );

    await tester.tap(find.text('Ten more new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redo the forgotten'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Listening'));
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.kind), [
      CustomStudyKind.moreNew,
      CustomStudyKind.forgotten,
      CustomStudyKind.channel,
    ]);
    expect(requests.last.channel, 'listening');
  });

  testWidgets('an empty listening custom queue is disabled', (tester) async {
    final repository = _FakeDeckRepository(
      overview: _overview(
        channels: [ReviewChannelDeck(channel: 'listening', counts: _counts())],
      ),
    );
    await _pump(tester, repository: repository);

    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Listening'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('editing daily limits saves and re-reads the counts', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    await _pump(tester, repository: repository);
    expect(repository.overviewCalls, 1);

    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New cards per day'),
      '5',
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.savedLimits?.newCards, 5);
    expect(repository.savedLimits?.reviews, 200);
    expect(repository.overviewCalls, 2);
  });
}
