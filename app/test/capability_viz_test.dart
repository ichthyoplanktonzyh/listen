import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/coach_dashboard.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';

// The capability portrait (#47) is presentation only: these tests pin the
// owner-approved graphic language — compass segment maths, echo-bar ghosts,
// state colors — against the shared 2x2 semantics, without touching any
// analysis data or evidence gating.

CoachChannelSummary channel(
  String name, {
  int acquired = 0,
  int notAcquired = 0,
  int unassessed = 0,
}) => CoachChannelSummary(
  channel: name,
  status: 'active',
  metrics: const [],
  effectiveAssessments: CoachAssessmentSummary(
    acquired: acquired,
    notAcquired: notAcquired,
    unassessed: unassessed,
  ),
);

// The design-doc mock: a 160-word library that can recognize far more than
// it can produce.
final portraitChannels = [
  channel('listening', acquired: 46, notAcquired: 18, unassessed: 96),
  channel('reading', acquired: 88, notAcquired: 10, unassessed: 62),
  channel('speaking', acquired: 12, notAcquired: 30, unassessed: 118),
  channel('writing', acquired: 8, notAcquired: 22, unassessed: 130),
];

CoachDashboard dashboard({List<CoachSuggestion> suggestions = const []}) =>
    CoachDashboard(
      channels: portraitChannels,
      suggestions: suggestions,
      starterChecklist: const [],
      materials: const [],
      periodStartMs: 0,
      periodEndMs: 0,
      generatedAtMs: 0,
      features: const [],
    );

Widget localized(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  // The shared scale across every capability graphic: the largest assessed
  // (acquired + not acquired) count, unassessed deliberately excluded.
  final unit = capabilityAssessedUnit(
    portraitChannels.map((c) => c.effectiveAssessments),
  );

  group('capabilityAssessedUnit', () {
    test('scales by what was measured, never by the size of the library', () {
      // reading is the best-assessed channel at 88 + 10; the 62 words nobody
      // looked at do not enlarge the scale.
      expect(unit, 98);
      expect(
        capabilityAssessedUnit([
          const CoachAssessmentSummary(
            acquired: 5,
            notAcquired: 3,
            unassessed: 200,
          ),
        ]),
        8,
      );
    });

    test('nothing assessed anywhere is a zero unit, not a tiny one', () {
      expect(
        capabilityAssessedUnit([
          const CoachAssessmentSummary(
            acquired: 0,
            notAcquired: 0,
            unassessed: 900,
          ),
        ]),
        0,
      );
    });
  });

  group('compassSegments', () {
    test('reception anchors the acquired light toward 12 o\'clock', () {
      // listening quadrant runs 274..356; anchored at the end means the
      // acquired segment must terminate exactly at 356.
      final segments = compassSegments('listening', 46, 18, unit);
      expect(segments.map((s) => s.$3), [
        capabilityUnmeasured,
        'not_acquired',
        'acquired',
      ]);
      final acquired = segments.last;
      expect(acquired.$1 + acquired.$2, closeTo(356, 0.001));
      // Scaled against the assessed unit (98), not the 160-word library.
      expect(acquired.$2, closeTo(82 * 46 / 98, 0.001));
    });

    test('production anchors the acquired light toward 6 o\'clock', () {
      // speaking starts at 184 (just past 6 o'clock) with acquired first…
      final speaking = compassSegments('speaking', 12, 30, unit);
      expect(speaking.first.$3, 'acquired');
      expect(speaking.first.$1, 184);
      // …and writing ends at 176 (just before 6 o'clock) with acquired last.
      final writing = compassSegments('writing', 8, 22, unit);
      expect(writing.last.$3, 'acquired');
      expect(writing.last.$1 + writing.last.$2, closeTo(176, 0.001));
    });

    test('the unmeasured remainder is what is left of the shared unit', () {
      // listening assessed 64 of the shared 98: the lit arcs cover 64/98 of
      // the quadrant and the rest is the dashed track, never fill.
      final segments = compassSegments('listening', 46, 18, unit);
      final lit = segments
          .where((s) => s.$3 != capabilityUnmeasured)
          .fold(0.0, (sum, s) => sum + s.$2);
      expect(lit, closeTo(82 * 64 / 98, 0.001));
      expect(
        segments.singleWhere((s) => s.$3 == capabilityUnmeasured).$2,
        closeTo(82 * 34 / 98, 0.001),
      );
    });

    test('a fully assessed channel leaves no unmeasured track', () {
      final segments = compassSegments('reading', 5, 3, 8);
      expect(segments.map((s) => s.$3), ['acquired', 'not_acquired']);
      expect(segments.fold(0.0, (sum, s) => sum + s.$2), closeTo(82, 0.001));
    });

    test('zero counts honestly fill the quadrant as unmeasured', () {
      expect(compassSegments('reading', 0, 0, 0), [
        (4, 82, capabilityUnmeasured),
      ]);
      // A channel with a large unassessed stock but no assessments reads the
      // same: the ring has nothing measured to draw for it.
      expect(compassSegments('reading', 0, 0, 98), [
        (4, 82, capabilityUnmeasured),
      ]);
    });

    test('empty states are skipped instead of rendered as zero-sweep arcs', () {
      final segments = compassSegments('reading', 5, 0, 20);
      expect(segments.map((s) => s.$3), ['acquired', capabilityUnmeasured]);
    });
  });

  test('crossModalGapCount only reports the backend join, never a guess', () {
    expect(crossModalGapCount(dashboard()), isNull);
    const gap = CoachSuggestion(
      kind: 'review',
      id: 'cross-modal-review',
      titleKey: 'coachSuggestionCrossModal',
      reasonKey: 'coachSuggestionCrossModalReason',
      destination: CoachSuggestionDestination(kind: 'review'),
      evidenceSource: 'capability_join',
      evidenceCount: 96,
    );
    expect(crossModalGapCount(dashboard(suggestions: const [gap])), 96);
  });

  test('assessment colors: teal light, amber target, dimmed unknown', () {
    const scheme = ColorScheme.dark(
      primary: Color(0xff4db8a8),
      secondary: Color(0xffe6b45c),
    );
    expect(capabilityAssessmentColor(scheme, 'acquired'), scheme.primary);
    expect(capabilityAssessmentColor(scheme, 'not_acquired'), scheme.secondary);
    // Unassessed is dimmed but present — never fully hidden.
    expect(capabilityAssessmentColor(scheme, 'unassessed').a, lessThan(0.5));
  });

  testWidgets(
    'the portrait ring names every channel state for hover and a11y',
    (tester) async {
      await tester.pumpWidget(
        localized(
          const CapabilityRing(
            assessments: {
              'listening': 'acquired',
              'reading': 'acquired',
              'speaking': 'not_acquired',
              'writing': 'unassessed',
            },
            withTooltip: true,
          ),
        ),
      );
      expect(
        find.byTooltip(
          'Listening: Acquired\n'
          'Reading: Acquired\n'
          'Writing: Not yet assessed\n'
          'Speaking: Not acquired',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('echo bars mirror the reception light as the gap ghost', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 600,
          child: CapabilityEchoBars(channels: portraitChannels),
        ),
      ),
    );
    // The ghost under the sound column repeats listening's acquired height:
    // 46 of the 98-word assessed scale on a 96px bar.
    final ghost = tester.getSize(
      find.byKey(const ValueKey('echo-ghost-sound')),
    );
    expect(ghost.height, closeTo(96 * 46 / 98, 0.01));
    expect(find.byKey(const ValueKey('echo-ghost-text')), findsOneWidget);
    // Gap captions juxtapose the two existing counts — no frontend arithmetic.
    expect(find.text('can hear 46 · can say 12'), findsOneWidget);
    expect(find.text('can read 88 · can write 8'), findsOneWidget);
    // The unassessed stock left the graphic, so it is stated in the caption
    // instead: no information is lost with the ink.
    expect(find.text('Listening · 46 · Unassessed 96'), findsOneWidget);
    expect(find.text('Speaking · 12 · Unassessed 118'), findsOneWidget);
    // Hovering a bar reveals the honest three-state numbers.
    expect(
      find.byTooltip(
        'Listening · Acquired 46 · Not acquired 18 · Unassessed 96',
      ),
      findsOneWidget,
    );
  });

  testWidgets('bar height is the assessed count, not the library size', (
    tester,
  ) async {
    // A realistic beginner: 8 words looked at, 200 nobody has touched.
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 600,
          child: CapabilityEchoBars(
            channels: [
              channel('listening', acquired: 5, notAcquired: 3, unassessed: 200),
              channel('reading', unassessed: 200),
              channel('speaking', unassessed: 200),
              channel('writing', unassessed: 200),
            ],
          ),
        ),
      ),
    );
    final colors = Theme.of(
      tester.element(find.byType(CapabilityEchoBars)),
    ).colorScheme;

    double heightOf(Color color) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CapabilityEchoBars),
            matching: find.byType(Container),
          ),
        )
        .where((container) => container.color == color)
        .fold(0.0, (sum, c) => sum + (c.constraints?.maxHeight ?? 0));

    // The shared unit is 8, so listening's two assessed segments fill the
    // whole 96pt bar: 60pt acquired above 36pt not-acquired.
    expect(heightOf(colors.primary), closeTo(96 * 5 / 8, 0.01));
    expect(heightOf(colors.secondary), closeTo(96 * 3 / 8, 0.01));
    // Nothing in the graphic is proportional to the 200 unassessed words —
    // only the 1.2pt mirror baselines carry the hairline color.
    final hairlines = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CapabilityEchoBars),
            matching: find.byType(Container),
          ),
        )
        .where((container) => container.color == colors.outlineVariant);
    expect(hairlines, isNotEmpty);
    expect(
      hairlines.map((c) => c.constraints?.maxHeight),
      everyElement(lessThan(2.0)),
    );
  });

  testWidgets('with nothing assessed the bars give way to an honest line', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 600,
          child: CapabilityEchoBars(
            channels: [
              channel('listening', unassessed: 200),
              channel('reading', unassessed: 200),
              channel('speaking', unassessed: 200),
              channel('writing', unassessed: 200),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('echo-bars-empty')), findsOneWidget);
    expect(
      find.text(
        'No assessment data yet. The bars appear once a channel has been '
        'assessed.',
      ),
      findsOneWidget,
    );
    // No empty bars pretending to be a reading.
    expect(find.byKey(const ValueKey('echo-ghost-sound')), findsNothing);
    expect(find.byKey(const ValueKey('echo-ghost-text')), findsNothing);
  });

  testWidgets('the compass center carries the gap count only when real', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(CapabilityPortrait(channels: portraitChannels, gapCount: 96)),
    );
    expect(find.text('96'), findsOneWidget);
    expect(find.text('recognized · not yet produced'), findsOneWidget);

    await tester.pumpWidget(
      localized(CapabilityPortrait(channels: portraitChannels)),
    );
    expect(find.text('recognized · not yet produced'), findsNothing);
  });

  group('compassHitTarget (S2 · #81 three hotspots)', () {
    test('quadrants follow the shared 2x2 semantics', () {
      // 200px compass, center (100,100): up-left is listening, up-right
      // reading, down-right writing, down-left speaking.
      String? at(double dx, double dy) =>
          compassHitTarget(200, Offset(dx, dy), hasGapCenter: true);
      expect(at(60, 20), 'listening');
      expect(at(140, 20), 'reading');
      expect(at(140, 180), 'writing');
      expect(at(60, 180), 'speaking');
    });

    test('the center disc is the gap only when the backend gave a count', () {
      expect(
        compassHitTarget(200, const Offset(100, 100), hasGapCenter: true),
        compassGapTarget,
      );
      expect(
        compassHitTarget(200, const Offset(100, 100), hasGapCenter: false),
        isNull,
      );
    });

    test('taps outside the circle hit nothing', () {
      expect(
        compassHitTarget(200, const Offset(5, 5), hasGapCenter: true),
        isNull,
      );
    });
  });

  testWidgets('the portrait is navigation: quadrant, center and echo bar', (
    tester,
  ) async {
    final channelTaps = <String>[];
    final pairTaps = <String>[];
    var gapTaps = 0;
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 900,
          child: CapabilityPortrait(
            channels: portraitChannels,
            gapCount: 96,
            onChannelTap: channelTaps.add,
            onGapTap: () => gapTaps++,
            onPairTap: pairTaps.add,
          ),
        ),
      ),
    );

    final compass = find.byType(CapabilityCompass);
    final origin = tester.getTopLeft(compass);
    // The listening quadrant (up-left) on a 200px ring.
    await tester.tapAt(origin + const Offset(60, 20));
    await tester.pump();
    expect(channelTaps, ['listening']);

    // The center figure is the one hotspot that may leave the page.
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    expect(gapTaps, 1);

    await tester.tap(find.text('can hear 46 · can say 12'));
    await tester.pump();
    expect(pairTaps, ['sound']);
  });

  testWidgets('the echo bar carries its own affordance instead of a caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 900,
          child: CapabilityPortrait(
            channels: portraitChannels,
            onPairTap: (_) {},
          ),
        ),
      ),
    );
    Iterable<Color?> tints() => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(CapabilityEchoBars),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color);

    expect(tints(), everyElement(isNotNull));
    expect(tints().map((c) => c!.a), everyElement(0.0));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(
      tester.getCenter(find.text('can hear 46 · can say 12')),
    );
    await tester.pumpAndSettle();

    // Exactly the hovered pair lights up — the picture says where the door is.
    expect(tints().where((c) => c!.a > 0), hasLength(1));
  });

  testWidgets('hover on the pair snaps under reduce motion', (tester) async {
    await tester.pumpWidget(
      localized(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 900,
            child: CapabilityPortrait(
              channels: portraitChannels,
              onPairTap: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(CapabilityEchoBars),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((c) => c.duration),
      everyElement(Duration.zero),
    );
  });

  testWidgets('a read-only portrait stays read-only', (tester) async {
    await tester.pumpWidget(
      localized(
        SizedBox(
          width: 900,
          child: CapabilityPortrait(channels: portraitChannels, gapCount: 96),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
