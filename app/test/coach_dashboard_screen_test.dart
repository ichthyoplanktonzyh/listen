import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/coach/coach_dashboard_screen.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';

// S2 · #81: the coach page's portrait is its navigation, evidence drills down
// in place, and the starter list states what listen has not seen instead of
// pretending to be a to-do list. Presentation only — every number here still
// comes from the backend envelope untouched.

Map<String, dynamic> _channel(
  String channel, {
  List<Map<String, dynamic>> metrics = const [],
  int acquired = 0,
  int notAcquired = 0,
  int unassessed = 0,
}) => {
  'channel': channel,
  'status': 'available',
  'metrics': metrics,
  'effective_assessments': {
    'acquired': acquired,
    'not_acquired': notAcquired,
    'unassessed': unassessed,
  },
};

Map<String, dynamic> _metric(String key, int value, String source) => {
  'key': key,
  'value': value,
  'source': source,
  'authority_layer': 'attempt',
};

Map<String, dynamic> _suggestion({
  required String id,
  required String kind,
  required String titleKey,
  required String destination,
  required int evidenceCount,
  String evidenceSource = 'review_schedules',
}) => {
  'id': id,
  'kind': kind,
  'title_key': titleKey,
  'reason_key': 'coachSuggestionReviewReason',
  'destination': {'kind': destination, 'language': 'en'},
  'evidence_source': evidenceSource,
  'evidence_count': evidenceCount,
};

// A real evidence id is a UUID; it must never reach the screen.
const _evidenceId = '2b0c8b1e-6d1f-4d2f-9b5a-6a2f0c1d8e77';

Map<String, dynamic> _evidence(String snapshot, {bool available = true}) => {
  'id': _evidenceId,
  'occurred_at_ms':
      DateTime.now().millisecondsSinceEpoch -
      const Duration(days: 3).inMilliseconds,
  'result': 'correct',
  'source_kind': 'practice_attempt',
  'snapshot': snapshot,
  'source_available': available,
  'unavailable_reason': available ? null : 'source_media_unavailable',
};

Map<String, dynamic> _dashboard({
  List<Map<String, dynamic>> suggestions = const [],
  List<String> starter = const [],
  List<Map<String, dynamic>> materials = const [],
  List<Map<String, dynamic>> features = const [],
}) => {
  'period_start_ms': 0,
  'period_end_ms': 1,
  'generated_at_ms': DateTime.now().millisecondsSinceEpoch - 180000,
  'channels': [
    _channel(
      'listening',
      metrics: [_metric('practice_attempts', 4, 'practice_attempts')],
      acquired: 46,
      notAcquired: 18,
      unassessed: 96,
    ),
    _channel(
      'speaking',
      metrics: [
        _metric('speaking_completed_attempts', 2, 'semantic_task_attempts'),
      ],
      acquired: 12,
      notAcquired: 30,
      unassessed: 118,
    ),
    _channel('reading', acquired: 88, unassessed: 62),
    _channel('writing', acquired: 8, unassessed: 130),
  ],
  'suggestions': suggestions,
  'starter_checklist': starter,
  'materials': materials,
  'features': features,
};

LocalApi _api({
  required Map<String, dynamic> dashboard,
  List<Map<String, dynamic>> evidence = const [],
  List<String>? requestLog,
}) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    requestLog?.add('$method $path');
    if (path.startsWith('/v1/coach/evidence')) {
      final uri = Uri.parse('http://test$path');
      final limit = int.parse(uri.queryParameters['limit']!);
      final offset = int.parse(uri.queryParameters['offset']!);
      final page = evidence.skip(offset).take(limit).toList();
      return (statusCode: 200, body: jsonEncode(page));
    }
    if (path.startsWith('/v1/coach/dashboard')) {
      return (statusCode: 200, body: jsonEncode(dashboard));
    }
    throw StateError('$method $path was not expected');
  },
);

Future<void> _pump(
  WidgetTester tester,
  LocalApi api, {
  List<String>? navigations,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachDashboardScreen(
        api: api,
        language: 'en',
        onNavigate: (destination, _) async =>
            navigations?.add(destination.kind),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Cards the page marked as focused carry a colored border.
Finder _focusedCard(Color color) => find.byWidgetPredicate((widget) {
  if (widget is! Card) return false;
  final shape = widget.shape;
  return shape is RoundedRectangleBorder && shape.side.color == color;
});

void main() {
  testWidgets('the portrait navigates: quadrant and echo bar stay on page', (
    tester,
  ) async {
    final navigations = <String>[];
    await _pump(
      tester,
      _api(dashboard: _dashboard()),
      navigations: navigations,
    );

    final origin = tester.getTopLeft(find.byType(CapabilityCompass));
    // The speaking quadrant is down-left on the 200px ring.
    await tester.tapAt(origin + const Offset(60, 180));
    await tester.pumpAndSettle();

    final colors = Theme.of(
      tester.element(find.byType(CapabilityCompass)),
    ).colorScheme;
    expect(
      find.descendant(
        of: _focusedCard(colors.primary),
        matching: find.text('Speaking'),
      ),
      findsOneWidget,
    );
    // A quadrant never leaves the page.
    expect(navigations, isEmpty);

    // The echo bar opens the pair and says where the gap comes from.
    await tester.tap(find.text('can hear 46 · can say 12'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The unlit part of this channel’s echo is where the gap comes from.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _focusedCard(colors.secondary),
        matching: find.text('Speaking'),
      ),
      findsOneWidget,
    );
    expect(navigations, isEmpty);
  });

  testWidgets(
    'the gap figure is the one hotspot that leaves, to the gap pane',
    (tester) async {
      final navigations = <String>[];
      await _pump(
        tester,
        _api(
          dashboard: _dashboard(
            suggestions: [
              _suggestion(
                id: 'cross-modal-review',
                kind: 'cross_modal_review',
                titleKey: 'coachSuggestionCrossModal',
                destination: 'cross_modal_review',
                evidenceCount: 7,
              ),
            ],
          ),
        ),
        navigations: navigations,
      );

      // The center figure only exists because the backend joined it.
      expect(find.text('7'), findsOneWidget);
      final origin = tester.getTopLeft(find.byType(CapabilityCompass));
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(navigations, ['cross_modal_review']);
    },
  );

  testWidgets('a suggestion is one verb-first sentence, a count and a door', (
    tester,
  ) async {
    final navigations = <String>[];
    await _pump(
      tester,
      _api(
        dashboard: _dashboard(
          suggestions: [
            _suggestion(
              id: 'due-review',
              kind: 'due_review',
              titleKey: 'coachSuggestionReview',
              destination: 'review_queue',
              evidenceCount: 3,
            ),
          ],
        ),
      ),
      navigations: navigations,
    );

    expect(find.text('Review due audio cards'), findsOneWidget);
    expect(find.text('3 cards are due'), findsOneWidget);
    // The old reason · count · source concatenation is gone, raw table names
    // with it.
    expect(find.textContaining('review_schedules'), findsNothing);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(navigations, ['review_queue']);
  });

  testWidgets('evidence drills down in place, with no UUID and no dialog', (
    tester,
  ) async {
    final requests = <String>[];
    await _pump(
      tester,
      _api(
        dashboard: _dashboard(),
        evidence: [
          for (var i = 0; i < 6; i++) _evidence('ended up taking the job $i'),
          _evidence('the gist of it', available: false),
        ],
        requestLog: requests,
      ),
    );

    // Metrics are rows in the channel's table, not 210px cards in a card.
    expect(find.text('Active practice attempts'), findsOneWidget);
    expect(find.text('from cloze and dictation attempts'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('Active practice attempts'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('ended up taking the job 0'), findsOneWidget);
    expect(find.textContaining(_evidenceId), findsNothing);
    // Relative time plus the source in words, never a raw source_kind.
    expect(find.textContaining('3 days ago · from a cloze'), findsWidgets);

    // The first page is a handful; "More" pages the same endpoint.
    expect(find.text('ended up taking the job 4'), findsOneWidget);
    expect(find.text('ended up taking the job 5'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('ended up taking the job 5'), findsOneWidget);
    expect(find.textContaining('the original media is gone'), findsOneWidget);
    expect(find.text('That is every fact in this period.'), findsOneWidget);
    expect(
      requests
          .where((request) => request.contains('/v1/coach/evidence'))
          .length,
      2,
    );

    // Tapping again folds it away instead of stacking another surface.
    await tester.tap(find.text('Active practice attempts'));
    await tester.pumpAndSettle();
    expect(find.text('ended up taking the job 0'), findsNothing);
  });

  testWidgets('the starter list states what listen has not seen', (
    tester,
  ) async {
    final navigations = <String>[];
    await _pump(
      tester,
      _api(
        dashboard: _dashboard(
          starter: const ['complete_extensive_listening', 'review_due_items'],
        ),
      ),
      navigations: navigations,
    );

    // K1: no radio icon can be mistaken for something the user may tick.
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.text(
        'These are states listen has not observed yet — not a list you tick.',
      ),
      findsOneWidget,
    );
    expect(find.text('listen has not seen this yet'), findsNWidgets(2));

    // Each state carries its own door.
    expect(find.text('Go listen'), findsOneWidget);
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(navigations, ['review_queue']);
  });

  testWidgets('chapters run portrait → next steps → evidence → shelf → tools', (
    tester,
  ) async {
    await _pump(
      tester,
      _api(
        dashboard: _dashboard(
          suggestions: [
            _suggestion(
              id: 'due-review',
              kind: 'due_review',
              titleKey: 'coachSuggestionReview',
              destination: 'review_queue',
              evidenceCount: 3,
            ),
          ],
          starter: const ['review_due_items'],
          materials: [
            {
              'media_id': 'media-1',
              'title': 'Real interview',
              'report_count': 3,
              'first_report': 'unclear',
              'latest_report': 'understood_all',
              'reports_understood_all': 1,
              'reports_got_the_gist': 1,
              'reports_unclear': 1,
              'practice_attempts': 0,
              'practice_correct': 0,
              'triage_intent': null,
              'recommended_intent': null,
              'graduation_candidate': false,
            },
          ],
          features: [
            {
              'feature': 'llm_feedback',
              'status': 'not_configured',
              'reason': 'no_provider',
            },
          ],
        ),
      ),
    );

    double top(Finder finder) => tester.getTopLeft(finder).dy;

    expect(
      top(find.text('Your language portrait')),
      lessThan(top(find.text('Suggested next steps'))),
    );
    expect(
      top(find.text('Suggested next steps')),
      lessThan(top(find.text('Build your first evidence'))),
    );
    expect(
      top(find.text('Build your first evidence')),
      lessThan(top(find.text('Channel evidence'))),
    );
    expect(
      top(find.text('Channel evidence')),
      lessThan(top(find.text('Material progress'))),
    );
    // The feature rows are status, so they sit at the tools/about level.
    expect(
      top(find.text('Material progress')),
      lessThan(top(find.text('Tools and status'))),
    );
    expect(
      find.text('LLM feedback · Not configured; core Coach remains available'),
      findsOneWidget,
    );
    // The trajectory reads in words, with the report count spelled out.
    expect(find.text('unclear → understood all · 3 reports'), findsOneWidget);
  });
}
