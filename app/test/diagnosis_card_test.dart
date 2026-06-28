import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
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
            diagnosis: const Diagnosis(),
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
            diagnosis: const Diagnosis(
              hints: [
                DiagnosisHint(
                  kind: 'recognition_barrier',
                  lexicalEntryIds: ['p1'],
                  reasons: ['tone_confusion', 'word_boundary'],
                ),
                DiagnosisHint(kind: 'meaning_barrier', lexicalEntryIds: ['p2']),
              ],
            ),
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
    PhoneticFinding? loopedFinding;
    String? feedback;
    const finding = PhoneticFinding(
      id: 'finding-1',
      findingType: 'possible_elision',
      status: 'uncertain',
      confidence: 0.5,
      evidence: 'Deletion alignment evidence',
      audioStartMs: 100,
      audioEndMs: 200,
    );
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
            diagnosis: const Diagnosis(),
            pronunciation: const PronunciationAnalysis(
              sentenceId: 'sentence-1',
              displayIpa: 'AH',
              rules: [
                PronunciationRule(
                  ruleFamily: 'weak_form',
                  reason: 'context',
                  status: 'likely_by_context',
                  confidence: 0.7,
                ),
              ],
            ),
            phoneticAnalysis: const PhoneticAnalysis(
              providerId: 'fixture',
              modelRevision: 'v1',
              phoneSet: 'test',
              detectedPhones: [
                DetectedPhone(
                  symbol: 'AH',
                  displayIpa: 'AH',
                  phoneSet: 'test',
                  start: Duration(milliseconds: 100),
                  end: Duration(milliseconds: 150),
                  confidence: 0.5,
                  tokenIndex: 0,
                  provider: 'fixture',
                  modelRevision: 'v1',
                ),
              ],
              findings: [finding],
            ),
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

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loop evidence'));
    expect(loopedFinding, same(finding));
    await tester.tap(find.text('Matches what I hear'));
    expect(feedback, 'confirmed');
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('Rule prediction'), findsOneWidget);
  });
}
