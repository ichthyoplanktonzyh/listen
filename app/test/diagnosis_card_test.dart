import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
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

    expect(find.text('Canonical pronunciation'), findsNothing);
    await tester.tap(find.text('Evidence and analysis'));
    await tester.pumpAndSettle();
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

  testWidgets('rhythm frame renders before phone evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(
          body: DiagnosisCard(
            diagnosis: Diagnosis(),
            phoneticAnalysis: PhoneticAnalysis(
              providerId: 'fixture',
              modelRevision: 'v1',
              phoneSet: 'arpabet',
              soundAnalysis: SoundAnalysis(
                providerId: 'fixture',
                providerVersion: 'v1',
                phoneSet: 'arpabet',
                generatedFrom: 'expected_phones_aligned_to_observed_timing',
                learningPhones: [],
                connectedSpeech: [],
                syllables: [],
                prosodicPhrases: [],
                rhythmFrame: RhythmFrame(
                  generatedFrom: 'wordtimeline_timing_acoustic_prominence_v1',
                  references: RhythmFrameReferences(
                    citation: RhythmReference(
                      label: 'citation_form',
                      source: 'dictionary_lexical_stress',
                      evidenceClass: 'heuristic_proxy',
                    ),
                    defaultConnected: RhythmReference(
                      label: 'default_connected_variants',
                      source: 'english_connected_speech_rules_v1',
                      evidenceClass: 'heuristic_proxy',
                    ),
                    actual: RhythmReference(
                      label: 'actual_delivery',
                      source: 'word_timeline_duration_energy',
                      evidenceClass: 'heuristic_proxy',
                    ),
                  ),
                  stressAnchors: [
                    RhythmStressAnchor(
                      start: Duration(milliseconds: 100),
                      end: Duration(milliseconds: 300),
                      label: 'market',
                      reason: 'anchor',
                      importance: 'primary',
                      isNucleus: true,
                      prominence: 0.82,
                      prominenceCues: ['timing', 'energy'],
                      signalSources: ['timing', 'energy'],
                      evidenceClass: 'heuristic_proxy',
                      claimStatus: 'audio_supported',
                      confidence: 0.82,
                    ),
                  ],
                  nuclei: [
                    RhythmNucleus(
                      phraseIndex: 0,
                      start: Duration(milliseconds: 100),
                      end: Duration(milliseconds: 300),
                      label: 'market',
                      reason: 'phrase nucleus',
                      cues: ['timing', 'energy'],
                      evidenceClass: 'heuristic_proxy',
                      claimStatus: 'audio_supported',
                      confidence: 0.82,
                    ),
                  ],
                  weakGroups: [
                    RhythmWeakGroup(
                      start: Duration(milliseconds: 0),
                      end: Duration(milliseconds: 90),
                      label: 'could have',
                      reason: 'weak',
                      reductionRefs: ['cs1'],
                      signalSources: ['timing'],
                      evidenceClass: 'heuristic_proxy',
                      claimStatus: 'audio_supported',
                      confidence: 0.7,
                    ),
                  ],
                  compressionSpans: [
                    RhythmCompressionSpan(
                      start: Duration(milliseconds: 0),
                      end: Duration(milliseconds: 180),
                      expectedUnits: 5,
                      duration: Duration(milliseconds: 180),
                      unitRatePerSecond: 27.8,
                      label: 'could have been',
                      reason: 'packed',
                      signalSources: ['timing'],
                      evidenceClass: 'heuristic_proxy',
                      claimStatus: 'audio_supported',
                      confidence: 0.74,
                    ),
                  ],
                  phraseBoundaries: [],
                  connectedSpeechRefs: [
                    RhythmConnectedSpeechRef(
                      id: 'cs1',
                      label: 'weak form',
                      divergence: 'clip_specific',
                      signalSources: ['phone_segmental'],
                      evidenceClass: 'heuristic_proxy',
                      confidence: 0.7,
                    ),
                  ],
                  listeningHotspots: [
                    ListeningHotspot(
                      id: 'hs1',
                      kind: 'weak_group',
                      start: Duration(milliseconds: 0),
                      end: Duration(milliseconds: 90),
                      label: 'weak group',
                      hint: 'backgrounded',
                      signalSources: ['timing'],
                      evidenceClass: 'heuristic_proxy',
                      claimStatus: 'audio_supported',
                      confidence: 0.7,
                    ),
                  ],
                  quality: RhythmFrameQuality(
                    timingSource: 'word_timeline',
                    prominenceSources: ['timing', 'energy'],
                    boundarySources: ['timing'],
                    connectedSpeechSource: 'phone_segmental',
                    phoneEvidenceCoverage: 0.9,
                    rhythmConfidence: 0.77,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Listening structure'), findsNothing);
    await tester.tap(find.text('Evidence and analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Listening structure'), findsOneWidget);
    expect(find.text('Nucleus:'), findsOneWidget);
    expect(find.text('Heard anchors:'), findsOneWidget);
    expect(find.text('market 82% audible'), findsWidgets);
    expect(find.text('could have 70% audible'), findsOneWidget);
    expect(find.text('could have been 74% audible'), findsOneWidget);
    expect(find.text('weak group 70% audible'), findsOneWidget);
    expect(find.textContaining('Rhythm confidence: 77%'), findsOneWidget);
  });

  testWidgets('document rhythm hotspot can trigger evidence loop', (
    tester,
  ) async {
    ListeningHotspot? looped;
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
            rhythmFrame: const RhythmFrame(
              generatedFrom: 'wordtimeline_timing_acoustic_prominence_v1',
              references: RhythmFrameReferences(
                citation: RhythmReference(
                  label: 'citation_form',
                  source: 'dictionary_lexical_stress',
                  evidenceClass: 'heuristic_proxy',
                ),
                actual: RhythmReference(
                  label: 'actual_delivery',
                  source: 'word_timeline_duration_energy',
                  evidenceClass: 'heuristic_proxy',
                ),
              ),
              stressAnchors: [],
              nuclei: [],
              weakGroups: [],
              compressionSpans: [],
              phraseBoundaries: [],
              connectedSpeechRefs: [],
              listeningHotspots: [
                ListeningHotspot(
                  id: 'hs1',
                  kind: 'compressed_span',
                  start: Duration(milliseconds: 120),
                  end: Duration(milliseconds: 260),
                  label: 'packed words',
                  hint: 'compressed function words',
                  signalSources: ['timing'],
                  evidenceClass: 'heuristic_proxy',
                  claimStatus: 'audio_supported',
                  confidence: 0.72,
                ),
              ],
              quality: RhythmFrameQuality(
                timingSource: 'word_timeline',
                prominenceSources: ['timing'],
                boundarySources: ['timing'],
                connectedSpeechSource: 'timing',
                phoneEvidenceCoverage: 0,
                rhythmConfidence: 0.6,
              ),
            ),
            onLoopHotspot: (value) => looped = value,
          ),
        ),
      ),
    );

    expect(find.text('packed words 72% audible'), findsNothing);
    await tester.tap(find.text('Evidence and analysis'));
    await tester.pumpAndSettle();
    expect(find.text('packed words 72% audible'), findsOneWidget);
    await tester.tap(find.text('packed words 72% audible'));
    expect(looped?.id, 'hs1');
  });
}
