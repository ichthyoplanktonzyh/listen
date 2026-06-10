import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/main.dart';

void main() {
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
        home: Scaffold(body: VocabularyBookView(words: [word], onWord: (_) {})),
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
    expect(find.text('Current status: known_recognized'), findsOneWidget);
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
}
