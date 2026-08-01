import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/settings/llm_provider_settings.dart';
import 'package:llplayer_next/widgets/settings/realtime_provider_settings.dart';
import 'package:llplayer_next/widgets/settings/syntax_capability_settings.dart';

/// The three settings panels, each driven by a request that really fails.
///
/// All three held one `String? _error` filled with `'$error'` and rendered it
/// verbatim — a red `Text` for the two provider panels, a `ListenErrorNotice`
/// for the syntax one. So a settings page could print an internal error code,
/// a `correlation_id`, the sidecar's loopback port and an internal route.
///
/// Every scenario below fails a **real** request through the **real**
/// transport: `LocalApi` throws `HttpException(body, uri: …)` on a non-2xx and
/// the fake is served from `127.0.0.1:62645`, the address the field report
/// used. So the assertion covers `describeApiFailure` and the exception's own
/// `toString` — which is what appends `uri = …` — and not a string this test
/// wrote itself.
void main() {
  /// The body the field actually reported, verbatim.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Everything the exchange carried that a settings panel is not a place for.
  const leaks = [
    'HttpException',
    'Exception',
    'correlation_id',
    'api-853',
    '127.0.0.1',
    '62645',
    'validation_error',
    'recording metadata must not be empty',
    'uri =',
    'retryable',
    '/v1/',
  ];

  /// Everything the panel is currently rendering, in one string.
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
            'The panel said:\n$text',
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
      return (statusCode: 200, body: '{}');
    },
  );

  Future<void> pump(WidgetTester tester, Widget panel) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the AI provider list failing to load names the failure', (
    tester,
  ) async {
    // GET /v1/llm/providers → 500 with the envelope.
    await pump(
      tester,
      LlmProviderSettings(
        repository: LocalLlmProviderRepository(
          api(
            fail: (method, path) => path.contains('/v1/llm/providers')
                ? (statusCode: 500, body: envelope)
                : null,
          ),
        ),
      ),
    );

    expectNoLeak(tester, from: 'the AI provider panel');
    expect(find.text('Could not load the AI providers'), findsOneWidget);
  });

  testWidgets('the speech provider list failing to load names the failure', (
    tester,
  ) async {
    // GET /v1/realtime/providers → 503 with the envelope.
    await pump(
      tester,
      RealtimeProviderSettings(
        repository: LocalRealtimeProviderRepository(
          api(
            fail: (method, path) => path.contains('/v1/realtime/providers')
                ? (statusCode: 503, body: envelope)
                : null,
          ),
        ),
      ),
    );

    expectNoLeak(tester, from: 'the speech provider panel');
    expect(find.text('Could not load the speech providers'), findsOneWidget);
  });

  testWidgets('a sentence-analysis action the backend rejects names the '
      'failure instead of quoting it', (tester) async {
    // The capability reads fine, so the panel is on screen; then
    // POST /v1/syntax/capability/install → 409 with the envelope.
    await pump(
      tester,
      SyntaxCapabilitySettings(
        repository: LocalSyntaxCapabilityRepository(
          api(
            fail: (method, path) => path.contains('/capability/install')
                ? (statusCode: 409, body: envelope)
                : null,
            ok: {
              '/v1/syntax/capability':
                  '{"status":"not_installed","enabled":false,'
                  '"runtime_version":"3.7","model_version":"en_core_web_sm"}',
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expectNoLeak(tester, from: 'the sentence-analysis panel');
    expect(find.text('That sentence-analysis action failed'), findsOneWidget);
  });
}
