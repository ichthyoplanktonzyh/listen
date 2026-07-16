import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/production_corpus.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/panels/word_learning_panel.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_book_view.dart';
import 'package:llplayer_next/widgets/vocabulary/listening_dictionary_entry_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_details_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_transfer_actions.dart';
import 'package:llplayer_next/utils/subtitle_position.dart';
import 'package:llplayer_next/utils/subtitle_style.dart';
import 'package:llplayer_next/utils/word_list_parser.dart';

LexicalEntryDetails vocabularyDetails({
  required String displayForm,
  String kind = 'word',
  List<LexicalOccurrence> occurrences = const [],
  LexicalCapabilityProfile? capabilityProfile,
}) => LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'entry-$displayForm',
    normalizedForm: displayForm.toLowerCase(),
    displayForm: displayForm,
    kind: kind,
    language: 'en',
  ),
  occurrences: occurrences,
  capabilityProfile: capabilityProfile,
);

Widget localized(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
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
  test('responsive subtitle sizing limits long compact subtitles', () {
    final normal = responsiveSubtitleSize(
      width: 1200,
      scale: 1,
      preset: 'learning',
      textLength: 30,
    );
    final longCompact = responsiveSubtitleSize(
      width: 1200,
      scale: 1,
      preset: 'compact',
      textLength: 160,
    );
    expect(normal, lessThanOrEqualTo(34));
    expect(longCompact, lessThan(normal));
  });

  test('subtitle dragging uses normalized viewport coordinates and clamps', () {
    final moved = moveSubtitlePosition(
      current: const Offset(0.5, 0.8),
      delta: const Offset(100, -100),
      viewport: const Size(1000, 500),
    );
    expect(moved.dx, closeTo(0.6, 0.0001));
    expect(moved.dy, closeTo(0.6, 0.0001));
    expect(
      moveSubtitlePosition(
        current: const Offset(0.95, 0.05),
        delta: const Offset(100, -100),
        viewport: const Size(1000, 500),
      ),
      const Offset(1, 0),
    );
  });

  test('external word list parser handles TXT and CSV status values', () {
    expect(parseExternalWordList('hello\n\nworld\n', csv: false), [
      {'word': 'hello', 'status': null},
      {'word': 'world', 'status': null},
    ]);
    expect(
      parseExternalWordList(
        'word,status\nhello,known_recognized\nworld,invalid\n',
        csv: true,
      ),
      [
        {'word': 'hello', 'status': 'known_recognized'},
        {'word': 'world', 'status': null},
      ],
    );
  });

  testWidgets('vocabulary book shows durable source and unavailable state', (
    tester,
  ) async {
    LexicalEntryDetails? selected;
    final word = vocabularyDetails(
      displayForm: 'Hello',
      occurrences: const [
        LexicalOccurrence(
          mediaTitleSnapshot: 'Example',
          mediaFingerprintSnapshot: 'sha256:example',
          sentenceTextSnapshot: 'Hello from a durable snapshot.',
          startMsSnapshot: 0,
          endMsSnapshot: 1000,
          encounterCount: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyBookView(
            words: [word],
            onWord: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Hello from a durable snapshot.'), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    await tester.tap(find.text('Hello'));
    expect(selected, same(word));
  });

  testWidgets('vocabulary book shows a four-channel snapshot and phrase badge', (
    tester,
  ) async {
    final word = vocabularyDetails(
      displayForm: 'take care of',
      kind: 'phrase',
      capabilityProfile: LexicalCapabilityProfile.fromJson({
        'lexical_entry_id': 'e1',
        'reading': <String, dynamic>{},
        'listening': <String, dynamic>{},
        'speaking': <String, dynamic>{},
        'writing': <String, dynamic>{},
      }),
    );
    await tester.pumpWidget(
      localized(VocabularyBookView(words: [word], onWord: (_) {})),
    );
    expect(find.text('take care of'), findsOneWidget);
    // Phrases are surfaced with a kind badge (the book is no longer word-only).
    expect(find.text('Phrase'), findsOneWidget);
    // One icon per capability channel, always shown even when unassessed.
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.hearing_outlined), findsOneWidget);
    expect(find.byIcon(Icons.record_voice_over_outlined), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('empty vocabulary book has an explicit state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VocabularyBookView(words: const [], onWord: (_) {}),
      ),
    );
    expect(find.text('No words in this book'), findsOneWidget);
  });

  testWidgets(
    'listening dictionary hides text until requested and plays clips',
    (tester) async {
      LexicalOccurrence? played;
      const occurrence = LexicalOccurrence(
        mediaTitleSnapshot: 'Personal media',
        mediaFingerprintSnapshot: 'fp-1',
        sentenceTextSnapshot: 'I heard hello in this source sentence.',
        startMsSnapshot: 1200,
        endMsSnapshot: 2400,
        encounterCount: 1,
        originalForm: 'hello',
        mediaId: 'media-1',
        sentenceId: 'sentence-1',
      );
      await tester.pumpWidget(
        localized(
          ListeningDictionaryEntryView(
            details: const LexicalEntryDetails(
              entry: LexicalEntry(
                id: 'hello',
                normalizedForm: 'hello',
                displayForm: 'hello',
                kind: 'word',
                language: 'en',
              ),
              occurrences: [occurrence],
            ),
            onPlay: (value) => played = value,
            onMark: (_, _) async => true,
          ),
        ),
      );

      expect(find.text('Reveal sentence text'), findsOneWidget);
      expect(find.text('I heard hello in this source sentence.'), findsNothing);
      await tester.tap(find.byTooltip('Play source clip'));
      expect(played, same(occurrence));
      await tester.tap(find.text('Reveal sentence text'));
      await tester.pump();
      // Marking remains an action on the active inline player; this rail test
      // fixes the old vertical-card contract to reveal + playback only.
    },
  );

  testWidgets(
    'sense folders stay optional and create through the detail view',
    (tester) async {
      String? createdLabel;
      const assigned = LexicalOccurrence(
        id: 'occurrence-1',
        mediaTitleSnapshot: 'Personal media',
        mediaFingerprintSnapshot: 'fp-1',
        sentenceTextSnapshot: 'She runs a business.',
        startMsSnapshot: 1200,
        endMsSnapshot: 2400,
        encounterCount: 1,
        originalForm: 'runs',
      );
      const unassigned = LexicalOccurrence(
        id: 'occurrence-2',
        mediaTitleSnapshot: 'Personal media',
        mediaFingerprintSnapshot: 'fp-2',
        sentenceTextSnapshot: 'She runs every morning.',
        startMsSnapshot: 2500,
        endMsSnapshot: 3600,
        encounterCount: 1,
        originalForm: 'runs',
      );
      await tester.pumpWidget(
        localized(
          ListeningDictionaryEntryView(
            details: const LexicalEntryDetails(
              entry: LexicalEntry(
                id: 'run',
                normalizedForm: 'run',
                displayForm: 'run',
                kind: 'word',
                language: 'en',
              ),
              occurrences: [assigned, unassigned],
              senseFolders: [
                LexicalSenseFolderDetails(
                  folder: LexicalSenseFolder(
                    id: 'sense-1',
                    lexicalEntryId: 'run',
                    label: 'operate a business',
                    createdAtMs: 1,
                    updatedAtMs: 1,
                  ),
                  occurrences: [assigned],
                ),
              ],
            ),
            onPlay: (_) {},
            onMark: (_, _) async => true,
            onCreateSenseFolder: (label, _, _, _) async => createdLabel = label,
          ),
        ),
      );

      expect(find.text('Meaning folders'), findsOneWidget);
      expect(find.text('Unassigned clips'), findsOneWidget);
      await tester.tap(find.byTooltip('Add meaning folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'physical running');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(createdLabel, 'physical running');
    },
  );

  testWidgets(
    'listening dictionary searches the library, dedupes saved clips, and collects',
    (tester) async {
      const savedOccurrence = LexicalOccurrence(
        mediaTitleSnapshot: 'Personal media',
        mediaFingerprintSnapshot: 'fp-1',
        sentenceTextSnapshot: 'hello already saved here.',
        startMsSnapshot: 0,
        endMsSnapshot: 900,
        encounterCount: 1,
        originalForm: 'hello',
        mediaId: 'media-1',
        sentenceId: 'sentence-saved',
      );
      const duplicate = CorpusOccurrence(
        id: 'corpus-dup',
        language: 'en',
        kind: 'lexical',
        displayText: 'hello',
        startMs: 0,
        endMs: 900,
        sourceSnapshot: 'hello already saved here.',
        mediaId: 'media-1',
        sentenceId: 'sentence-saved',
      );
      const fresh = CorpusOccurrence(
        id: 'corpus-fresh',
        language: 'en',
        kind: 'chunk',
        displayText: 'hello there',
        startMs: 1200,
        endMs: 1800,
        sourceSnapshot: 'hello there from a chunk.',
        mediaId: 'media-2',
        sentenceId: 'sentence-fresh',
      );
      CorpusOccurrence? collected;
      await tester.pumpWidget(
        localized(
          ListeningDictionaryEntryView(
            details: const LexicalEntryDetails(
              entry: LexicalEntry(
                id: 'hello',
                normalizedForm: 'hello',
                displayForm: 'hello',
                kind: 'word',
                language: 'en',
              ),
              occurrences: [savedOccurrence],
            ),
            onPlay: (_) {},
            onMark: (_, _) async => true,
            onSearchLibrary: () async => const [duplicate, fresh],
            onPlayCorpus: (_) {},
            onCollectCorpus: (occurrence) async {
              collected = occurrence;
              return true;
            },
          ),
        ),
      );

      await tester.tap(find.text('Search my library'));
      await tester.pump();
      await tester.pump();
      // The saved sentence is filtered out; only the fresh chunk remains.
      expect(find.text('hello there from a chunk.'), findsOneWidget);
      expect(find.text('hello already saved here.'), findsNothing);
      expect(find.textContaining('Chunk'), findsOneWidget);

      await tester.tap(find.byTooltip('Save as source clip'));
      await tester.pump();
      expect(collected, same(fresh));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    },
  );

  test('clip speech rate estimates wpm and refuses degenerate input', () {
    expect(clipSpeechRateWpm('one two three four', 0, 2000), 120);
    expect(clipSpeechRateWpm('   ', 0, 2000), isNull);
    expect(clipSpeechRateWpm('word', 0, 100), isNull);
  });

  testWidgets('listening dictionary sorts clips by estimated speech rate', (
    tester,
  ) async {
    const fast = LexicalOccurrence(
      mediaTitleSnapshot: 'Fast clip',
      mediaFingerprintSnapshot: 'fp-fast',
      sentenceTextSnapshot: 'one two three four five six',
      startMsSnapshot: 0,
      endMsSnapshot: 1000,
      encounterCount: 1,
      sentenceId: 's-fast',
    );
    const slow = LexicalOccurrence(
      mediaTitleSnapshot: 'Slow clip',
      mediaFingerprintSnapshot: 'fp-slow',
      sentenceTextSnapshot: 'one two',
      startMsSnapshot: 0,
      endMsSnapshot: 2000,
      encounterCount: 1,
      sentenceId: 's-slow',
    );
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
            occurrences: [fast, slow],
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
        ),
      ),
    );

    // The first PageView card follows stored order, then rebinds after sort.
    expect(find.textContaining('≈360 wpm'), findsOneWidget);

    await tester.tap(find.text('By speech rate'));
    await tester.pump();
    expect(find.textContaining('≈60 wpm'), findsOneWidget);
  });

  testWidgets('upgrade suggestion banner resolves through its callbacks', (
    tester,
  ) async {
    const suggestion = UpgradeSuggestion(
      id: 'suggestion-1',
      lexicalEntryId: 'hello',
      lexicalDisplayForm: 'hello',
      previousStatus: 'known_not_recognized',
      suggestedStatus: 'known_recognized',
      status: 'pending',
      evidenceContextCount: 5,
      evidenceIds: [],
      threshold: 5,
      evidenceClass: 'heuristic_proxy',
      createdAtMs: 1,
    );
    UpgradeSuggestion? confirmed;
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
          suggestions: const [suggestion],
          onConfirmSuggestion: (value) async => confirmed = value,
          onRejectSuggestion: (_) async {},
        ),
      ),
    );
    expect(find.textContaining('5 contexts'), findsOneWidget);
    await tester.tap(find.text('Confirm: can hear it'));
    expect(confirmed, same(suggestion));
  });

  testWidgets('capability chips edit the channel override in place', (
    tester,
  ) async {
    final records = <(String, String?)>[];
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: LexicalEntryDetails(
            entry: const LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
            capabilityProfile: LexicalCapabilityProfile.fromJson(const {
              'lexical_entry_id': 'hello',
              'reading': <String, dynamic>{},
              'listening': <String, dynamic>{},
              'speaking': <String, dynamic>{},
              'writing': <String, dynamic>{},
            }),
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
          onCapabilityOverride: (capability, conclusion) async =>
              records.add((capability, conclusion)),
        ),
      ),
    );
    // Four channels render an editable acquired / not-acquired pair each.
    expect(find.text('Acquired'), findsNWidgets(4));
    await tester.tap(find.text('Acquired').first);
    expect(records, [('reading', 'acquired')]);
  });

  testWidgets('zero-clip state offers external references only as reference', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
          externalLookupUrl: 'https://youglish.com/pronounce/hello/english',
          onOpenExternal: (url) => opened = url,
        ),
      ),
    );
    await tester.tap(find.text('Open on YouGlish'));
    expect(opened, 'https://youglish.com/pronounce/hello/english');
  });

  testWidgets('each clip exposes a review-queue exit', (tester) async {
    const occurrence = LexicalOccurrence(
      mediaTitleSnapshot: 'Personal media',
      mediaFingerprintSnapshot: 'fp-1',
      sentenceTextSnapshot: 'hello in a reviewable sentence.',
      startMsSnapshot: 1200,
      endMsSnapshot: 2400,
      encounterCount: 1,
      originalForm: 'hello',
      mediaId: 'media-1',
      sentenceId: 'sentence-1',
    );
    LexicalOccurrence? queued;
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
            occurrences: [occurrence],
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
          onReviewClip: (value) async => queued = value,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add this clip to review'));
    expect(queued, same(occurrence));
  });

  testWidgets('listening dictionary gives an honest zero-clip state', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        const ListeningDictionaryEntryView(
          details: LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'hello',
              normalizedForm: 'hello',
              displayForm: 'hello',
              kind: 'word',
              language: 'en',
            ),
          ),
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
        ),
      ),
    );
    expect(find.text('No source clips yet'), findsOneWidget);
    expect(find.textContaining('Open hello from a subtitle'), findsOneWidget);
  });

  testWidgets('dictionary shows submitted output and opens its attempt', (
    tester,
  ) async {
    const document = ProductionCorpusDocumentView(
      id: 'document-1',
      language: 'en',
      channel: 'written',
      assistance: 'learner_revision',
      attemptId: 'attempt-1',
      rubricId: 'rubric-1',
      responseRevision: 2,
      taskKind: 'opinion',
      mediaId: null,
      startMs: 0,
      endMs: 1000,
      responseText: 'This proposal is worth discussing.',
      producedAtMs: 42,
    );
    const hit = ProductionCorpusHitView(
      document: document,
      entry: ProductionCorpusEntryView(
        id: 'entry-1',
        documentId: 'document-1',
        normalizedKey: 'proposal',
        displayText: 'proposal',
        startChar: 5,
        endChar: 13,
      ),
    );
    ProductionCorpusHitView? opened;

    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: vocabularyDetails(displayForm: 'proposal'),
          showProductionCorpus: true,
          productionHits: const [hit],
          onOpenProductionAttempt: (value) => opened = value,
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
        ),
      ),
    );

    expect(find.text('My output'), findsOneWidget);
    expect(
      find.text('You used this word once in submitted writing.'),
      findsOneWidget,
    );
    expect(find.text('This proposal is worth discussing.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('production-output-document-1')),
    );
    expect(opened, same(hit));
  });

  testWidgets('dictionary distinguishes unavailable output from no output', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        ListeningDictionaryEntryView(
          details: vocabularyDetails(displayForm: 'proposal'),
          showProductionCorpus: true,
          productionHits: const [],
          productionLoadFailed: true,
          onPlay: _ignoreOccurrence,
          onMark: _ignoreMark,
        ),
      ),
    );

    expect(
      find.text('Your writing output is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('No writing output for this word yet.'), findsNothing);
  });

  testWidgets('status movement removes a word from the previous dynamic book', (
    tester,
  ) async {
    final word = vocabularyDetails(displayForm: 'Move me');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyBookView(words: [word], onWord: (_) {}),
        ),
      ),
    );
    expect(find.text('Move me'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyBookView(words: const [], onWord: (_) {}),
        ),
      ),
    );
    expect(find.text('Move me'), findsNothing);
  });

  testWidgets('word details show status history and playable source', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    final occurrence = <String, dynamic>{
      'sentence_text_snapshot': 'A playable source sentence.',
      'media_title_snapshot': 'Media',
      'encounter_count': 2,
      'media_id': 'media-id',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyDetailsView(
            entry: const {'status': 'known_recognized'},
            occurrences: [occurrence],
            history: const [
              {
                'previous_status': 'unknown_meaning',
                'new_status': 'known_recognized',
                'change_source': 'user_selection',
                'changed_at_ms': 1,
              },
            ],
            onSource: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.text('Current status: Known and recognized'), findsOneWidget);
    expect(find.text('unknown_meaning → known_recognized'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.text('A playable source sentence.'));
    expect(selected, same(occurrence));
  });

  testWidgets('vocabulary transfer actions invoke export and import', (
    tester,
  ) async {
    var exported = false;
    var imported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VocabularyTransferActions(
                onExport: () async => exported = true,
                onImport: () async => imported = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Export vocabulary assets'));
    await tester.tap(find.byTooltip('Import vocabulary assets'));
    expect(exported, isTrue);
    expect(imported, isTrue);
  });

  testWidgets(
    'word learning panel groups providers and edits durable content',
    (tester) async {
      String? definition;
      String? note;
      await tester.pumpWidget(
        localized(
          WordLearningPanel(
            details: _helloDetails,
            dictionary: _helloDictionary,
            pronunciation: _helloPronunciation,
            onStatus: (_) {},
            onSave: (value, memo) async {
              definition = value;
              note = memo;
            },
            onSource: (_) {},
            onHeard: () {},
            onNotHeard: () {},
          ),
        ),
      );
      expect(find.text('Provider A'), findsOneWidget);
      expect(find.text('həˈloʊ'), findsOneWidget);
      expect(find.byTooltip('Play pronunciation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('word-user-definition')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('word-user-definition')),
        'greeting',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('word-personal-note')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('word-personal-note')),
        'remember this',
      );
      await tester.scrollUntilVisible(
        find.text('Save'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save'));
      expect(definition, 'greeting');
      expect(note, 'remember this');
    },
  );

  testWidgets(
    'word learning panel breaks a Han word into per-character pinyin',
    (tester) async {
      await tester.pumpWidget(
        localized(
          WordLearningPanel(
            details: _coffeeDetails,
            dictionary: _coffeeDictionary,
            languageProfile: _zhPinyinProfile,
            onStatus: (_) {},
            onSave: (_, _) async {},
            onSource: (_) {},
            onHeard: () {},
            onNotHeard: () {},
          ),
        ),
      );
      // The word's characters are aligned with their pinyin syllables (字 → 拼音).
      expect(find.text('Characters'), findsOneWidget);
      expect(find.text('咖'), findsOneWidget);
      expect(find.text('啡'), findsOneWidget);
      expect(find.text('kā'), findsOneWidget);
      expect(find.text('fēi'), findsOneWidget);
    },
  );

  testWidgets('per-character pinyin does not fire for a Japanese kanji word', (
    tester,
  ) async {
    // 学生 is written in kanji (Han script) and even resolves in CC-CEDICT, so the
    // old Han-script gate would have rendered Chinese pinyin under a Japanese
    // word. The language gate must suppress it — this is the falsification guard.
    await tester.pumpWidget(
      localized(
        WordLearningPanel(
          details: _studentDetails,
          dictionary: _studentDictionary,
          onStatus: (_) {},
          onSave: (_, _) async {},
          onSource: (_) {},
          onHeard: () {},
          onNotHeard: () {},
        ),
      ),
    );
    // No per-character breakdown: the feature follows the pinyin pronunciation
    // system (Chinese), not the Han script that Japanese kanji share.
    expect(find.text('Characters'), findsNothing);
    expect(find.text('xué'), findsNothing);
  });

  testWidgets('localization renders simplified Chinese labels', (tester) async {
    await tester.pumpWidget(
      localized(const Text('placeholder'), locale: const Locale('zh')),
    );
    final context = tester.element(find.text('placeholder'));
    expect(AppLocalizations.of(context).text('vocabulary'), '词汇本');
  });
}

void _ignoreOccurrence(LexicalOccurrence _) {}

Future<bool> _ignoreMark(LexicalOccurrence _, bool ignoredHeard) async => true;

const _helloDetails = LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'lexical-hello',
    normalizedForm: 'hello',
    displayForm: 'Hello',
    kind: 'word',
    status: 'unknown_meaning',
    language: 'en',
  ),
);

const _helloDictionary = DictionaryLookupBundle(
  query: 'hello',
  normalizedLemma: 'hello',
  results: [
    DictionaryLookupResult(
      provider: DictionaryProviderDescriptor(
        id: 'provider-a',
        displayName: 'Provider A',
      ),
      lookup: DictionaryLookup(
        query: 'hello',
        lemma: 'hello',
        phonetics: [
          DictionaryPhonetic(
            text: '/hello/',
            audioUrl: 'https://example.test/hello.mp3',
          ),
        ],
        definitions: [
          DictionaryDefinition(text: 'a greeting', partOfSpeech: 'noun'),
        ],
      ),
    ),
  ],
);

const _helloPronunciation = WordPronunciation(
  tokenIndex: 0,
  text: 'Hello',
  normalized: 'hello',
  variants: [
    PronunciationVariant(
      displayIpa: 'həˈloʊ',
      phonemes: [
        PronunciationPhoneme(symbol: 'HH'),
        PronunciationPhoneme(symbol: 'AH0'),
        PronunciationPhoneme(symbol: 'L'),
        PronunciationPhoneme(symbol: 'OW1'),
      ],
    ),
  ],
);

const _coffeeDetails = LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'lexical-coffee',
    normalizedForm: '咖啡',
    displayForm: '咖啡',
    kind: 'word',
    status: 'unknown_meaning',
    language: 'zh',
  ),
);

const _coffeeDictionary = DictionaryLookupBundle(
  query: '咖啡',
  normalizedLemma: '咖啡',
  results: [
    DictionaryLookupResult(
      provider: DictionaryProviderDescriptor(
        id: 'cc-cedict',
        displayName: 'CC-CEDICT',
      ),
      lookup: DictionaryLookup(
        query: '咖啡',
        lemma: '咖啡',
        phonetics: [DictionaryPhonetic(text: 'kā fēi', region: 'zh')],
        definitions: [DictionaryDefinition(text: 'coffee')],
      ),
    ),
  ],
);

const _studentDetails = LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'lexical-student',
    normalizedForm: '学生',
    displayForm: '学生',
    kind: 'word',
    status: 'unknown_meaning',
    language: 'ja',
  ),
);

const _studentDictionary = DictionaryLookupBundle(
  query: '学生',
  normalizedLemma: '学生',
  results: [
    DictionaryLookupResult(
      provider: DictionaryProviderDescriptor(
        id: 'cc-cedict',
        displayName: 'CC-CEDICT',
      ),
      lookup: DictionaryLookup(
        query: '学生',
        lemma: '学生',
        phonetics: [DictionaryPhonetic(text: 'xué shēng', region: 'zh')],
        definitions: [DictionaryDefinition(text: 'student')],
      ),
    ),
  ],
);

const _zhPinyinProfile = LanguageProfile(
  languageCode: 'zh',
  pronunciation: 'zh.pinyin',
);
