import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/subtitle/phoneme_ribbon.dart';

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
}
