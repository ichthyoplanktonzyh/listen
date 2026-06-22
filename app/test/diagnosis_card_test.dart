import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/panels/diagnosis_card.dart';

void main() {
  testWidgets('sentence and whole-track analysis triggers remain distinct', (
    tester,
  ) async {
    var sentenceRuns = 0;
    var trackRuns = 0;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: DiagnosisCard(
            diagnosis: const {'hints': <dynamic>[]},
            onAnalyzePhonetics: () => sentenceRuns++,
            onAnalyzeTrackPhonetics: () => trackRuns++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Analyze audio pronunciation'));
    await tester.tap(find.text('Analyze subtitle track'));

    expect(sentenceRuns, 1);
    expect(trackRuns, 1);
  });

  testWidgets('recognition barrier renders per-language listening factors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: DiagnosisCard(
            diagnosis: const {
              'hints': [
                {
                  'kind': 'recognition_barrier',
                  'message': 'Known words were not recognized.',
                  'word_profile_ids': ['p1'],
                  'reasons': ['tone_confusion', 'word_boundary'],
                },
                {
                  'kind': 'meaning_barrier',
                  'message': 'Unknown vocabulary.',
                  'word_profile_ids': ['p2'],
                  'reasons': <dynamic>[],
                },
              ],
            },
          ),
        ),
      ),
    );

    // The recognition barrier surfaces the language's listening factors,
    // localized and clearly framed as possibilities (not detections).
    expect(find.textContaining('Factors to consider'), findsOneWidget);
    expect(find.textContaining('tone confusion'), findsOneWidget);
    expect(find.textContaining('word boundary'), findsOneWidget);
  });

  testWidgets('audio findings expose evidence loop and feedback actions', (
    tester,
  ) async {
    DetectedPhone? loopedPhone;
    Map<String, dynamic>? loopedFinding;
    String? feedback;
    final finding = <String, dynamic>{
      'id': 'finding-1',
      'finding_type': 'possible_elision',
      'status': 'uncertain',
      'confidence': 0.5,
      'evidence': 'Deletion alignment evidence',
      'audio_start_ms': 100,
      'audio_end_ms': 200,
    };
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: DiagnosisCard(
            diagnosis: const {'hints': <dynamic>[]},
            pronunciation: const {'rules': <dynamic>[]},
            phoneticAnalysis: {
              'provider_id': 'fixture',
              'model_revision': 'v1',
              'phone_set': 'test',
              'detected_phones': [
                {
                  'symbol': 'AH',
                  'phone_set': 'test',
                  'start_ms': 100,
                  'end_ms': 150,
                  'confidence': 0.5,
                  'token_index': 0,
                  'provider_id': 'fixture',
                  'model_revision': 'v1',
                },
              ],
              'findings': [finding],
            },
            onLoopDetectedPhone: (value) => loopedPhone = value,
            onLoopFinding: (value) => loopedFinding = value,
            onFindingFeedback: (_, value) => feedback = value,
          ),
        ),
      ),
    );

    expect(find.text('Canonical pronunciation'), findsOneWidget);
    expect(find.text('Audio detection (experimental)'), findsOneWidget);
    await tester.tap(find.text('AH 50%'));
    expect(loopedPhone?.symbol, 'AH');

    await tester.scrollUntilVisible(
      find.text('Loop evidence'),
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Loop evidence'));
    expect(loopedFinding, same(finding));
    await tester.tap(find.text('Matches what I hear'));
    expect(feedback, 'confirmed');
    await tester.scrollUntilVisible(
      find.text('Rule prediction'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Rule prediction'), findsOneWidget);
  });
}
