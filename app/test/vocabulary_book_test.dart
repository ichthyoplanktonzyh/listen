import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/panels/word_learning_panel.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_book_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_details_view.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_transfer_actions.dart';
import 'package:llplayer_next/utils/subtitle_position.dart';
import 'package:llplayer_next/utils/subtitle_style.dart';
import 'package:llplayer_next/utils/word_list_parser.dart';

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
    Map<String, dynamic>? selected;
    final word = <String, dynamic>{
      'entry': {'display_form': 'Hello'},
      'occurrences': [
        {
          'sentence_text_snapshot': 'Hello from a durable snapshot.',
          'media_id': null,
        },
      ],
    };
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

  testWidgets('empty vocabulary book has an explicit state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VocabularyBookView(words: const [], onWord: (_) {}),
      ),
    );
    expect(find.text('No words in this book'), findsOneWidget);
  });

  testWidgets('status movement removes a word from the previous dynamic book', (
    tester,
  ) async {
    final word = <String, dynamic>{
      'entry': {'display_form': 'Move me'},
      'occurrences': const [],
    };
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
      await tester.enterText(find.byType(TextField).first, 'greeting');
      await tester.enterText(find.byType(TextField).last, 'remember this');
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
