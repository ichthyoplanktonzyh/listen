import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/local_api.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/main.dart';
import 'package:llplayer_next/m18_ui.dart';
import 'package:llplayer_next/timeline.dart';

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
  test('OpenSubtitles media hash follows the 64-bit file algorithm', () async {
    final directory = await Directory.systemTemp.createTemp(
      'llplayer-m18-hash-',
    );
    final file = File('${directory.path}/media.bin');
    await file.writeAsBytes(List<int>.filled(131072, 0));
    expect(await computeOpenSubtitlesMovieHash(file.path), '0000000000020000');
    await directory.delete(recursive: true);
  });

  testWidgets('learning asset tile shows phrase status and durable sources', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      localized(
        LearningAssetTile(
          details: const {
            'entry': {
              'display_form': 'piece of cake',
              'kind': 'phrase',
              'status': 'known_not_recognized',
            },
            'occurrences': [
              {'sentence_text_snapshot': 'That was a piece of cake.'},
            ],
          },
          onTap: () => selected = true,
        ),
      ),
    );
    expect(find.text('piece of cake'), findsOneWidget);
    expect(find.text('Phrase · Known, not recognized'), findsOneWidget);
    expect(find.text('1 Sources'), findsOneWidget);
    await tester.tap(find.text('piece of cake'));
    expect(selected, isTrue);
  });

  testWidgets('learning resource tile exposes provenance and install action', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      localized(
        LearningResourceTile(
          value: const {
            'display_name': 'ECDICT',
            'version': 'bc015ed2',
            'license': 'MIT',
            'state': 'available',
            'checksum_sha256': 'abc123',
          },
          busy: false,
          onToggle: () => toggled = true,
        ),
      ),
    );
    expect(find.text('ECDICT'), findsOneWidget);
    expect(find.textContaining('MIT · available'), findsOneWidget);
    expect(find.textContaining('abc123'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download));
    expect(toggled, isTrue);
  });

  testWidgets(
    'subtitle phrase underline prefers longest candidate and selects phrase',
    (tester) async {
      Map<String, dynamic>? selectedPhrase;
      var selectedWords = 0;
      const cue = Cue(
        id: 'sentence-1',
        index: 0,
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: 'I look forward to it.',
        tokens: [
          SubtitleToken(index: 0, kind: 'word', text: 'I', normalized: 'i'),
          SubtitleToken(
            index: 1,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(
            index: 2,
            kind: 'word',
            text: 'look',
            normalized: 'look',
          ),
          SubtitleToken(
            index: 3,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(
            index: 4,
            kind: 'word',
            text: 'forward',
            normalized: 'forward',
          ),
          SubtitleToken(
            index: 5,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(index: 6, kind: 'word', text: 'to', normalized: 'to'),
          SubtitleToken(
            index: 7,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(index: 8, kind: 'word', text: 'it', normalized: 'it'),
          SubtitleToken(
            index: 9,
            kind: 'punctuation',
            text: '.',
            normalized: null,
          ),
        ],
      );
      await tester.pumpWidget(
        localized(
          TokenLine(
            cue: cue,
            profiles: const {},
            showStyles: true,
            phraseCandidates: const [
              {
                'canonical_form': 'look forward to',
                'display_form': 'look forward to',
                'token_start': 2,
                'token_end': 6,
              },
              {
                'canonical_form': 'forward to',
                'display_form': 'forward to',
                'token_start': 4,
                'token_end': 6,
              },
            ],
            onWord: (_, _) async => selectedWords += 1,
            onPhrase: (candidate, _) async => selectedPhrase = candidate,
          ),
        ),
      );
      expect(find.byType(PhraseUnderlineSpan), findsOneWidget);
      final underline = tester.getRect(find.byType(PhraseUnderlineSpan));
      await tester.tapAt(Offset(underline.center.dx, underline.bottom - 2));
      expect(selectedPhrase?['canonical_form'], 'look forward to');
      expect(selectedWords, 0);
    },
  );
}
