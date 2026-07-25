import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_book_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_gap_panel.dart';

// ── Wire fixtures ──

Map<String, dynamic> _entry(String id, String form) => {
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

Map<String, dynamic> _candidate(String id, String form) => {
  'lexical_entry_id': id,
  'display_form': form,
  'reading': 'acquired',
  'listening': 'acquired',
  'speaking': 'not_acquired',
  'writing': 'unassessed',
  'review_kind': 'cross_modal',
  'reason': 'Heard often, not yet produced.',
  'source': {
    'observation_id': 'obs-1',
    'source_ref': null,
    'task_type': 'listening',
    'outcome': 'heard',
    'occurred_at_ms': 0,
    'snapshot': 'a durable sentence snapshot',
  },
};

/// A transport that answers the workbench's core endpoints. [vocabularyHits]
/// counts `/v1/vocabulary` requests so a test can prove the channel picker does
/// not re-query. Everything not listed degrades to a 500 (best-effort sources).
class _Fixture {
  int vocabularyHits = 0;

  LocalApi build({
    List<Map<String, dynamic>> words = const [],
    List<Map<String, dynamic>> candidates = const [],
  }) => LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      if (method == 'GET' && path.startsWith('/v1/vocabulary?')) {
        vocabularyHits++;
        return (statusCode: 200, body: jsonEncode(words));
      }
      if (method == 'GET' && path.startsWith('/v1/hunting/targets?')) {
        return (statusCode: 200, body: '[]');
      }
      if (method == 'GET' && path.startsWith('/v1/hunting/candidates?')) {
        return (statusCode: 200, body: '[]');
      }
      if (method == 'GET' && path.startsWith('/v1/review/cross-modal?')) {
        return (statusCode: 200, body: jsonEncode(candidates));
      }
      if (method == 'GET' && path.startsWith('/v1/lexical-entries/')) {
        final id = path.substring('/v1/lexical-entries/'.length);
        final match = words.firstWhere(
          (w) => (w['entry'] as Map)['id'] == id,
          orElse: () => _entry(id, id),
        );
        return (statusCode: 200, body: jsonEncode(match));
      }
      // Production gap, semantic capability, dictionary, corpus: optional
      // decorations — degrade to a notice, never fail the workbench.
      return (statusCode: 500, body: 'unhandled');
    },
  );
}

Widget _host({
  required LocalApi api,
  required WidgetTester tester,
  bool openCrossModalReviewOnStart = false,
}) {
  // The screen's dispose fires an unawaited auxiliaryAudio.stop(); if the
  // controller were disposed first, that stop would notify a dead notifier.
  // Register the disposes first and the unmount+settle last, so LIFO teardown
  // unmounts (running stop to completion) before the controllers dispose.
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
      api: api,
      language: 'en',
      onExport: () async {},
      onImport: () async {},
      huntingController: hunting,
      auxiliaryAudio: audio,
      openCrossModalReviewOnStart: openCrossModalReviewOnStart,
    ),
  );
}

void main() {
  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('two-pane: gap pane is the default right pane', (tester) async {
    await setSize(tester, const Size(1200, 900));
    final fixture = _Fixture();
    final api = fixture.build(
      words: [_entry('entry-endedup', 'ended up')],
      candidates: [_candidate('entry-rather', 'rather')],
    );
    await tester.pumpWidget(_host(api: api, tester: tester));
    await tester.pumpAndSettle();

    // Right pane defaults to the gap instrument room (gap-(c) first).
    expect(find.byType(VocabularyGapPanel), findsOneWidget);
    expect(find.text('Where output lags input'), findsOneWidget);
    // The candidate carries the entry-scale ring, not raw channel strings.
    expect(find.text('rather'), findsOneWidget);
    expect(find.text('View entry'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VocabularyGapPanel),
        matching: find.byType(CapabilityRing),
      ),
      findsWidgets,
    );
    // The list column stays beside the pane.
    expect(find.byType(VocabularyBookView), findsOneWidget);
    expect(find.text('ended up'), findsOneWidget);
    // The app bar never grows a back button in the two-pane form.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets(
    'two-pane: opening an entry keeps the list and the app bar constant',
    (tester) async {
      await setSize(tester, const Size(1200, 900));
      final fixture = _Fixture();
      final api = fixture.build(
        words: [_entry('entry-endedup', 'ended up')],
        candidates: [_candidate('entry-rather', 'rather')],
      );
      await tester.pumpWidget(_host(api: api, tester: tester));
      await tester.pumpAndSettle();

      final titleBefore = tester.widget<Text>(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Listening Dictionary'),
        ),
      );
      expect(titleBefore.data, 'Listening Dictionary');

      await tester.tap(find.text('ended up'));
      await tester.pumpAndSettle();

      // Right pane switched to detail; list did not disappear.
      expect(find.byType(VocabularyBookView), findsOneWidget);
      expect(find.byType(VocabularyGapPanel), findsNothing);
      // App bar title unchanged (never transforms) — no back button either.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Listening Dictionary'),
        ),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsNothing);
      // Detail action moved off the app bar and onto the detail pane.
      expect(find.text('Add to review'), findsOneWidget);
    },
  );

  testWidgets(
    'channel chip always responds but never re-queries under the All filter',
    (tester) async {
      // Narrow so the four capability chips share one full-width row and are
      // all laid out (the 340px two-pane list scrolls them lazily).
      await setSize(tester, const Size(700, 900));
      final fixture = _Fixture();
      final api = fixture.build(
        words: [_entry('entry-endedup', 'ended up')],
        candidates: const [],
      );
      await tester.pumpWidget(_host(api: api, tester: tester));
      await tester.pumpAndSettle();

      final hitsAfterLoad = fixture.vocabularyHits;
      expect(hitsAfterLoad, greaterThan(0));

      final speakingChip = find.widgetWithText(ChoiceChip, 'Speaking');
      expect(tester.widget<ChoiceChip>(speakingChip).selected, isFalse);

      await tester.tap(speakingChip);
      await tester.pumpAndSettle();

      // Visible response: the chip is now selected (the ring re-lenses).
      expect(tester.widget<ChoiceChip>(speakingChip).selected, isTrue);
      // Query semantics unchanged: no capability filter is applied while the
      // assessment is "All", so no new /v1/vocabulary request fires.
      expect(fixture.vocabularyHits, hitsAfterLoad);
    },
  );

  testWidgets('narrow window degrades to a single column', (tester) async {
    await setSize(tester, const Size(700, 900));
    final fixture = _Fixture();
    final api = fixture.build(
      words: [_entry('entry-endedup', 'ended up')],
      candidates: [_candidate('entry-rather', 'rather')],
    );
    await tester.pumpWidget(_host(api: api, tester: tester));
    await tester.pumpAndSettle();

    // Single column: the list shows, the gap pane is not co-visible.
    expect(find.byType(VocabularyBookView), findsOneWidget);
    expect(find.byType(VocabularyGapPanel), findsNothing);
    expect(find.text('ended up'), findsOneWidget);

    // The narrow gap strip brings the gap pane forward; the back button
    // returns to the list.
    expect(find.text('View gaps →'), findsOneWidget);
    await tester.tap(find.text('View gaps →'));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyGapPanel), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyBookView), findsOneWidget);
    expect(find.byType(VocabularyGapPanel), findsNothing);
  });

  testWidgets('cross_modal_review lands on the gap pane, not a dialog', (
    tester,
  ) async {
    await setSize(tester, const Size(1200, 900));
    final fixture = _Fixture();
    final api = fixture.build(
      words: [_entry('entry-endedup', 'ended up')],
      candidates: [_candidate('entry-rather', 'rather')],
    );
    await tester.pumpWidget(
      _host(api: api, tester: tester, openCrossModalReviewOnStart: true),
    );
    await tester.pumpAndSettle();

    // The hand-off lands on the gap pane in place — no modal dialog.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(VocabularyGapPanel), findsOneWidget);
    expect(find.text('Where output lags input'), findsOneWidget);
    expect(find.text('rather'), findsOneWidget);
  });
}
