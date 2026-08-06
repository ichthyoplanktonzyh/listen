import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/panels/word_bubble.dart';

/// Tapping a word used to swap the whole side panel to the word tab, which
/// took the transcript off screen on every lookup. The bubble replaces that,
/// and its job is to be honest at glance size: the lookup arrives in two steps
/// and the bubble must never leave a blank where a definition would go.
void main() {
  testWidgets('waiting for the entry says it is waiting', (tester) async {
    await tester.pumpWidget(_harness(const WordBubbleFixture()));
    await tester.pump();

    expect(find.text('查询中…'), findsOneWidget);
    // Nothing about the word is claimed before the entry exists.
    expect(find.byKey(const Key('word-bubble-details')), findsNothing);
  });

  testWidgets('an entry with no dictionary yet still says it is waiting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(WordBubbleFixture(details: _details('hello'))),
    );
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('查询中…'), findsOneWidget);
  });

  testWidgets('a dictionary that returned nothing says so, not blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WordBubbleFixture(
          details: _details('hello'),
          dictionary: const DictionaryLookupBundle(
            query: 'hello',
            normalizedLemma: 'hello',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('词典没有返回释义。'), findsOneWidget);
  });

  testWidgets('a failed provider reads as a failure, not as "no such word"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WordBubbleFixture(
          details: _details('hello'),
          dictionary: DictionaryLookupBundle(
            query: 'hello',
            normalizedLemma: 'hello',
            results: [
              DictionaryLookupResult(
                provider: const DictionaryProviderDescriptor(
                  id: 'p',
                  displayName: 'Provider',
                ),
                error: 'timeout',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('词典查询失败。'), findsOneWidget);
    expect(find.text('词典没有返回释义。'), findsNothing);
  });

  testWidgets('a definition names the provider it came from', (tester) async {
    await tester.pumpWidget(
      _harness(
        WordBubbleFixture(
          details: _details('hello'),
          dictionary: DictionaryLookupBundle(
            query: 'hello',
            normalizedLemma: 'hello',
            results: [
              DictionaryLookupResult(
                provider: const DictionaryProviderDescriptor(
                  id: 'ecdict',
                  displayName: 'ECDICT',
                ),
                lookup: const DictionaryLookup(
                  query: 'hello',
                  lemma: 'hello',
                  definitions: [DictionaryDefinition(text: '你好')],
                  phonetics: [DictionaryPhonetic(text: '/həˈloʊ/')],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('你好'), findsOneWidget);
    // A gloss with no source is a claim with no source.
    expect(find.text('ECDICT'), findsOneWidget);
    expect(find.text('/həˈloʊ/'), findsOneWidget);
  });

  testWidgets('the full entry stays one click away', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _harness(
        WordBubbleFixture(
          details: _details('hello'),
          onOpenDetails: () => opened += 1,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('word-bubble-details')));
    expect(opened, 1);
  });
}

/// Named so the test reads as a fixture rather than a second widget: it only
/// fills in the callbacks the bubble requires.
class WordBubbleFixture extends StatelessWidget {
  const WordBubbleFixture({
    super.key,
    this.details,
    this.dictionary,
    this.onOpenDetails,
  });

  final LexicalEntryDetails? details;
  final DictionaryLookupBundle? dictionary;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) => WordBubble(
    details: details,
    dictionary: dictionary,
    pronunciation: null,
    onStatus: (_) {},
    onOpenDetails: onOpenDetails ?? () {},
  );
}

LexicalEntryDetails _details(String lemma) => LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'lexical-1',
    normalizedForm: lemma,
    displayForm: '${lemma[0].toUpperCase()}${lemma.substring(1)}',
    kind: 'word',
    language: 'en',
  ),
);

Widget _harness(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);
