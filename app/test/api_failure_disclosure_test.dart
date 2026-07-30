import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/widgets/common/api_failure_disclosure.dart';

/// The disclosure is the answer to "then where does the exception go?".
///
/// #62's fix has two halves and this is the second one, so it needs its own
/// proof: the reference id a bug report needs must be reachable, and
/// `ApiFailure.raw` must not be — not collapsed, and not expanded either.
void main() {
  /// The exchange the field actually reported, as `describeApiFailure` parses
  /// it: the body is the envelope, and `raw` additionally carries the URI the
  /// `HttpException`'s own `toString` appended.
  final failure = ApiFailure.parse(
    '{"code":"validation_error","message":"recording metadata must not be '
    'empty","correlation_id":"api-853","retryable":false}',
  );

  /// `ApiFailure.parse` keeps the body as `raw`; production also appends the
  /// URI, so pin the worse of the two shapes.
  const rawWithUri =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}, uri = '
      'http://127.0.0.1:62645/v1/recordings';

  /// Everything `raw` carries that no surface may render, expanded or not.
  const neverRendered = [
    'HttpException',
    '127.0.0.1',
    '62645',
    'uri =',
    'correlation_id',
    'retryable',
    '/v1/',
  ];

  void expectNoRawAnywhere(WidgetTester tester) {
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .followedBy(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((widget) => widget.data ?? ''),
        )
        .join('\n');
    for (final leak in neverRendered) {
      expect(
        rendered,
        isNot(contains(leak)),
        reason: '"$leak" lives in ApiFailure.raw, which is never rendered.',
      );
    }
  }

  Widget host(Widget child) => MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the notice shows the sentence and keeps the detail collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ApiFailureNotice(
          message: 'Could not load the AI providers',
          failure: failure,
        ),
      ),
    );

    expect(find.text('Could not load the AI providers'), findsOneWidget);
    // The backend's operator English is not on screen until asked for.
    expect(find.text('recording metadata must not be empty'), findsNothing);
    expect(find.text('Details'), findsOneWidget);
    expectNoRawAnywhere(tester);
  });

  testWidgets('expanding it reveals the reference id, and still not raw', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ApiFailureNotice(
          message: 'Could not load the AI providers',
          failure: failure,
        ),
      ),
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    // What a bug report can actually be matched against a backend log line.
    expect(find.text('Reference api-853'), findsOneWidget);
    expect(find.text('recording metadata must not be empty'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    // And the loopback port / internal route still are not anywhere.
    expectNoRawAnywhere(tester);
    // Still carried, just not spoken.
    expect(failure.correlationId, 'api-853');
  });

  testWidgets('a failure with nothing to disclose grows no affordance', (
    tester,
  ) async {
    // A local tool threw: `describeApiFailure` fills only `raw`, so there is
    // no reference id and no operator message. An empty "Details" panel would
    // be worse than none.
    final opaque = ApiFailure(raw: rawWithUri);
    expect(ApiFailureDisclosure.hasDetail(opaque), isFalse);

    await tester.pumpWidget(
      host(ApiFailureNotice(message: 'Download failed', failure: opaque)),
    );

    expect(find.text('Download failed'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    expectNoRawAnywhere(tester);
  });

  testWidgets('the modal form shows the same two fields and no more', (
    tester,
  ) async {
    await tester.pumpWidget(host(ApiFailureDetailsButton(failure: failure)));

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Failure details'), findsOneWidget);
    expect(find.text('Reference api-853'), findsOneWidget);
    expectNoRawAnywhere(tester);
  });
}
