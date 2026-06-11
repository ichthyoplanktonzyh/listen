import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/main.dart';
import 'package:llplayer_next/localization.dart';

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
      'profile': {'display_form': 'Hello'},
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
      'profile': {'display_form': 'Move me'},
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
            profile: const {'status': 'known_recognized'},
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
            details: const {
              'profile': {
                'display_form': 'Hello',
                'status': 'unknown_meaning',
                'user_definition': null,
                'personal_note': null,
              },
              'occurrences': [],
              'history': [],
            },
            dictionary: const {
              'results': [
                {
                  'provider': {'display_name': 'Provider A'},
                  'lookup': {
                    'phonetics': [
                      {
                        'text': '/hello/',
                        'audio_url': 'https://example.test/hello.mp3',
                      },
                    ],
                    'definitions': [
                      {'text': 'a greeting', 'part_of_speech': 'noun'},
                    ],
                  },
                  'error': null,
                },
              ],
            },
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

  testWidgets('localization renders simplified Chinese labels', (tester) async {
    await tester.pumpWidget(
      localized(const Text('placeholder'), locale: const Locale('zh')),
    );
    final context = tester.element(find.text('placeholder'));
    expect(AppLocalizations.of(context).text('vocabulary'), '词汇本');
  });
}
