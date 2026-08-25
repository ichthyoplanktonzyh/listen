import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/widgets/panels/sentence_analysis_window.dart';
import 'package:llplayer_next/widgets/subtitle/phoneme_ribbon.dart';
import 'package:llplayer_next/widgets/subtitle/rhythm_frame_ribbon.dart';

const _sentence = 'Hundreds of hungry pelicans are flocking.';

Cue _cue() => const Cue(
  id: 'cue-1',
  index: 0,
  start: Duration.zero,
  end: Duration(seconds: 2),
  text: _sentence,
  tokens: [],
);

({
  Widget widget,
  LearningController learning,
  int Function() diagnosisCalls,
  int Function() closes,
})
_harness({
  bool withCurrentCue = true,
  LLTimelineDocument? document,
  List<DetectedPhone> phones = const [],
}) {
  final subtitle = SubtitleController();
  if (withCurrentCue) {
    final cue = _cue();
    subtitle
      ..setPrimaryTrack(
        SubtitleTrack(id: 'track-1', cues: [cue], source: 'fixture'),
      )
      ..setCurrentPrimaryCue(cue);
  }
  if (document != null) {
    subtitle.setTimelineResource(
      summaries: const [],
      phoneSummaries: const [],
      document: document,
    );
  }
  if (phones.isNotEmpty) {
    subtitle.setSpeechEnhancements(
      pronunciationBySentence: const {},
      timingsBySentence: const {},
      pronunciationProviders: const [],
      phonesBySentence: {'cue-1': phones},
    );
  }
  final learning = LearningController();
  final player = PlayerController();
  final playback = PlaybackActionsCoordinator(
    adapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
  );
  var diagnosisCalls = 0;
  var closes = 0;

  final widget = MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            SentenceAnalysisWindow(
              subtitleController: subtitle,
              learningController: learning,
              settingsController: SettingsController(),
              playbackActions: playback,
              voiceClipPlayer: SlicePlayerController(),
              onRequestDiagnosis: () async {
                diagnosisCalls += 1;
              },
              onPlayVoiceClip: () async {},
              onSetSoundPatternDisplayMode: (_) async {},
              onClose: () => closes += 1,
            ),
          ],
        ),
      ),
    ),
  );

  return (
    widget: widget,
    learning: learning,
    diagnosisCalls: () => diagnosisCalls,
    closes: () => closes,
  );
}

void main() {
  testWidgets(
    'opens on the text layer and marks grammar/collocation unavailable',
    (tester) async {
      final h = _harness();
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // The current sentence heads the text layer, and the layers that need an
      // AI contract we do not have say so plainly instead of faking a result.
      expect(find.text(_sentence), findsOneWidget);
      expect(
        find.byKey(const Key('analysis-text-unavailable')),
        findsOneWidget,
      );
      // Opening the window automatically prefetches the voice diagnosis so it
      // is ready when the reader switches tabs.
      expect(h.diagnosisCalls(), 1);
    },
  );

  testWidgets(
    'switching to the voice layer shows pending when diagnosis not ready',
    (tester) async {
      final h = _harness();
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
          matching: find.text('语音'),
        ),
      );
      await tester.pumpAndSettle();

      expect(h.diagnosisCalls(), 1);
      expect(
        find.byKey(const Key('transcript-analysis-pending')),
        findsOneWidget,
      );
    },
  );

  testWidgets('the close button asks the host to close', (tester) async {
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('analysis-window-close')));
    expect(h.closes(), 1);
  });

  // An adopted package carries no sound analysis: Core's import contract
  // lands every package resource as a candidate, so the track has no active
  // phone timeline and C has to read the phones straight off the exported
  // document — the same document its rhythm frames come from. Without this a
  // fully generated package shows "unavailable" over real evidence.
  testWidgets('C renders from package phones and the document rhythm frame', (
    tester,
  ) async {
    final h = _harness(document: _document(), phones: _packagePhones);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
        matching: find.text('语音'),
      ),
    );
    // The rendered ribbons animate continuously, so settle never arrives here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RhythmFrameRibbon), findsOneWidget);
    expect(find.byType(PhonemeRibbon), findsOneWidget);
    expect(find.byType(SoundPatternUnavailableRibbon), findsNothing);
  });

  testWidgets('C stays unavailable when the package carried no phones', (
    tester,
  ) async {
    final h = _harness(document: _document());
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
        matching: find.text('语音'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SoundPatternUnavailableRibbon), findsOneWidget);
    expect(find.byType(RhythmFrameRibbon), findsNothing);
  });
}

const _packagePhones = [
  DetectedPhone(
    symbol: 'h',
    displayIpa: 'h',
    phoneSet: 'ipa',
    start: Duration.zero,
    end: Duration(milliseconds: 120),
    confidence: 0.4,
    tokenIndex: 0,
    provider: 'wav2vec2-ctc-phoneme',
    modelRevision: 'fixture',
  ),
  DetectedPhone(
    symbol: 'ʌ',
    displayIpa: 'ʌ',
    phoneSet: 'ipa',
    start: Duration(milliseconds: 120),
    end: Duration(milliseconds: 300),
    confidence: 0.5,
    tokenIndex: 0,
    provider: 'wav2vec2-ctc-phoneme',
    modelRevision: 'fixture',
  ),
];

/// The export shape Core produces for an adopted package: rhythm frames built
/// from real energy prominence (so no phone coverage of their own, since that
/// builder is handed no learning phones), plus the phones as candidates.
LLTimelineDocument _document() => LLTimelineDocument(
  schema: 'llplayer.timeline.v1',
  metadata: const LLTimelineMetadata(
    createdAt: Duration(milliseconds: 1),
    generatorId: 'listen-resource-package',
    generatorVersion: 'v3',
    generatorMode: 'adopted_package',
    mediaTitle: 'Fixture',
    mediaFingerprint: 'fingerprint',
    humanReviewed: false,
    extra: {'track_source': 'package:subtitle_text_track'},
  ),
  activeWordTimelineId: null,
  activePhoneTimelineId: null,
  prosodyAnalyses: const [],
  activeProsodyAnalysisId: null,
  rhythmFrames: const [
    LLTimelineRhythmFrame(
      id: 'rhythm-package',
      trackId: 'track-1',
      mediaId: 'media-1',
      sentenceId: 'cue-1',
      parentWordTimelineId: 'word-package-candidate',
      providerId: 'wordtimeline-rhythm-frame',
      providerVersion: '1.0',
      status: 'active',
      metricsJson: TimelineMetrics.empty(),
      rhythmFrame: RhythmFrame(
        generatedFrom: 'wordtimeline_estimated_acoustic_prominence_v1',
        references: RhythmFrameReferences(
          citation: RhythmReference(
            label: 'citation_form',
            source: 'lexicon',
            evidenceClass: 'heuristic_proxy',
          ),
          actual: RhythmReference(
            label: 'this_audio',
            source: 'audio',
            evidenceClass: 'measured',
          ),
        ),
        stressAnchors: [
          RhythmStressAnchor(
            start: Duration.zero,
            end: Duration(milliseconds: 300),
            label: 'Hundreds',
            reason: 'energy-supported anchor',
            importance: 'primary',
            isNucleus: true,
            prominence: 0.7,
            prominenceCues: ['energy'],
            signalSources: ['energy'],
            evidenceClass: 'heuristic_proxy',
            claimStatus: 'audio_supported',
            confidence: 0.7,
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
          prominenceSources: ['energy'],
          boundarySources: [],
          connectedSpeechSource: 'text_prior',
          phoneEvidenceCoverage: 0.0,
          rhythmConfidence: 0.6,
        ),
      ),
      createdAt: Duration(milliseconds: 10),
      updatedAt: Duration(milliseconds: 20),
    ),
  ],
  artifacts: const [],
);
