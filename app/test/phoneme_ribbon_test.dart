import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/subtitle/connected_speech_reference_ribbon.dart';
import 'package:llplayer_next/widgets/subtitle/expected_pronunciation_reference.dart';
import 'package:llplayer_next/widgets/subtitle/phoneme_ribbon.dart';
import 'package:llplayer_next/widgets/subtitle/rhythm_frame_ribbon.dart';
import 'package:llplayer_next/widgets/subtitle/sound_pattern_mode_toggle.dart';

void main() {
  testWidgets('sound pattern ribbon has distinct audio identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            child: PhonemeRibbon(
              phones: [
                DetectedPhone(
                  symbol: 'S',
                  displayIpa: 's',
                  phoneSet: 'arpabet',
                  start: Duration(milliseconds: 100),
                  end: Duration(milliseconds: 180),
                  confidence: 0.8,
                  tokenIndex: 0,
                  provider: 'wav2vec2-ctc-phoneme',
                  modelRevision: 'model-rev',
                ),
              ],
              position: Duration(milliseconds: 120),
              lane: PhonemeRibbonLane.sound,
              tooltip: 'Sound line',
              findings: [
                PhonemeRibbonFinding(
                  phoneStart: 0,
                  phoneEnd: 0,
                  findingType: 'linking_or_insertion',
                  status: 'supported_by_alignment',
                  confidence: 0.68,
                  evidence: 'Insertion alignment',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.text('s'), findsOneWidget);
    expect(find.byTooltip('possible linking · 68%'), findsOneWidget);
  });

  testWidgets('sound pattern unavailable state is visible but compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            child: SoundPatternUnavailableRibbon(
              message: 'No real sound analysis for this line',
              tooltip: 'Only appears after audio analysis.',
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.text('No real sound analysis for this line'), findsOneWidget);
  });

  testWidgets('sound pattern evidence marker can request loop playback', (
    tester,
  ) async {
    PhonemeRibbonFinding? looped;
    const finding = PhonemeRibbonFinding(
      phoneStart: 0,
      phoneEnd: 0,
      findingType: 'weak_form',
      status: 'detected_in_audio',
      confidence: 0.84,
      evidence: 'reduction evidence',
      learnerLabelOverride: 'possible reduction',
      learnerHint: 'A vowel may be reduced in fast speech.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            child: PhonemeRibbon(
              phones: const [
                DetectedPhone(
                  symbol: 'AH',
                  displayIpa: 'ə',
                  phoneSet: 'arpabet',
                  start: Duration(milliseconds: 100),
                  end: Duration(milliseconds: 180),
                  confidence: 0.8,
                  tokenIndex: 0,
                  provider: 'wav2vec2-ctc-phoneme',
                  modelRevision: 'model-rev',
                ),
              ],
              position: const Duration(milliseconds: 120),
              lane: PhonemeRibbonLane.sound,
              findings: const [finding],
              onLoopFinding: (value) => looped = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ə'));

    expect(looped, same(finding));
  });

  testWidgets('rhythm frame ribbon surfaces rhythm cues in subtitle layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 460,
            child: RhythmFrameRibbon(
              title: 'Listening rhythm',
              anchorLabel: 'Anchors',
              weakGroupLabel: 'Weak groups',
              compressionLabel: 'Compressed',
              hotspotLabel: 'Hotspots',
              position: Duration(milliseconds: 130),
              pronunciation: PronunciationAnalysis(
                sentenceId: 's1',
                displayIpa: 'kədəv ˈmɑrkət',
                words: [
                  WordPronunciation(
                    tokenIndex: 2,
                    text: 'market',
                    normalized: 'market',
                    variants: [
                      PronunciationVariant(
                        displayIpa: 'ˈmɑrkət',
                        phonemes: [
                          PronunciationPhoneme(
                            symbol: 'AA1',
                            displayIpa: 'ɑ',
                            stress: 1,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              frame: RhythmFrame(
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
                    tokenIndex: 2,
                    start: Duration(milliseconds: 100),
                    end: Duration(milliseconds: 260),
                    label: 'market',
                    reason: 'main stress',
                    importance: 'primary',
                    isNucleus: true,
                    prominence: 0.82,
                    prominenceCues: ['timing', 'energy'],
                    signalSources: ['timing', 'energy'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'audio_supported',
                    confidence: 0.82,
                  ),
                  RhythmStressAnchor(
                    tokenIndex: 6,
                    start: Duration(milliseconds: 270),
                    end: Duration(milliseconds: 300),
                    label: 'predicted only',
                    reason: 'text prior',
                    importance: 'secondary',
                    isNucleus: false,
                    prominence: 0.48,
                    prominenceCues: ['text_prior'],
                    signalSources: ['text_prior'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'predicted',
                    confidence: 0.48,
                  ),
                ],
                nuclei: [
                  RhythmNucleus(
                    phraseIndex: 0,
                    tokenIndex: 2,
                    start: Duration(milliseconds: 100),
                    end: Duration(milliseconds: 260),
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
                    tokenStart: 0,
                    tokenEnd: 1,
                    start: Duration(milliseconds: 0),
                    end: Duration(milliseconds: 90),
                    label: 'could have',
                    reason: 'function words are reduced',
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
                    reason: 'packed timing',
                    signalSources: ['timing'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'audio_supported',
                    confidence: 0.74,
                  ),
                ],
                phraseBoundaries: [
                  RhythmPhraseBoundary(
                    at: Duration(milliseconds: 310),
                    reason: 'pause',
                    cues: ['pause'],
                    signalSources: ['timing'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'audio_supported',
                    isFinal: false,
                    confidence: 0.8,
                  ),
                ],
                connectedSpeechRefs: [
                  RhythmConnectedSpeechRef(
                    id: 'cs1',
                    tokenStart: 0,
                    tokenEnd: 1,
                    label: 'weak form',
                    defaultDisplayIpa: 'kədəv',
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
    );

    expect(find.byIcon(Icons.hearing), findsOneWidget);
    expect(find.text('Listening rhythm'), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    expect(find.text('/ɑ/'), findsOneWidget);
    expect(find.textContaining('market'), findsWidgets);
    expect(find.text('kədəv'), findsOneWidget);
    expect(find.textContaining('could have been'), findsNothing);
    expect(find.text('weak group'), findsNothing);
    expect(find.textContaining('predicted only'), findsNothing);
    expect(
      find.byTooltip(
        'Nucleus: market\n/ɑ/\nmain stress\n'
        'audio supported · heuristic proxy · timing, energy',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rhythm frame ribbon shows audible consonant vowel shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: RhythmFrameRibbon(
              title: 'This audio',
              anchorLabel: 'Anchors',
              weakGroupLabel: 'Weak groups',
              compressionLabel: 'Compressed',
              hotspotLabel: 'Hotspots',
              position: Duration(milliseconds: 150),
              pronunciation: PronunciationAnalysis(
                sentenceId: 's1',
                displayIpa: 'tʃeɪndʒd',
                words: [
                  WordPronunciation(
                    tokenIndex: 0,
                    text: 'changed',
                    normalized: 'changed',
                    variants: [
                      PronunciationVariant(
                        displayIpa: 'tʃeɪndʒd',
                        phonemes: [
                          PronunciationPhoneme(symbol: 'CH', displayIpa: 'tʃ'),
                          PronunciationPhoneme(
                            symbol: 'EY1',
                            displayIpa: 'eɪ',
                            stress: 1,
                          ),
                          PronunciationPhoneme(symbol: 'N', displayIpa: 'n'),
                          PronunciationPhoneme(symbol: 'JH', displayIpa: 'dʒ'),
                          PronunciationPhoneme(symbol: 'D', displayIpa: 'd'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              frame: RhythmFrame(
                generatedFrom: 'wordtimeline_timing_prominence_v1',
                references: RhythmFrameReferences(
                  citation: RhythmReference(
                    label: 'citation_form',
                    source: 'dictionary_lexical_stress',
                    evidenceClass: 'heuristic_proxy',
                  ),
                  actual: RhythmReference(
                    label: 'actual_delivery',
                    source: 'word_timeline_duration',
                    evidenceClass: 'heuristic_proxy',
                  ),
                ),
                stressAnchors: [
                  RhythmStressAnchor(
                    tokenIndex: 0,
                    start: Duration(milliseconds: 100),
                    end: Duration(milliseconds: 260),
                    label: 'changed',
                    reason: 'clearly timed content sound',
                    importance: 'secondary',
                    isNucleus: false,
                    prominence: 0.72,
                    prominenceCues: ['timing'],
                    signalSources: ['timing'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'audio_supported',
                    confidence: 0.72,
                  ),
                ],
                nuclei: [],
                weakGroups: [],
                compressionSpans: [],
                phraseBoundaries: [],
                connectedSpeechRefs: [],
                listeningHotspots: [],
                quality: RhythmFrameQuality(
                  timingSource: 'word_timeline',
                  prominenceSources: ['timing'],
                  boundarySources: [],
                  connectedSpeechSource: 'text_prior',
                  phoneEvidenceCoverage: 0,
                  rhythmConfidence: 0.72,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('/tʃeɪndʒd/'), findsOneWidget);
    expect(find.text('changed'), findsOneWidget);
    expect(
      find.byTooltip(
        'Anchors: changed\n/tʃeɪndʒd/\nclearly timed content sound\n'
        'audio supported · heuristic proxy · timing',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rhythm frame ribbon can request cue loop playback', (
    tester,
  ) async {
    Duration? loopStart;
    Duration? loopEnd;
    String? loopLabel;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: RhythmFrameRibbon(
              title: 'Listening rhythm',
              anchorLabel: 'Anchors',
              weakGroupLabel: 'Weak groups',
              compressionLabel: 'Compressed',
              hotspotLabel: 'Hotspots',
              position: const Duration(milliseconds: 40),
              onLoopCue: (start, end, label) {
                loopStart = start;
                loopEnd = end;
                loopLabel = label;
              },
              frame: const RhythmFrame(
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
                stressAnchors: [
                  RhythmStressAnchor(
                    start: Duration(milliseconds: 100),
                    end: Duration(milliseconds: 260),
                    label: 'market',
                    reason: 'main stress',
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
                nuclei: [],
                weakGroups: [
                  RhythmWeakGroup(
                    start: Duration(milliseconds: 20),
                    end: Duration(milliseconds: 90),
                    label: 'weak group',
                    reason: 'backgrounded',
                    reductionRefs: [],
                    signalSources: ['timing'],
                    evidenceClass: 'heuristic_proxy',
                    claimStatus: 'audio_supported',
                    confidence: 0.7,
                  ),
                ],
                compressionSpans: [],
                phraseBoundaries: [],
                connectedSpeechRefs: [],
                listeningHotspots: [],
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
    );

    await tester.tap(find.text('weak group'));

    expect(loopStart, const Duration(milliseconds: 20));
    expect(loopEnd, const Duration(milliseconds: 90));
    expect(loopLabel, 'weak group');
  });

  testWidgets('rhythm reference toggle switches among A B and C', (
    tester,
  ) async {
    final changes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RhythmReferenceToggle(
            mode: 'actual',
            citationTooltip: 'A dictionary',
            connectedTooltip: 'B common speech',
            actualTooltip: 'C this audio',
            semanticsLabel: 'Rhythm references',
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('C this audio'));
    expect(changes, isEmpty);

    await tester.tap(find.byTooltip('A dictionary'));
    await tester.tap(find.byTooltip('B common speech'));
    expect(changes, ['citation', 'connected']);
  });

  testWidgets('connected speech reference shows A to B rule changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 480,
            child: ConnectedSpeechReferenceRibbon(
              title: 'Common speech',
              currentTokenIndex: 4,
              tokens: [
                SubtitleToken(
                  index: 0,
                  kind: 'word',
                  text: 'I',
                  normalized: 'i',
                ),
                SubtitleToken(
                  index: 1,
                  kind: 'whitespace',
                  text: ' ',
                  normalized: null,
                ),
                SubtitleToken(
                  index: 2,
                  kind: 'word',
                  text: 'could',
                  normalized: 'could',
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
                  text: 'have',
                  normalized: 'have',
                ),
                SubtitleToken(
                  index: 5,
                  kind: 'whitespace',
                  text: ' ',
                  normalized: null,
                ),
                SubtitleToken(
                  index: 6,
                  kind: 'word',
                  text: 'gone',
                  normalized: 'gone',
                ),
              ],
              references: [
                RhythmConnectedSpeechRef(
                  id: 'cs1',
                  tokenStart: 2,
                  tokenEnd: 4,
                  family: 'contraction',
                  surfaceText: 'could have',
                  label: 'default contraction',
                  hint: 'This phrase commonly reduces in connected speech.',
                  expectedSymbols: ['K', 'UH', 'D', 'HH', 'AE', 'V'],
                  defaultSymbols: ['K', 'UH', 'D', 'AH', 'V'],
                  expectedDisplayIpa: 'kʊdhæv',
                  defaultDisplayIpa: 'kʊdəv',
                  divergence: 'teachable_rule',
                  signalSources: ['text_prior'],
                  evidenceClass: 'heuristic_proxy',
                  confidence: 0.78,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(find.text('Common speech'), findsOneWidget);
    expect(find.text('could have'), findsOneWidget);
    expect(find.text('contraction'), findsOneWidget);
    expect(find.text('/kʊdhæv/ → /kʊdəv/'), findsOneWidget);
    expect(find.text('I'), findsOneWidget);
    expect(find.text('gone'), findsOneWidget);
    expect(
      find.byTooltip(
        'could have\n/kʊdhæv/ → /kʊdəv/\n'
        'This phrase commonly reduces in connected speech.\ncontraction',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'expected pronunciation reference shows word IPA and current word',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              child: ExpectedPronunciationReference(
                title: 'Expected',
                currentTokenIndex: 2,
                analysis: PronunciationAnalysis(
                  sentenceId: 's1',
                  displayIpa: 'ðə ˈmɑrkət',
                  words: [
                    WordPronunciation(
                      tokenIndex: 0,
                      text: 'The',
                      normalized: 'the',
                      variants: [PronunciationVariant(displayIpa: 'ðə')],
                    ),
                    WordPronunciation(
                      tokenIndex: 2,
                      text: 'market',
                      normalized: 'market',
                      variants: [PronunciationVariant(displayIpa: 'ˈmɑrkət')],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
      expect(find.text('Expected'), findsOneWidget);
      expect(find.text('ðə'), findsOneWidget);
      expect(find.text('ˈmɑrkət'), findsOneWidget);
      expect(find.byTooltip('market: ˈmɑrkət'), findsOneWidget);
    },
  );
}
