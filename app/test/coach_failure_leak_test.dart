import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/coach/coach_dashboard_screen.dart';

/// The coach page's evidence drill-down, driven by a request that really
/// fails.
///
/// `_EvidenceFeed` held `String? error` filled with `'$error'` and the panel
/// rendered it as its only line. So opening a metric while the sidecar was
/// unhappy printed the whole `HttpException` — envelope, `correlation_id`,
/// loopback port, internal route — in the place a learner's own snapshots go.
/// That is the same substitution #61 found in the conversation transcript, one
/// screen over.
///
/// The dashboard itself loads fine here on purpose: the failure has to be the
/// *evidence page*, because that is the one the leak was on. A scenario that
/// failed the dashboard request instead would pass this file's blocklist
/// without ever reaching the code that leaked.
///
/// The failure is a real non-2xx through the real transport, served from
/// `127.0.0.1:62645` — the address the field report used — so the assertion
/// covers `describeApiFailure` and the exception's own `toString`, which is
/// what appends `uri = …`.
void main() {
  /// The body the field actually reported, verbatim.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Everything the exchange carried that a drill-down is not a place for.
  const leaks = [
    'HttpException',
    'Exception',
    'correlation_id',
    'api-853',
    '127.0.0.1',
    '62645',
    'validation_error',
    'uri =',
    'retryable',
    '/v1/',
  ];

  Map<String, dynamic> channel(
    String name, {
    List<Map<String, dynamic>> metrics = const [],
  }) => {
    'channel': name,
    'status': 'available',
    'metrics': metrics,
    'effective_assessments': {
      'acquired': 12,
      'not_acquired': 4,
      'unassessed': 20,
    },
  };

  Map<String, dynamic> dashboard() => {
    'period_start_ms': 0,
    'period_end_ms': 1,
    'generated_at_ms': DateTime.now().millisecondsSinceEpoch - 180000,
    'channels': [
      channel(
        'listening',
        metrics: [
          {
            'key': 'practice_attempts',
            'value': 4,
            'source': 'practice_attempts',
            'authority_layer': 'attempt',
          },
        ],
      ),
      channel('speaking'),
      channel('reading'),
      channel('writing'),
    ],
    'suggestions': const <dynamic>[],
    'starter_checklist': const <dynamic>[],
    'materials': const <dynamic>[],
    'features': const <dynamic>[],
  };

  /// The dashboard reads; the evidence page is what fails.
  LocalApi api() => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async {
      if (path.startsWith('/v1/coach/evidence')) {
        return (statusCode: 503, body: envelope);
      }
      if (path.startsWith('/v1/coach/dashboard')) {
        return (statusCode: 200, body: jsonEncode(dashboard()));
      }
      throw StateError('$method $path was not expected');
    },
  );

  Future<void> pump(WidgetTester tester) async {
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
          api: api(),
          language: 'en',
          onNavigate: (destination, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String rendered(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .followedBy(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data ?? ''),
      )
      .join('\n');

  testWidgets('a failed evidence page names the failure instead of quoting '
      'it', (tester) async {
    await pump(tester);

    // The dashboard is up, so the metric row is there to open.
    expect(find.text('Active practice attempts'), findsOneWidget);
    await tester.tap(find.text('Active practice attempts'));
    await tester.pumpAndSettle();

    final text = rendered(tester);
    for (final leak in leaks) {
      expect(
        text,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; the evidence drill-down is not a '
            'place to print it. The page said:\n$text',
      );
    }
    expect(find.text('This evidence could not be loaded.'), findsOneWidget);
  });

  testWidgets('the reference id is behind the disclosure, the raw body is '
      'nowhere', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Active practice attempts'));
    await tester.pumpAndSettle();

    // Collapsed by default: the backend's operator English is not on screen
    // until it is asked for.
    expect(find.text('recording metadata must not be empty'), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Reference api-853'), findsOneWidget);
    expect(find.text('recording metadata must not be empty'), findsOneWidget);

    // Expanded, and `ApiFailure.raw` is still not among the fields.
    final text = rendered(tester);
    for (final leak in [
      'HttpException',
      '127.0.0.1',
      '62645',
      'uri =',
      'correlation_id',
      'retryable',
      '/v1/',
    ]) {
      expect(
        text,
        isNot(contains(leak)),
        reason: '"$leak" lives in ApiFailure.raw, which is never rendered.',
      );
    }
  });
}
