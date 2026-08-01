import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_view_model.dart';
import 'package:llplayer_next/data/repositories/lexical_repository.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/semantic_search_dialog.dart';

/// The vocabulary workbench, driven by requests that really fail.
///
/// This screen had the most sites of any file in #62's table, in three shapes:
///
/// - the gap pane's two sources stored `'$error'` in a `String?` that
///   `VocabularyGapPanel` substituted into its own `{error}` placeholder;
/// - eleven `_snack(l.text('…').replaceAll('{error}', '$error'))` calls, which
///   put the whole exception in a SnackBar;
/// - `SemanticSearchDialog` kept `error = '$failure'` at seven sites and passed
///   it into `semanticSearchFailure`'s `{error}` placeholder.
///
/// Every scenario fails a **real** request through the **real** transport,
/// served from `127.0.0.1:62645` — the address the field report used — so the
/// assertions cover `describeApiFailure` and the exception's own `toString`,
/// which is what appends `uri = …`.
/// One word in the book, enough to open an entry and reach its actions.
const _word =
    '{"entry":{"id":"entry-1","normalized_form":"rather","display_form":'
    '"rather","kind":"word","language":"en"},"history":[],"occurrences":[],'
    '"sense_folders":[]}';

void main() {
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

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

  /// Everything on screen, including SnackBar content.
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
            'On screen:\n$text',
      );
    }
  }

  LocalApi api(
    ({int statusCode, String body})? Function(String method, String path) route,
  ) => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async =>
        route(method, path) ?? (statusCode: 200, body: '{}'),
  );

  Widget host(WidgetTester tester, LocalApi service) {
    final hunting = HuntingController();
    addTearDown(hunting.dispose);
    final audio = AuxiliaryAudioController();
    addTearDown(audio.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    return MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: VocabularyScreen(
        viewModel: VocabularyViewModel(
          repository: LexicalRepository(service),
          language: 'en',
        ),
        semanticSearchViewModel: SemanticSearchViewModel(
          LocalSemanticSearchRepository(service),
        ),
        slicePlayer: SlicePlayerController(),
        language: 'en',
        onExport: () async {},
        onImport: () async {},
        huntingController: hunting,
        auxiliaryAudio: audio,
      ),
    );
  }

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the gap pane names each source that could not be read', (
    tester,
  ) async {
    await setSize(tester, const Size(1200, 900));
    // Both of the pane's sources 500 with the envelope:
    // GET /v1/review/cross-modal and the production-gap pair.
    await tester.pumpWidget(
      host(
        tester,
        api((method, path) {
          if (path.startsWith('/v1/vocabulary')) {
            return (statusCode: 200, body: '[]');
          }
          if (path.contains('/cross-modal') ||
              path.contains('production-gap') ||
              path.contains('/semantic/production-gap')) {
            return (statusCode: 500, body: envelope);
          }
          if (path.startsWith('/v1/hunting/')) {
            return (statusCode: 200, body: '[]');
          }
          return null;
        }),
      ),
    );
    await tester.pumpAndSettle();

    expectNoLeak(tester, from: 'the gap pane');
    expect(find.text('Cross-channel review is unavailable'), findsOneWidget);
    expect(find.text('Could not load output review'), findsOneWidget);
  });

  testWidgets('a capability-proposal lookup that fails says so in the '
      'SnackBar', (tester) async {
    await setSize(tester, const Size(1200, 900));
    // One word in the book, opened; then
    // GET /v1/projections/entries/entry-1 → 500 with the envelope.
    await tester.pumpWidget(
      host(
        tester,
        api((method, path) {
          if (path.startsWith('/v1/projections/')) {
            return (statusCode: 500, body: envelope);
          }
          if (path.startsWith('/v1/vocabulary')) {
            return (statusCode: 200, body: '[$_word]');
          }
          if (path.startsWith('/v1/lexical-entries/')) {
            return (statusCode: 200, body: _word);
          }
          if (path.startsWith('/v1/hunting/') ||
              path.contains('/cross-modal')) {
            return (statusCode: 200, body: '[]');
          }
          return null;
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('rather'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Capability proposals'));
    await tester.pumpAndSettle();

    expectNoLeak(tester, from: 'a SnackBar');
    expect(find.text('Capability proposals are unavailable'), findsOneWidget);
  });

  testWidgets('the meaning-search dialog names what failed', (tester) async {
    // GET /v1/semantic-embedding/capability → 503 with the envelope.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SemanticSearchDialog(
            viewModel: SemanticSearchViewModel(
              LocalSemanticSearchRepository(
                api(
                  (method, path) => path.contains('/semantic-embedding/')
                      ? (statusCode: 503, body: envelope)
                      : null,
                ),
              ),
            ),
            language: 'en',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectNoLeak(tester, from: 'the meaning-search dialog');
    expect(
      find.text('Could not read the meaning-search state'),
      findsOneWidget,
    );
  });
}
