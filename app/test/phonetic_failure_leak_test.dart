import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/phonetic_analysis_ui.dart';
import 'package:llplayer_next/data/repositories/phonetic_analysis_repository.dart';
import 'package:llplayer_next/services/api_service.dart';

/// The analysis centre, driven by requests that really fail.
///
/// It held one `String? error` and rendered it as the whole panel body, so a
/// failed load printed an internal error code, a `correlation_id`, the
/// sidecar's loopback port and an internal route where a sentence belonged.
///
/// Two sites filled that field and only one was visible to the source gate:
/// `_refresh` catches into a variable named `value` and called
/// `value.toString()`, which is not a shape `error_leak_discipline_test`
/// recognises. Both are covered here, and the uncaught one is the load path —
/// the one a user hits first.
///
/// Both scenarios fail a **real** request through the **real** transport:
/// `LocalApi` throws `HttpException(body, uri: …)` on a non-2xx and the fake
/// is served from `127.0.0.1:62645`, the address the field report used. So
/// the assertion covers `describeApiFailure` and the exception's own
/// `toString` — which is what appends `uri = …`.
void main() {
  /// The body the field actually reported, verbatim.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Everything the exchange carried that a screen is not a place for.
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

  String rendered(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .join('\n');

  void expectNoLeak(WidgetTester tester, {required String from}) {
    final text = rendered(tester);
    for (final leak in leaks) {
      expect(
        text,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; $from is not a place to print it. '
            'The screen said:\n$text',
      );
    }
  }

  LocalApi api({
    ({int statusCode, String body})? Function(String method, String path)? fail,
    Map<String, String> ok = const {},
  }) => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async {
      final failure = fail?.call(method, path);
      if (failure != null) return failure;
      for (final entry in ok.entries) {
        if (path.contains(entry.key)) {
          return (statusCode: 200, body: entry.value);
        }
      }
      return (statusCode: 200, body: '[]');
    },
  );

  Future<void> pump(WidgetTester tester, LocalApi service) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PhoneticAnalysisCenter(
          repository: LocalPhoneticAnalysisRepository(service),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the centre failing to load names the failure', (tester) async {
    // GET /v1/phonetic-analysis/providers → 500 with the envelope. This is
    // the site the source gate could not see.
    await pump(
      tester,
      api(
        fail: (method, path) => path.contains('/phonetic-analysis/providers')
            ? (statusCode: 500, body: envelope)
            : null,
      ),
    );

    expectNoLeak(tester, from: 'the analysis centre');
    expect(find.text('Could not load the analysis centre'), findsOneWidget);
  });

  testWidgets('a model install the backend rejects names the failure', (
    tester,
  ) async {
    // The three lists read fine, so the models tab is on screen with one
    // downloadable model; then POST /models/install → 409 with the envelope.
    await pump(
      tester,
      api(
        fail: (method, path) => path.contains('/models/install')
            ? (statusCode: 409, body: envelope)
            : null,
        ok: {
          '/phonetic-analysis/models':
              '[{"id":"en_us_arpa","provider_id":"local",'
              '"display_name":"English (US)",'
              '"state":"downloadable","size_bytes":1000,'
              '"installed_bytes":0,"license":"CC-BY","revision":"1",'
              '"training_data_provenance":"public",'
              '"application_verified":true,"distribution_allowed":true}]',
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    await tester.pump();

    expectNoLeak(tester, from: 'the analysis centre');
    expect(find.text('Could not install this model'), findsOneWidget);
  });

  testWidgets('the reference id is reachable, and the raw body is not', (
    tester,
  ) async {
    await pump(
      tester,
      api(
        fail: (method, path) => path.contains('/phonetic-analysis/providers')
            ? (statusCode: 500, body: envelope)
            : null,
      ),
    );

    // The disclosure is collapsed, so the operator message is not on screen
    // until it is asked for.
    expect(find.text('recording metadata must not be empty'), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    // What a bug report can be matched against a backend log line.
    expect(find.text('Reference api-853'), findsOneWidget);
    // And the loopback port, the internal route and the envelope's own field
    // names still are not anywhere — `ApiFailure.raw` is not rendered even
    // expanded.
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .followedBy(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((widget) => widget.data ?? ''),
        )
        .join('\n');
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
