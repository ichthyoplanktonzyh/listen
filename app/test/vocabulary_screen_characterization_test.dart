import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_view_model.dart';
import 'package:llplayer_next/data/repositories/hunting_repository.dart';
import 'package:llplayer_next/data/repositories/lexical_repository.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/common/listen_loading.dart';
import 'package:llplayer_next/widgets/vocabulary/listening_dictionary_entry_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_book_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_gap_panel.dart';

/// Characterization tests for `lib/screens/vocabulary_screen.dart`.
///
/// These pin CURRENT behaviour ahead of the `LexicalRepository` +
/// `VocabularyViewModel` extraction, so that refactor can be shown to preserve
/// what the user sees. Several of them pin behaviour that
/// `design-notes/vocabulary-behavior-contract.md` records as a suspected
/// defect; each such test names the defect in its own comment, and its name
/// states what happens today rather than what ought to.
///
/// Same pattern as the neighbouring vocabulary tests: a fake **transport**
/// feeding a real [LocalApi], never a fake `LocalApi`.

// ── Wire fixtures ──

Map<String, dynamic> entryWire(String id, String form) => {
  'entry': {
    'id': id,
    'normalized_form': form.toLowerCase(),
    'display_form': form,
    'kind': 'word',
    'language': 'en',
  },
  'history': <dynamic>[],
  'occurrences': <dynamic>[],
  'sense_folders': <dynamic>[],
};

Map<String, dynamic> suggestionWire(String entryId, int contexts) => {
  'id': 'suggestion-$entryId',
  'lexical_entry_id': entryId,
  'lexical_display_form': entryId,
  'previous_status': 'known_not_recognized',
  'suggested_status': 'known_recognized',
  'status': 'pending',
  'evidence_context_count': contexts,
  'evidence_ids': <dynamic>[],
  'threshold': 5,
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 1,
};

Map<String, dynamic> productionReviewWire({
  String readiness = 'ready',
  List<Map<String, dynamic>> targets = const [],
}) => {
  'readiness': readiness,
  'document_count': 3,
  'token_count': 120,
  'lemma_count': 60,
  'candidate_count': targets.length,
  'targets': targets,
};

Map<String, dynamic> productionTargetWire(String id, String form) => {
  'lexical_entry_id': id,
  'normalized_key': form.toLowerCase(),
  'display_form': form,
  'frequency_rank': 900,
  'frequency_band': 1,
  'evidence_strength': 3,
  'recency_band': 2,
  'explanation': <dynamic>['frequent in input'],
};

Map<String, dynamic> semanticCapabilityWire({
  String status = 'ready',
  int indexed = 4,
}) => {'status': status, 'indexed_source_count': indexed, 'reason': null};

Map<String, dynamic> semanticHitWire(String text, double similarity) => {
  'source': {
    'kind': 'sentence',
    'source_id': 'source-1',
    'language': 'en',
    'text': text,
    'channel': 'listening',
    'start_ms': 0,
    'end_ms': 500,
  },
  'similarity': similarity,
  'model_fingerprint': 'fp-1',
};

Map<String, dynamic> semanticResultWire(List<Map<String, dynamic>> hits) => {
  'capability': semanticCapabilityWire(),
  'query': 'q',
  'hits': hits,
};

Map<String, dynamic> huntingTargetWire(String entryId, String form) => {
  'id': 'target-$entryId',
  'lexical_entry_id': entryId,
  'source_kind': 'manual',
  'source_id': null,
  'target_snapshot': form,
  'status': 'active',
  'created_at_ms': 1,
  'updated_at_ms': 1,
};

Map<String, dynamic> capabilityProfileWire(String entryId) => {
  'lexical_entry_id': entryId,
  'reading': <String, dynamic>{},
  'listening': <String, dynamic>{},
  'speaking': <String, dynamic>{},
  'writing': <String, dynamic>{},
};

typedef Reply = ({int statusCode, String body});

Reply ok(Object? json) => (statusCode: 200, body: jsonEncode(json));

Reply fail(String body, {int statusCode = 500}) =>
    (statusCode: statusCode, body: body);

/// The backend's JSON error envelope. Only an envelope carries the fields
/// `ApiFailureDisclosure.hasDetail` looks for, so only an envelope earns the
/// SnackBar's "Details" action.
const envelope =
    '{"code":"validation_error","message":"the index is locked",'
    '"correlation_id":"api-853","retryable":false}';

/// One transport with per-path overrides on top of a working baseline.
///
/// The baseline answers everything the workbench touches on mount, so a test
/// only describes the one thing it is bending. [route] may be async, which is
/// how the race tests hold a response open.
class Workbench {
  Workbench({this.words = const [], this.candidates = const [], this.route});

  List<Map<String, dynamic>> words;
  List<Map<String, dynamic>> candidates;

  /// Returns a reply, or `null` to fall through to the baseline.
  FutureOr<Reply?> Function(String method, String path)? route;

  final List<({String method, String path})> calls = [];

  int hits(String prefix) =>
      calls.where((call) => call.path.startsWith(prefix)).length;

  /// Exact-path count. `hits` would also match a sub-resource of the same
  /// entry (`…/entry-1/capability/reading`), which is not the same request.
  int exact(String path) => calls.where((call) => call.path == path).length;

  LocalApi build() => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'tok',
    transport: (method, path, body) async {
      calls.add((method: method, path: path));
      final override = await route?.call(method, path);
      if (override != null) return override;
      if (path.startsWith('/v1/vocabulary?')) return ok(words);
      if (path.startsWith('/v1/hunting/')) return ok(const <dynamic>[]);
      if (path.startsWith('/v1/review/cross-modal?')) return ok(candidates);
      if (path.startsWith('/v1/review/upgrade-suggestions')) {
        return ok(const <dynamic>[]);
      }
      if (path.startsWith('/v1/production-gap/')) {
        return ok(productionReviewWire());
      }
      if (path.startsWith('/v1/production-corpus/search')) {
        return ok(const <dynamic>[]);
      }
      if (path.startsWith('/v1/semantic-embedding/capability')) {
        return ok(semanticCapabilityWire());
      }
      if (path.startsWith('/v1/dictionary')) {
        return ok({'results': <dynamic>[]});
      }
      if (path.startsWith('/v1/lexical-entries/')) {
        final id = path.substring('/v1/lexical-entries/'.length);
        return ok(
          words.firstWhere(
            (word) => (word['entry'] as Map)['id'] == id,
            orElse: () => entryWire(id, id),
          ),
        );
      }
      return fail('unhandled $method $path');
    },
  );
}

Widget host({
  required LocalApi api,
  required WidgetTester tester,
  String? initialEntryId,
}) {
  // Teardown order matters: the screen's dispose fires an unawaited
  // auxiliaryAudio.stop(), so the unmount must run before the controllers are
  // disposed. LIFO teardown gives that if the unmount is registered last.
  final hunting = HuntingController(
    repository: LocalHuntingRepository(() => api),
  );
  addTearDown(hunting.dispose);
  final audio = AuxiliaryAudioController();
  addTearDown(audio.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return MaterialApp(
    locale: const Locale('en'),
    // The waiting mark breathes forever by design; reduce motion halts it so
    // `pumpAndSettle` can reach a resting frame while a source is still down.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: VocabularyScreen(
      viewModel: VocabularyViewModel(
        repository: LexicalRepository(api),
        language: 'en',
      ),
      semanticSearchViewModel: SemanticSearchViewModel(
        LocalSemanticSearchRepository(api),
      ),
      slicePlayer: SlicePlayerController(),
      language: 'en',
      onExport: () async {},
      onImport: () async {},
      huntingController: hunting,
      auxiliaryAudio: audio,
      initialEntryId: initialEntryId,
    ),
  );
}

void setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Everything rendered as text, SnackBars included.
String rendered(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? '')
    .join('\n');

/// Scopes a finder to the open entry detail, so the left column's filter chips
/// (which reuse the same words) cannot answer for it.
Finder inDetail(Finder matching) => find.descendant(
  of: find.byType(ListeningDictionaryEntryView),
  matching: matching,
);

/// Pumps one frame at a time and consumes the tools menu's known right-edge
/// overflow, which is re-thrown on every layout pass the menu takes part in.
/// `pumpAndSettle` would let several pile up into one opaque "multiple
/// exceptions" summary; taking them one per frame keeps each one checkable.
/// The overflow itself is pinned by 'the tools menu clips its own longest
/// label' (suspected defect D6) — here it is only drained.
Future<Object?> pumpDrainingOverflow(WidgetTester tester) async {
  Object? first;
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    final error = tester.takeException();
    if (error == null) continue;
    expect(
      error.toString(),
      contains('overflowed'),
      reason: 'only the known tools-menu overflow may be drained here',
    );
    first ??= error;
  }
  return first;
}

Future<Object?> openTools(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Tools'));
  return pumpDrainingOverflow(tester);
}

Future<void> tapTool(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await pumpDrainingOverflow(tester);
  await tester.pumpAndSettle();
}

void main() {
  // ──────────────────────────────────────────────────────────────────────
  // Failure paths: what the user sees when an endpoint is down.
  // ──────────────────────────────────────────────────────────────────────

  group('failure paths', () {
    testWidgets(
      'a vocabulary list request that fails leaves the list waiting forever',
      (tester) async {
        // SUSPECTED DEFECT D1. `_load()` (vocabulary_screen.dart:202) has no
        // try/catch and no failure state. A 500 escapes as an unhandled async
        // error, `loading` is never cleared, and the column keeps its waiting
        // mark with no sentence, no retry and no honest empty state.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          route: (method, path) => path.startsWith('/v1/vocabulary?')
              ? fail('vocabulary is down')
              : null,
        );
        // The failure escapes as an *unhandled* async error rather than a
        // FlutterError, so it cannot be read back with `takeException`; a
        // guarded zone is the only way to observe it without failing the test.
        final escaped = <Object>[];
        await runZonedGuarded(() async {
          await tester.pumpWidget(host(api: bench.build(), tester: tester));
          await tester.pumpAndSettle();
        }, (error, _) => escaped.add(error));

        expect(
          escaped.single,
          isA<HttpException>(),
          reason: 'the list failure is unhandled, never turned into a state',
        );

        // And nothing on screen moved: still the waiting mark, with no
        // sentence, no retry and no honest empty state.
        expect(find.byType(ListenLoading), findsWidgets);
        expect(find.byType(VocabularyBookView), findsNothing);
        expect(find.text('No words in this book'), findsNothing);
        expect(rendered(tester), isNot(contains('vocabulary is down')));
      },
    );

    testWidgets(
      'tapping a word whose entry request fails does nothing and says nothing',
      (tester) async {
        // SUSPECTED DEFECT D5. `_openEntryById` (vocabulary_screen.dart:234)
        // does not catch `lexicalEntryDetails`. The tap has no visible
        // consequence at all: the gap pane stays, no SnackBar names the
        // failure, and the error escapes as an unhandled async error.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) =>
              path == '/v1/lexical-entries/entry-1' ? fail(envelope) : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        final escaped = <Object>[];
        await runZonedGuarded(() async {
          await tester.tap(find.text('rather'));
          await tester.pumpAndSettle();
        }, (error, _) => escaped.add(error));

        expect(escaped.single, isA<HttpException>());
        // Nothing moved: the right pane is still the gap pane, and no bar
        // names what went wrong.
        expect(find.byType(VocabularyGapPanel), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('dictionary-identity-card')), findsNothing);
      },
    );

    testWidgets(
      'a semantic search that fails is reported as "no matches", not as a '
      'failure',
      (tester) async {
        // SUSPECTED DEFECT D2. `_runSemanticSearch`
        // (vocabulary_screen.dart:426) swallows the error into `hits = const
        // []`, so an unreachable index reads exactly like an index that
        // genuinely holds nothing near the query.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.startsWith('/v1/semantic-search')
              ? fail('index is down')
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'a feeling of dread');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Semantic'));
        await tester.pumpAndSettle();

        expect(bench.hits('/v1/semantic-search'), 1);
        expect(find.text('No semantic matches yet.'), findsOneWidget);
        expect(rendered(tester), isNot(contains('unavailable')));
      },
    );

    testWidgets(
      'a corpus search that fails is reported as an empty library, not as a '
      'failure',
      (tester) async {
        // SUSPECTED DEFECT D3. `_searchHomeCorpus`
        // (vocabulary_screen.dart:674) swallows into `results = const []`, so
        // "your library holds nothing else" and "the corpus index could not
        // be read" render as the same sentence.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          route: (method, path) =>
              path.startsWith('/v1/corpus/search') ? fail('corpus down') : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        // An empty book plus a non-empty query is what opens the fallback.
        await tester.enterText(find.byType(TextField), 'gist');
        await tester.pumpAndSettle();
        expect(find.text('No words in this book'), findsOneWidget);

        await tester.tap(find.text('Search my library'));
        await tester.pumpAndSettle();

        expect(bench.hits('/v1/corpus/search'), 1);
        expect(
          find.text('No other contexts in your library yet'),
          findsOneWidget,
        );
        expect(rendered(tester), isNot(contains('corpus down')));
      },
    );

    testWidgets('a corpus reindex that fails names the failure and keeps the '
        'diagnostics one tap away', (tester) async {
      setSize(tester, const Size(1200, 900));
      final bench = Workbench(
        route: (method, path) =>
            path.startsWith('/v1/corpus/reindex') ? fail(envelope) : null,
      );
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();

      await openTools(tester);
      await tapTool(tester, 'Rebuild library index');

      expect(find.text('Could not rebuild the index'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      // The envelope's own fields never reach the bar itself.
      final text = rendered(tester);
      expect(text, isNot(contains('api-853')));
      expect(text, isNot(contains('the index is locked')));
      expect(text, isNot(contains('127.0.0.1')));
    });

    testWidgets(
      'a failure whose body is not the error envelope offers no details at all',
      (tester) async {
        // Not a bug so much as the honest floor: `ApiFailure.parse` keeps only
        // `raw` for an unrecognised body, and `raw` may never be shown, so the
        // bar has nothing to disclose and drops the action.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          route: (method, path) => path.startsWith('/v1/corpus/reindex')
              ? fail('<html>502 Bad Gateway</html>')
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await openTools(tester);
        await tapTool(tester, 'Rebuild library index');

        expect(find.text('Could not rebuild the index'), findsOneWidget);
        expect(find.text('Details'), findsNothing);
        expect(rendered(tester), isNot(contains('Bad Gateway')));
      },
    );

    testWidgets('a corpus reindex that succeeds reports the track count', (
      tester,
    ) async {
      setSize(tester, const Size(1200, 900));
      final bench = Workbench(
        route: (method, path) => path.startsWith('/v1/corpus/reindex')
            ? ok({'indexed_tracks': 7})
            : null,
      );
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();

      await openTools(tester);
      await tapTool(tester, 'Rebuild library index');

      expect(find.text('Reindexed 7 subtitle tracks'), findsOneWidget);
      // A success bar carries no disclosure action.
      expect(find.text('Details'), findsNothing);
    });

    testWidgets('the tools menu clips its own longest label', (tester) async {
      // SUSPECTED DEFECT D6. `_toolsItem` (vocabulary_screen.dart:1197) is an
      // unconstrained Row inside a PopupMenuItem, whose max width Material
      // fixes at 280pt. "Import vocabulary assets" plus the icon and its gap
      // does not fit, so the row overflows and the label is cut off — on
      // every window size, because the menu width does not depend on one.
      setSize(tester, const Size(1600, 1000));
      final bench = Workbench();
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();

      final overflow = await openTools(tester);
      expect(
        overflow.toString(),
        contains('A RenderFlex overflowed'),
        reason: 'the tools menu still overflows its 280pt menu width',
      );
      // All four items are offered; it is the label that is cut, not the item.
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
    });

    testWidgets(
      'the semantic toggle stays hidden when the capability probe fails',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) =>
              path.startsWith('/v1/semantic-embedding/capability')
              ? fail('model missing', statusCode: 503)
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        // The optional capability degrades to absence: exact search stays
        // fully usable and nothing offers a toggle that could not work.
        expect(find.byType(FilterChip), findsNothing);
        expect(find.byType(VocabularyBookView), findsOneWidget);
        expect(find.text('rather'), findsOneWidget);
      },
    );

    testWidgets(
      'the semantic toggle stays hidden when the model is ready but nothing '
      'is indexed',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) =>
              path.startsWith('/v1/semantic-embedding/capability')
              ? ok(semanticCapabilityWire(indexed: 0))
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        expect(find.byType(FilterChip), findsNothing);
      },
    );

    testWidgets(
      'the gap pane falls back to the plain output review when the semantic '
      'enrichment fails',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          route: (method, path) {
            if (path.startsWith('/v1/production-gap/semantic-enrichment')) {
              return fail('enrichment is down');
            }
            if (path.startsWith('/v1/production-gap/review')) {
              return ok(
                productionReviewWire(
                  targets: [productionTargetWire('entry-9', 'nonetheless')],
                ),
              );
            }
            return null;
          },
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        // Both were tried, and the fallback's rows render.
        expect(bench.hits('/v1/production-gap/semantic-enrichment'), 1);
        expect(bench.hits('/v1/production-gap/review'), 1);
        expect(find.byType(VocabularyGapPanel), findsOneWidget);
        expect(find.text('nonetheless'), findsOneWidget);
        // Degraded silently: no failure notice for a fallback that worked.
        expect(find.text('Could not load output review'), findsNothing);
      },
    );

    testWidgets(
      'the gap pane names the output source only after both of its requests '
      'fail',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          route: (method, path) => path.startsWith('/v1/production-gap/')
              ? fail('output review is down')
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        expect(bench.hits('/v1/production-gap/semantic-enrichment'), 1);
        expect(bench.hits('/v1/production-gap/review'), 1);
        expect(find.text('Could not load output review'), findsOneWidget);
        // The pane's other source is unaffected by this one being down.
        expect(find.text('Cross-channel review is unavailable'), findsNothing);
      },
    );

    testWidgets('an entry whose dictionary lookup fails settles on synthetic '
        'pronunciation instead of waiting', (tester) async {
      setSize(tester, const Size(1200, 900));
      final bench = Workbench(
        words: [entryWire('entry-1', 'rather')],
        route: (method, path) =>
            path.startsWith('/v1/dictionary') ? fail('provider down') : null,
      );
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rather'));
      await tester.pumpAndSettle();

      // The identity card is up, the pronunciation slot resolved to "no
      // provider audio", and the synthetic fallback is offered — the card is
      // never held hostage by a dead provider.
      expect(find.byKey(const Key('dictionary-identity-card')), findsOneWidget);
      expect(find.byTooltip('Play synthetic pronunciation'), findsOneWidget);
      expect(find.byTooltip('Play pronunciation'), findsNothing);
    });

    testWidgets(
      'a capability override that fails names the failure and leaves the open '
      'entry as it was',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) =>
              path.contains('/capability/') ? fail(envelope) : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();
        await tester.tap(find.text('rather'));
        await tester.pumpAndSettle();

        final detailsBefore = bench.exact('/v1/lexical-entries/entry-1');
        final target = inDetail(find.text('Acquired')).first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();

        expect(find.text('Could not update'), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
        // The failed write does not re-read the entry, so the pane keeps the
        // state the user was looking at — every channel still unanswered.
        expect(bench.exact('/v1/lexical-entries/entry-1'), detailsBefore);
        expect(inDetail(find.text('Not yet assessed')), findsNWidgets(4));
      },
    );

    testWidgets(
      'a capability override that succeeds re-reads both the entry and the '
      'list',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.contains('/capability/')
              ? ok(capabilityProfileWire('entry-1'))
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();
        await tester.tap(find.text('rather'));
        await tester.pumpAndSettle();

        final detailsBefore = bench.exact('/v1/lexical-entries/entry-1');
        final listBefore = bench.hits('/v1/vocabulary?');
        final target = inDetail(find.text('Acquired')).first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();

        expect(find.text('Could not update'), findsNothing);
        expect(
          bench.exact('/v1/lexical-entries/entry-1'),
          detailsBefore + 1,
          reason: 'the open entry is re-read after a successful override',
        );
        expect(
          bench.hits('/v1/vocabulary?'),
          listBefore + 1,
          reason:
              'the list re-queries because its filters read the same '
              'channels',
        );
      },
    );

    Future<void> queueOpenEntryForReview(
      WidgetTester tester, {
      required Reply reply,
    }) async {
      setSize(tester, const Size(1200, 900));
      final bench = Workbench(
        words: [entryWire('entry-1', 'rather')],
        route: (method, path) =>
            path.startsWith('/v1/review/items') ? reply : null,
      );
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rather'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to review'));
      await tester.pumpAndSettle();
    }

    testWidgets('queueing the open entry for review confirms it by name', (
      tester,
    ) async {
      await queueOpenEntryForReview(
        tester,
        reply: ok({
          'id': 'item-1',
          'source': {'kind': 'lexical_entry'},
          'anchors': <dynamic>[],
          'prompt_snapshot': 'rather',
          'status': 'active',
          'created_at_ms': 1,
          'updated_at_ms': 1,
        }),
      );

      expect(find.text('Added to sound review'), findsOneWidget);
      expect(find.text('Could not add to review'), findsNothing);
    });

    testWidgets(
      'queueing the open entry for review reports the failure as its own '
      'sentence',
      (tester) async {
        await queueOpenEntryForReview(tester, reply: fail(envelope));

        expect(find.text('Could not add to review'), findsOneWidget);
        expect(find.text('Added to sound review'), findsNothing);
        expect(find.text('Details'), findsOneWidget);
      },
    );

    testWidgets(
      'a word already on the hunting list is refused without a request',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.startsWith('/v1/hunting/targets')
              ? ok([huntingTargetWire('entry-1', 'rather')])
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();
        await tester.tap(find.text('rather'));
        await tester.pumpAndSettle();

        final before = bench.calls.length;
        // Already on the list: the control is disabled and its tooltip is the
        // reason, so the guard never has to fire.
        expect(find.byTooltip('Already in Hunting List'), findsOneWidget);
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Already in Hunting List'),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull);
        expect(bench.calls.length, before);
      },
    );

    testWidgets(
      'a capability-proposal lookup with nothing to propose says so instead '
      'of showing an empty dialog',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.startsWith('/v1/projections/entries/')
              ? ok({'proposals': <dynamic>[]})
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();
        await tester.tap(find.text('rather'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Capability proposals'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(
            'There is not enough qualified evidence for a proposal. '
            'The channel remains unassessed.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // Async race guards.
  // ──────────────────────────────────────────────────────────────────────

  group('async race guards', () {
    testWidgets(
      'a decoration belonging to the previous entry cannot paint onto the '
      'entry opened after it',
      (tester) async {
        // The `detailRequest` sequence guard (vocabulary_screen.dart:123, 235,
        // 244, 255) exists for exactly this: entry A's suggestions resolving
        // after the user moved to entry B must be dropped, not painted onto B.
        setSize(tester, const Size(1200, 900));
        final staleSuggestions = Completer<void>();
        addTearDown(() {
          if (!staleSuggestions.isCompleted) staleSuggestions.complete();
        });
        final bench = Workbench(
          words: [entryWire('entry-a', 'alpha'), entryWire('entry-b', 'bravo')],
          route: (method, path) async {
            if (!path.startsWith('/v1/review/upgrade-suggestions')) return null;
            if (path.contains('lexical_entry_id=entry-a')) {
              await staleSuggestions.future;
              return ok([suggestionWire('entry-a', 5)]);
            }
            return ok([suggestionWire('entry-b', 9)]);
          },
        );

        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.tap(find.text('alpha'));
        await tester.pumpAndSettle();
        expect(staleSuggestions.isCompleted, isFalse);

        await tester.tap(find.text('bravo'));
        await tester.pumpAndSettle();
        expect(find.textContaining('9 contexts'), findsOneWidget);

        // Entry A's suggestion lands late — and is dropped.
        staleSuggestions.complete();
        await tester.pumpAndSettle();
        expect(find.textContaining('5 contexts'), findsNothing);
        expect(find.textContaining('9 contexts'), findsOneWidget);
      },
    );

    testWidgets('a stale vocabulary list response overwrites the fresher one', (
      tester,
    ) async {
      // SUSPECTED DEFECT D4. The detail path has a sequence guard; the list
      // path (`_load`, vocabulary_screen.dart:202) has none. Two searches in
      // flight publish in arrival order, so a slower older query wins and
      // the column shows results for a query the user already replaced.
      setSize(tester, const Size(1200, 900));
      final slowFirstQuery = Completer<void>();
      addTearDown(() {
        if (!slowFirstQuery.isCompleted) slowFirstQuery.complete();
      });
      final bench = Workbench(
        route: (method, path) async {
          if (!path.startsWith('/v1/vocabulary?')) return null;
          if (path.contains('search=gi&')) {
            await slowFirstQuery.future;
            return ok([entryWire('entry-stale', 'STALE')]);
          }
          if (path.contains('search=gist&')) {
            return ok([entryWire('entry-fresh', 'FRESH')]);
          }
          return ok(const <dynamic>[]);
        },
      );

      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'gi');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'gist');
      await tester.pumpAndSettle();

      // The fresher query has landed and is on screen.
      expect(find.text('FRESH'), findsOneWidget);

      // The older query now lands — and wins.
      slowFirstQuery.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('STALE'),
        findsOneWidget,
        reason: 'today the older response overwrites the newer list',
      );
      expect(find.text('FRESH'), findsNothing);
    });

    testWidgets(
      'the previously opened entry stays on screen while the next one loads',
      (tester) async {
        // `_openEntryById` clears the three decorations before awaiting but
        // deliberately leaves `details` alone (vocabulary_screen.dart:222-237),
        // so the pane never blanks between two words.
        setSize(tester, const Size(1200, 900));
        final slowEntry = Completer<void>();
        addTearDown(() {
          if (!slowEntry.isCompleted) slowEntry.complete();
        });
        final bench = Workbench(
          words: [entryWire('entry-a', 'alpha'), entryWire('entry-b', 'bravo')],
          route: (method, path) async {
            if (path != '/v1/lexical-entries/entry-b') return null;
            await slowEntry.future;
            return null;
          },
        );

        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();
        await tester.tap(find.text('alpha'));
        await tester.pumpAndSettle();
        expect(inDetail(find.text('alpha')), findsOneWidget);

        await tester.tap(find.text('bravo'));
        await tester.pumpAndSettle();

        // Still alpha's card — the pane holds the old word rather than
        // blanking — and the decoration slots are back in their waiting state.
        expect(slowEntry.isCompleted, isFalse);
        expect(inDetail(find.text('alpha')), findsOneWidget);
        expect(
          find.byKey(const Key('dictionary-suggestions-loading')),
          findsOneWidget,
        );

        slowEntry.complete();
        await tester.pumpAndSettle();
        expect(inDetail(find.text('bravo')), findsOneWidget);
        expect(inDetail(find.text('alpha')), findsNothing);
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transitions across the three right-pane surfaces.
  // ──────────────────────────────────────────────────────────────────────

  group('pane transitions', () {
    Workbench withProductionTarget(String id, String form) => Workbench(
      words: [entryWire(id, form)],
      route: (method, path) {
        if (path.startsWith('/v1/production-gap/semantic-enrichment')) {
          return fail('no enrichment');
        }
        if (path.startsWith('/v1/production-gap/review')) {
          return ok(
            productionReviewWire(targets: [productionTargetWire(id, form)]),
          );
        }
        return null;
      },
    );

    testWidgets(
      'two-pane: opening an entry from the gap pane swaps the gap pane for '
      'the detail and keeps the list',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = withProductionTarget('entry-1', 'rather');
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        expect(find.byType(VocabularyGapPanel), findsOneWidget);
        await tester.tap(find.text('View & practice'));
        await tester.pumpAndSettle();

        expect(find.byType(VocabularyGapPanel), findsNothing);
        expect(
          find.byKey(const Key('dictionary-identity-card')),
          findsOneWidget,
        );
        expect(find.byType(VocabularyBookView), findsOneWidget);
        // Two-pane never grows a back button.
        expect(find.byType(BackButton), findsNothing);
      },
    );

    testWidgets(
      'two-pane: the Gaps row reads as selected exactly while no entry is open',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(words: [entryWire('entry-1', 'rather')]);
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        ListTile gapsRow() =>
            tester.widget<ListTile>(find.widgetWithText(ListTile, 'Gaps'));
        expect(gapsRow().selected, isTrue);

        await tester.tap(find.text('rather'));
        await tester.pumpAndSettle();
        expect(gapsRow().selected, isFalse);

        await tester.tap(find.text('Gaps'));
        await tester.pumpAndSettle();
        expect(gapsRow().selected, isTrue);
        expect(find.byType(VocabularyGapPanel), findsOneWidget);
      },
    );

    testWidgets(
      'narrow: closing an entry opened from the gap pane returns to the gap '
      'pane, not the list',
      (tester) async {
        // `_closeDetails` (vocabulary_screen.dart:313) clears `details` only;
        // `narrowGapOpen` survives, so back unwinds one surface at a time.
        setSize(tester, const Size(700, 900));
        final bench = withProductionTarget('entry-1', 'rather');
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.tap(find.text('View gaps →'));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyGapPanel), findsOneWidget);

        await tester.tap(find.text('View & practice'));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyGapPanel), findsNothing);
        expect(
          find.byKey(const Key('dictionary-identity-card')),
          findsOneWidget,
        );

        // First back: detail → gap pane.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyGapPanel), findsOneWidget);
        expect(find.byType(VocabularyBookView), findsNothing);

        // Second back: gap pane → list.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyBookView), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
      },
    );

    testWidgets(
      'the narrow gap strip counts both sources once they have loaded',
      (tester) async {
        setSize(tester, const Size(700, 900));
        final bench = Workbench(
          route: (method, path) {
            if (path.startsWith('/v1/production-gap/semantic-enrichment')) {
              return fail('no enrichment');
            }
            if (path.startsWith('/v1/production-gap/review')) {
              return ok(
                productionReviewWire(
                  targets: [
                    productionTargetWire('entry-1', 'rather'),
                    productionTargetWire('entry-2', 'nonetheless'),
                  ],
                ),
              );
            }
            return null;
          },
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        expect(
          find.text('Cross-channel candidates 0 · output gap 2'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'switching to semantic mode with an empty query shows no matches '
      'without querying the index',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(words: [entryWire('entry-1', 'rather')]);
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilterChip, 'Semantic'));
        await tester.pumpAndSettle();

        expect(bench.hits('/v1/semantic-search'), 0);
        expect(find.text('No semantic matches yet.'), findsOneWidget);
        expect(find.byType(VocabularyBookView), findsNothing);
        // The box relabels itself for the mode it is now in.
        expect(find.text('Describe the idea you want to find'), findsOneWidget);
      },
    );

    testWidgets(
      'semantic hits replace the word list and turning the mode off restores '
      'it',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.startsWith('/v1/semantic-search')
              ? ok(
                  semanticResultWire([
                    semanticHitWire('a nearby sentence', 0.8123),
                  ]),
                )
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'dread');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Semantic'));
        await tester.pumpAndSettle();

        expect(find.text('a nearby sentence'), findsOneWidget);
        // Similarity is shown to three decimals, not collapsed into a verdict.
        expect(find.text('0.812'), findsOneWidget);
        expect(find.byType(VocabularyBookView), findsNothing);

        final listBefore = bench.hits('/v1/vocabulary?');
        await tester.tap(find.widgetWithText(FilterChip, 'Semantic'));
        await tester.pumpAndSettle();

        expect(find.byType(VocabularyBookView), findsOneWidget);
        expect(find.text('a nearby sentence'), findsNothing);
        expect(
          bench.hits('/v1/vocabulary?'),
          listBefore + 1,
          reason: 'leaving semantic mode re-runs the exact query',
        );
      },
    );

    testWidgets(
      'typing while semantic mode is on queries neither index until submit',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(
          words: [entryWire('entry-1', 'rather')],
          route: (method, path) => path.startsWith('/v1/semantic-search')
              ? ok(semanticResultWire(const []))
              : null,
        );
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilterChip, 'Semantic'));
        await tester.pumpAndSettle();
        final listBefore = bench.hits('/v1/vocabulary?');
        final semanticBefore = bench.hits('/v1/semantic-search');

        await tester.enterText(find.byType(TextField), 'dread');
        await tester.pumpAndSettle();
        expect(bench.hits('/v1/vocabulary?'), listBefore);
        expect(bench.hits('/v1/semantic-search'), semanticBefore);

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(bench.hits('/v1/semantic-search'), semanticBefore + 1);
      },
    );

    testWidgets(
      'the gap pane gives one honest empty state when neither source has '
      'anything',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        // Baseline: no candidates, a ready output review with no targets.
        final bench = Workbench(words: [entryWire('entry-1', 'rather')]);
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "No cross-channel gaps yet. Words you understand but haven't "
            'produced will surface here first.',
          ),
          findsOneWidget,
        );
        // One state, not two per-source notices stacked together.
        expect(find.text('Where output lags input'), findsNothing);
      },
    );

    testWidgets('the right pane waits until both gap sources have answered', (
      tester,
    ) async {
      setSize(tester, const Size(1200, 900));
      final slowCandidates = Completer<void>();
      addTearDown(() {
        if (!slowCandidates.isCompleted) slowCandidates.complete();
      });
      final bench = Workbench(
        words: [entryWire('entry-1', 'rather')],
        route: (method, path) async {
          if (!path.startsWith('/v1/review/cross-modal?')) return null;
          await slowCandidates.future;
          return null;
        },
      );
      await tester.pumpWidget(host(api: bench.build(), tester: tester));
      await tester.pumpAndSettle();

      // The list column is already usable while the gap pane waits: the two
      // sides of the workbench load on separate clocks.
      expect(find.byType(VocabularyBookView), findsOneWidget);
      expect(find.text('rather'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VocabularyGapPanel),
          matching: find.byType(ListenLoading),
        ),
        findsOneWidget,
      );

      slowCandidates.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(VocabularyGapPanel),
          matching: find.byType(ListenLoading),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'picking an assessment re-queries with both the channel and the '
      'assessment',
      (tester) async {
        // The channel alone never filters the query (already pinned in
        // vocabulary_workbench_test); this is the other half — once an
        // assessment is chosen, both axes go to the backend together.
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(words: [entryWire('entry-1', 'rather')]);
        await tester.pumpWidget(host(api: bench.build(), tester: tester));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ChoiceChip, 'Speaking'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Not acquired'));
        await tester.pumpAndSettle();

        final last = bench.calls
            .lastWhere((call) => call.path.startsWith('/v1/vocabulary?'))
            .path;
        expect(last, contains('capability=speaking'));
        expect(last, contains('assessment=not_acquired'));

        // Going back to "All" drops the capability filter again.
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await tester.pumpAndSettle();
        final afterAll = bench.calls
            .lastWhere((call) => call.path.startsWith('/v1/vocabulary?'))
            .path;
        expect(afterAll, isNot(contains('capability=')));
        expect(afterAll, isNot(contains('assessment=')));
      },
    );

    testWidgets(
      'an entry named at construction opens straight into the detail pane',
      (tester) async {
        setSize(tester, const Size(1200, 900));
        final bench = Workbench(words: [entryWire('entry-1', 'rather')]);
        await tester.pumpWidget(
          host(api: bench.build(), tester: tester, initialEntryId: 'entry-1'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('dictionary-identity-card')),
          findsOneWidget,
        );
        expect(find.byType(VocabularyGapPanel), findsNothing);
        expect(find.byType(VocabularyBookView), findsOneWidget);
      },
    );
  });
}
