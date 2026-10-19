import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_due_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/typography.dart';
import 'package:llplayer_next/widgets/home/today_pane.dart';

/// The today pane is the app's answer to "what should I do now", and every
/// row on it is a count the learner will read as a fact about their day.
///
/// The gate this file exists for: **the four due-count states must never
/// impersonate one another.** "Nobody has asked yet", "the answer is on its
/// way", "the answer is zero" and "asking failed" are four different facts,
/// and only one of them may be drawn as `0`. A single `?? 0` anywhere on the
/// path from [ReviewDueController] to this pane would quietly tell a learner
/// their day is clear when nothing has said so — which is exactly the kind of
/// lie AGENT.md's honesty constraint rules out for a product that teaches a
/// language.
///
/// The rest of the cases pin the same rule for the other counts, and pin that
/// a door only exists where there is somewhere to go.
Widget _app({
  ReviewDueState reviewDue = const ReviewDueState.unknown(),
  VoidCallback? onOpenReview,
  VoidCallback? onRetryReviewDue,
  String? recentMediaTitle,
  Duration recentPosition = Duration.zero,
  Duration recentDuration = Duration.zero,
  int recentSubtitleCount = 0,
  int vocabularyCount = 0,
  bool vocabularyCapped = false,
  bool vocabularyKnown = false,
  int listeningInboxCount = 0,
  String coreStatusText = '',
  VoidCallback? onContinue,
  VoidCallback? onOpenMedia,
  VoidCallback? onOpenVocabulary,
}) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: TodayPane(
      recentMediaTitle: recentMediaTitle,
      recentMediaPath: null,
      recentPosition: recentPosition,
      recentDuration: recentDuration,
      recentSubtitleCount: recentSubtitleCount,
      onContinue: onContinue ?? () {},
      onOpenMedia: onOpenMedia ?? () {},
      reviewDue: reviewDue,
      onOpenReview: onOpenReview ?? () {},
      onRetryReviewDue: onRetryReviewDue ?? () {},
      onOpenVocabulary: onOpenVocabulary ?? () {},
      vocabularyCount: vocabularyCount,
      vocabularyCapped: vocabularyCapped,
      vocabularyKnown: vocabularyKnown,
      listeningInboxCount: listeningInboxCount,
      coreStatusText: coreStatusText,
    ),
  ),
);

/// The count drawn on the row carrying [label]. Scoped to one row on
/// purpose: "is there a zero anywhere on the page" would pass or fail for the
/// wrong reasons, since some rows legitimately report zero.
String _countFor(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final counts = tester
      .widgetList<Text>(
        find.descendant(of: row.first, matching: find.byType(Text)),
      )
      .where((text) => text.style?.fontWeight == FontWeight.w800)
      .map((text) => text.data ?? '')
      .toList(growable: false);
  expect(counts, hasLength(1), reason: 'one count per row on "$label"');
  return counts.single;
}

void main() {
  group('the due count never invents a fact', () {
    testWidgets('unknown reads as unknown, not as zero', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // The dash is the whole point: nobody has reported a number.
      expect(find.text('今天待复习'), findsOneWidget);
      expect(_countFor(tester, '今天待复习'), '—');
      // And it says *why* it does not know.
      expect(find.text('请先连接本地核心'), findsOneWidget);
    });

    testWidgets('loading waits out loud instead of guessing zero', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _app(reviewDue: const ReviewDueState(status: ReviewDueStatus.loading)),
      );
      await tester.pump();

      expect(_countFor(tester, '今天待复习'), '—');
      expect(
        find.bySemanticsLabel('正在加载…'),
        findsOneWidget,
        reason: 'waiting uses the shared waiting language, not a filled count',
      );
    });

    testWidgets('a real zero is written as zero and stays a door', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = 0;

      await tester.pumpWidget(
        _app(
          reviewDue: const ReviewDueState(
            status: ReviewDueStatus.loaded,
            count: 0,
          ),
          onOpenReview: () => opened += 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(_countFor(tester, '今天待复习'), '0');

      // "Nothing is due today" is something the review home says better than
      // a dead tile does, so a true zero is still walkable.
      await tester.tap(find.text('今天待复习'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('failure states the failure and offers a retry', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retries = 0;

      await tester.pumpWidget(
        _app(
          reviewDue: const ReviewDueState(status: ReviewDueStatus.failed),
          onRetryReviewDue: () => retries += 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('无法读取待复习数量。'), findsOneWidget);
      // Not degraded to zero, and not silently empty.
      expect(_countFor(tester, '今天待复习'), '—');

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('a loaded count is the number the backend reported', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _app(
          reviewDue: const ReviewDueState(
            status: ReviewDueStatus.loaded,
            count: 12,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_countFor(tester, '今天待复习'), '12');
    });
  });

  testWidgets('an unreported vocabulary total is unknown, not zero', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(vocabularyCount: 0, vocabularyKnown: false));
    await tester.pumpAndSettle();
    expect(find.text('已存词条'), findsOneWidget);
    expect(_countFor(tester, '已存词条'), '—');

    // Known-and-zero is a different fact and is written as one.
    await tester.pumpWidget(_app(vocabularyCount: 0, vocabularyKnown: true));
    await tester.pumpAndSettle();
    expect(_countFor(tester, '已存词条'), '0');

    // A capped total says it is capped rather than pretending to be exact.
    await tester.pumpWidget(
      _app(vocabularyCount: 500, vocabularyKnown: true, vocabularyCapped: true),
    );
    await tester.pumpAndSettle();
    expect(_countFor(tester, '已存词条'), '500+');
  });

  testWidgets('the listening inbox states its count without pretending to be '
      'a destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        listeningInboxCount: 3,
        reviewDue: const ReviewDueState(
          status: ReviewDueStatus.loaded,
          count: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_countFor(tester, '泛听收集箱'), '3');

    // The inbox lives inside the workbench's listening panel. A tile that
    // opened the workbench would be a second copy of "continue listening" —
    // the exact duplication this restructure removed — so it is a statement,
    // not a door. Doors are the ones with a chevron.
    final doors = find.byIcon(Icons.chevron_right);
    expect(
      tester.widgetList(doors),
      hasLength(3),
      reason: 'continue, review and vocabulary are doors; the inbox is not',
    );
  });

  testWidgets('the core health line is present without a count beside it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // Empty status means nothing to report, which is the ready state — the
    // line stays visible because a disconnected core is *why* the other rows
    // may read as unknown.
    expect(find.text('就绪'), findsOneWidget);

    await tester.pumpWidget(_app(coreStatusText: '本地内核不可用'));
    await tester.pumpAndSettle();
    expect(find.text('本地内核不可用'), findsOneWidget);
    expect(find.text('就绪'), findsNothing);
  });

  testWidgets('recent media offers a continue door; nothing recent offers a '
      'way to open something', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var continues = 0;
    var opens = 0;

    await tester.pumpWidget(
      _app(
        recentMediaTitle: 'BBC News Review.mp4',
        recentPosition: const Duration(minutes: 3, seconds: 20),
        recentDuration: const Duration(minutes: 10),
        recentSubtitleCount: 42,
        onContinue: () => continues += 1,
        onOpenMedia: () => opens += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BBC News Review.mp4'), findsOneWidget);
    // The transcript rung rides on the card that describes that media.
    expect(find.textContaining('42'), findsOneWidget);

    await tester.tap(find.text('BBC News Review.mp4'));
    await tester.pumpAndSettle();
    expect(continues, 1);
    expect(opens, 0);

    await tester.pumpWidget(_app(onOpenMedia: () => opens += 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('还没有最近媒体'));
    await tester.pumpAndSettle();
    expect(opens, 1);
  });

  testWidgets('today carries the one hero title', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('今天')).style?.fontSize,
      ListenType.hero.fontSize,
    );
  });

  testWidgets('the page states that a due count is information, not debt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Charter principle 3: present, never pushy. No streak, no goal, no
    // guilt — the page says so out loud.
    expect(find.text('到期数量只是信息，不是欠账。'), findsOneWidget);
  });
}
