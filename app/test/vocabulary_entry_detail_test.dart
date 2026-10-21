import 'dart:async';
import 'dart:convert';

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
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/listening_dictionary_entry_view.dart';

/// S4 (#82): the entry detail is an identity card plus four anchored sections; pronunciation can load separately.

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

const _occurrence = LexicalOccurrence(
  id: 'occurrence-1',
  mediaTitleSnapshot: 'Personal media',
  mediaFingerprintSnapshot: 'fp-1',
  sentenceTextSnapshot: 'I got the gist of it.',
  startMsSnapshot: 1200,
  endMsSnapshot: 2400,
  encounterCount: 1,
  originalForm: 'gist',
  mediaId: 'media-1',
  sentenceId: 'sentence-1',
);

/// The detail with every listening section wired, so all four anchors exist.
Widget _fullDetail() => ListeningDictionaryEntryView(
  details: const LexicalEntryDetails(
    entry: LexicalEntry(
      id: 'gist',
      normalizedForm: 'gist',
      displayForm: 'gist',
      kind: 'word',
      language: 'en',
    ),
    occurrences: [_occurrence],
  ),
  onPlay: (_) {},
  onMark: (_, _) async => true,
  onLoadEvidenceHistory: ({String? capability, int offset = 0}) async =>
      const [],
  onSaveContent: (_, _) async {},
  onCreateSenseFolder: (_, _, _, _) async {},
);

Map<String, dynamic> _entryWire(String id, String form) => {
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

void main() {
  testWidgets('the detail offers four section anchors, not tabs', (
    tester,
  ) async {
    await tester.pumpWidget(_localized(_fullDetail()));
    await tester.pump();

    for (final anchor in const [
      ('evidence', 'Evidence'),
      // The clips anchor carries its inventory count ("Clips 1").
      ('clips', 'Clips 1'),
      ('senses', 'Meanings'),
      ('notes', 'Notes'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(const Key('entry-section-anchors')),
          matching: find.byKey(Key('entry-section-anchor-${anchor.$1}')),
        ),
        findsOneWidget,
        reason: '${anchor.$1} should be one of the four section anchors',
      );
      expect(
        find.descendant(
          of: find.byKey(Key('entry-section-anchor-${anchor.$1}')),
          matching: find.text(anchor.$2),
        ),
        findsOneWidget,
      );
    }
    // Anchors, not tabs: no tab bar claims only one section exists, and every
    // section stays built and co-visible in one scroll view.
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Your source clips'), findsOneWidget);
    expect(find.text('Meaning folders'), findsOneWidget);
    expect(find.text('My definition & note'), findsOneWidget);
  });

  testWidgets('tapping an anchor scrolls that section to the reading line', (
    tester,
  ) async {
    await tester.pumpWidget(_localized(_fullDetail()));
    await tester.pump();

    final notes = find.text('My definition & note');
    final viewportHeight = tester.getSize(find.byType(Scaffold)).height;
    // The last section starts below the fold.
    expect(tester.getTopLeft(notes).dy, greaterThan(viewportHeight));

    await tester.tap(find.byKey(const Key('entry-section-anchor-notes')));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(notes).dy, lessThan(viewportHeight));
    // The other sections did not disappear — scrolling back is all it takes.
    expect(find.text('Your source clips'), findsOneWidget);
  });

  testWidgets('a section keeps its own state across a parent rebuild', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localized(
        ListeningDictionaryEntryView(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'gist',
              normalizedForm: 'gist',
              displayForm: 'gist',
              kind: 'word',
              language: 'en',
            ),
            occurrences: [_occurrence],
          ),
          onPlay: (_) {},
          onMark: (_, _) async => true,
          onLoadEvidenceHistory: ({String? capability, int offset = 0}) async =>
              const [],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Evidence & history'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('No recorded learning evidence here yet.'),
      findsOneWidget,
    );

    // Revealing a clip is a setState on the host, which rebuilds every
    // section. Anchor keys are stable, so the expanded evidence section is not
    // remounted and does not silently collapse.
    await tester.tap(find.byTooltip('Reveal sentence text').first);
    await tester.pump();
    expect(
      find.text('No recorded learning evidence here yet.'),
      findsOneWidget,
    );
  });

  testWidgets('the identity card does not wait for pronunciation lookup', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pronunciationGate = Completer<void>();
    final words = [_entryWire('entry-gist', 'gist')];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.startsWith('/v1/dictionary')) {
          await pronunciationGate.future;
          return (statusCode: 200, body: jsonEncode({'results': <dynamic>[]}));
        }
        if (path.startsWith('/v1/vocabulary?')) {
          return (statusCode: 200, body: jsonEncode(words));
        }
        if (path.startsWith('/v1/lexical-entries/')) {
          return (statusCode: 200, body: jsonEncode(words.first));
        }
        return (statusCode: 500, body: 'unhandled');
      },
    );

    final hunting = HuntingController();
    addTearDown(hunting.dispose);
    final audio = AuxiliaryAudioController();
    addTearDown(audio.dispose);
    addTearDown(() async {
      if (!pronunciationGate.isCompleted) pronunciationGate.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('gist').first);
    await tester.pumpAndSettle();

    expect(pronunciationGate.isCompleted, isFalse);
    expect(find.byKey(const Key('dictionary-identity-card')), findsOneWidget);
    expect(find.byKey(const Key('entry-section-anchors')), findsOneWidget);
    expect(find.text('My definition & note'), findsOneWidget);
  });
}
