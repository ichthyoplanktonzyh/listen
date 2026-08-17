import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/widgets/panels/diagnosis_card.dart';

void main() {
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

  testWidgets('diagnosis links lexical barriers to the listening dictionary', (
    tester,
  ) async {
    String? opened;
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
                  lexicalEntryIds: ['entry-1'],
                ),
              ],
            ),
            onOpenListeningDictionary: (id) async => opened = id,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Listen in dictionary'));
    expect(opened, 'entry-1');

    // Token provenance: the dictionary link is a secondary action, so its
    // glyph is `control` — not the 16 it used to carry while its neighbour on
    // the same card carried 14. The gate can only see that no literal is left;
    // this sees that both now land on one step.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.headphones_outlined)).size,
      ListenIconSize.control,
    );
  });

  testWidgets('audio findings expose evidence loop and feedback actions', (
    tester,
  ) async {
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
          // The card is content inside a list — the transcript's, in
          // production — so the list is what scrolls it.
          body: ListView(
            children: [
              DiagnosisCard(
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
                onLoopFinding: (value) => loopedFinding = value,
                onFindingFeedback: (_, value) => feedback = value,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Canonical pronunciation'), findsNothing);
    await tester.tap(find.text('Evidence and analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Canonical pronunciation'), findsOneWidget);
    expect(find.text('Audio detection (experimental)'), findsOneWidget);

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

  // The analysis opens inside the sentence it describes, which means it is
  // built as one item of the transcript's own `ListView` — an unbounded
  // height. A card that was a scroll view itself threw
  // "Vertical viewport was given unbounded height" from `performLayout`, and a
  // render box whose layout threw never gets a size: every pointer that
  // afterwards crossed the card produced "Cannot hit test a render box with no
  // size", until a hover landed mid-update and tripped the mouse tracker's
  // `!_debugDuringDeviceUpdate` assertion. The analysis was unusable.
  testWidgets('analysis lays out inline, where height is unbounded', (
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
          // The transcript, in miniature: a vertical list whose items get no
          // height from above.
          body: ListView(
            children: const [
              Text('a sentence'),
              DiagnosisCard(
                diagnosis: Diagnosis(
                  hints: [
                    DiagnosisHint(
                      kind: 'recognition_barrier',
                      reasons: ['tone_confusion'],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Evidence and analysis'), findsOneWidget);

    // And it still opens: the evidence section is reachable, which is what the
    // sizeless render box took away.
    await tester.tap(find.text('Evidence and analysis'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
