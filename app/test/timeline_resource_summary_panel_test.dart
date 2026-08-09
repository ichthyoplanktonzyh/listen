import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/timeline_resource_summary_panel.dart';

void main() {
  testWidgets('timeline resource summary exposes candidates and activation', (
    tester,
  ) async {
    String? activated;
    var reviewRuns = 0;
    var exports = 0;
    await tester.pumpWidget(
      _Harness(
        child: TimelineResourceSummaryPanel(
          activeTrack: _track,
          document: const LLTimelineDocument(
            schema: 'llplayer.timeline.v1',
            metadata: LLTimelineMetadata(
              createdAt: Duration(milliseconds: 1),
              generatorId: 'fixture-generator',
              generatorVersion: 'v1',
              generatorMode: 'production_engine',
              mediaTitle: 'Fixture',
              mediaFingerprint: 'fingerprint',
              humanReviewed: false,
              extra: {'track_source': 'lltimeline-json-v1'},
            ),
            activeWordTimelineId: 'timeline-active',
            activePhoneTimelineId: 'phone-active',
            prosodyAnalyses: [_prosody],
            activeProsodyAnalysisId: 'prosody-active',
            rhythmFrames: [_activeRhythmFrame],
            artifacts: [
              LLTimelineArtifact(kind: 'production_report', payload: {}),
            ],
          ),
          summaries: const [
            WordTimelineSummary(
              id: 'timeline-active',
              trackId: 'track-1',
              mediaId: 'media-1',
              algorithmId: 'whisperx',
              algorithmVersion: '1.0',
              createdBy: 'algorithm',
              status: 'active',
              lifecycleStage: 'algorithm_candidate',
              wordCount: 12,
              providerIds: ['whisperx'],
              timingSources: ['asr_reported'],
              averageConfidence: 0.92,
              canActivate: true,
              canArchive: true,
              canDelete: true,
            ),
            WordTimelineSummary(
              id: 'timeline-mfa',
              trackId: 'track-1',
              mediaId: 'media-1',
              algorithmId: 'mfa',
              algorithmVersion: '2.0',
              createdBy: 'algorithm',
              status: 'candidate',
              lifecycleStage: 'algorithm_candidate',
              wordCount: 12,
              providerIds: ['mfa'],
              timingSources: ['forced_aligned'],
              averageConfidence: 0.95,
              canActivate: true,
              canArchive: true,
              canDelete: true,
            ),
          ],
          phoneSummaries: const [
            PhoneTimelineSummary(
              id: 'phone-active',
              trackId: 'track-1',
              mediaId: 'media-1',
              providerId: 'research-fixture',
              providerVersion: 'v1',
              phoneSet: 'research_fixture_symbols',
              precision: 'approximate',
              createdBy: 'algorithm',
              status: 'active',
              phoneCount: 8,
              findingCount: 2,
              averageConfidence: 0.5,
              canActivate: false,
              canArchive: true,
              canDelete: false,
            ),
          ],
          activeWordTimingCount: 0,
          error: null,
          onImport: () async {},
          onRefresh: () async {},
          onActivate: (timelineId) async => activated = timelineId,
          onManualReview: () async => reviewRuns++,
          onActivatePhoneTimeline: (_) async {},
          onArchivePhoneTimeline: (_) async {},
          onDeletePhoneTimeline: (_) async {},
          onExportLLTimeline: () async => exports++,
        ),
      ),
    );

    expect(find.text('LLTimeline present'), findsOneWidget);
    expect(find.text('Learning capabilities'), findsOneWidget);

    // S2 token provenance. This panel had nine icon sizes across 14/15/16/18
    // and five different `EdgeInsets`; the two steps it needs are `control` for
    // the header identity glyph, sitting beside 14px `titleSmall`, and `inline`
    // for the status markers that lead a line of 12px body text.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.timeline)).size,
      ListenIconSize.control,
    );
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byIcon(Icons.timeline),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding,
      ListenPadding.row,
    );
    // And no glyph anywhere in this pane sits off the ladder — the check the
    // source gate cannot make, since a size can reach an `Icon` through a
    // variable.
    final steps = <double>{
      ListenIconSize.inline,
      ListenIconSize.control,
      ListenIconSize.chrome,
      ListenIconSize.illustration,
    };
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.size != null) expect(steps, contains(icon.size));
    }
    expect(find.text('Word sync'), findsOneWidget);
    expect(find.text('Listening structure'), findsOneWidget);
    expect(
      find.textContaining('Document listening structure is ready'),
      findsOneWidget,
    );
    expect(find.text('Production report ready'), findsNothing);
    expect(find.textContaining('whisperx 1.0'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('Production report ready'), findsOneWidget);
    expect(find.textContaining('whisperx 1.0'), findsWidgets);
    expect(find.textContaining('mfa 2.0'), findsOneWidget);
    expect(find.textContaining('research-fixture'), findsWidgets);
    expect(find.textContaining('prosody-v1'), findsWidgets);

    await tester.tap(find.byIcon(Icons.rate_review_outlined));
    await tester.pump();
    expect(reviewRuns, 1);
    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pump();
    expect(exports, 1);

    const activateMfa = ValueKey('activate-word-timeline-timeline-mfa');
    await tester.ensureVisible(find.byKey(activateMfa));
    await tester.pump();
    await tester.tap(find.byKey(activateMfa));
    await tester.pump();

    expect(activated, 'timeline-mfa');
  });

  testWidgets('generated word timings keep workflow actions available', (
    tester,
  ) async {
    var exports = 0;
    await tester.pumpWidget(
      _Harness(
        child: TimelineResourceSummaryPanel(
          activeTrack: _track,
          document: const LLTimelineDocument(
            schema: 'llplayer.timeline.v1',
            metadata: LLTimelineMetadata(
              createdAt: Duration(milliseconds: 1),
              generatorId: 'llplayernext',
              generatorVersion: '0.7.0',
              generatorMode: 'production_engine',
              mediaTitle: 'Fixture',
              mediaFingerprint: 'fingerprint',
              humanReviewed: false,
              extra: {'track_source': 'ASR-small-en.srt'},
            ),
            activeWordTimelineId: null,
            activePhoneTimelineId: null,
            prosodyAnalyses: [],
            activeProsodyAnalysisId: null,
            rhythmFrames: [],
            artifacts: [],
          ),
          summaries: const [],
          phoneSummaries: const [],
          activeWordTimingCount: 703,
          error: null,
          onImport: () async {},
          onRefresh: () async {},
          onActivate: (_) async {},
          onManualReview: () async {},
          onActivatePhoneTimeline: (_) async {},
          onArchivePhoneTimeline: (_) async {},
          onDeletePhoneTimeline: (_) async {},
          onExportLLTimeline: () async => exports++,
        ),
      ),
    );

    expect(find.text('LLTimeline present'), findsOneWidget);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Generated word timings'), findsWidgets);
    expect(find.textContaining('703'), findsWidgets);

    await tester.tap(find.text('Export LLTimeline JSON'));
    await tester.pump();
    expect(exports, 1);
  });

  testWidgets('timeline resource summary shows legacy fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(
        child: TimelineResourceSummaryPanel(
          activeTrack: _track,
          document: null,
          summaries: const [],
          phoneSummaries: const [],
          activeWordTimingCount: 0,
          error: null,
          onImport: () async {},
          onRefresh: () async {},
          onActivate: (_) async {},
          onManualReview: () async {},
          onActivatePhoneTimeline: (_) async {},
          onArchivePhoneTimeline: (_) async {},
          onDeletePhoneTimeline: (_) async {},
          onExportLLTimeline: () async {},
        ),
      ),
    );

    expect(find.text('Legacy timing fallback'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(
      find.textContaining('Needs an active Word sync timeline'),
      findsOneWidget,
    );
    expect(find.text('No Word sync candidates'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('No Word sync candidates'), findsOneWidget);
  });
}

const _track = SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  source: 'fixture',
  cues: [
    Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'Hello',
      tokens: [],
    ),
  ],
);

const _prosody = ProsodyAnalysis(
  id: 'prosody-active',
  trackId: 'track-1',
  mediaId: 'media-1',
  providerId: 'listen-gen',
  providerVersion: '0.4.0',
  algorithm: 'prosody-v1',
  status: 'active',
  chunks: [
    ProsodicChunk(
      sentenceId: 'sentence-1',
      chunkIndex: 0,
      startTokenIndex: 0,
      endTokenIndex: 1,
    ),
  ],
  anchorCount: 2,
);

const _refs = RhythmFrameReferences(
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
);

const _activeRhythmFrame = LLTimelineRhythmFrame(
  id: 'rhythm-1',
  trackId: 'track-1',
  mediaId: 'media-1',
  sentenceId: 'sentence-1',
  parentWordTimelineId: 'timeline-active',
  providerId: 'wordtimeline-rhythm-frame',
  providerVersion: 'phase-2.21',
  status: 'active',
  metricsJson: TimelineMetrics.empty(),
  rhythmFrame: RhythmFrame(
    generatedFrom: 'wordtimeline_timing_prominence_v1',
    references: _refs,
    stressAnchors: [
      RhythmStressAnchor(
        tokenIndex: 0,
        start: Duration.zero,
        end: Duration(milliseconds: 300),
        label: 'Hello',
        reason: 'timing-supported anchor',
        importance: 'primary',
        isNucleus: true,
        prominence: 0.8,
        prominenceCues: ['timing'],
        signalSources: ['timing'],
        evidenceClass: 'heuristic_proxy',
        claimStatus: 'audio_supported',
        confidence: 0.8,
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
      phoneEvidenceCoverage: 0.0,
      rhythmConfidence: 0.8,
    ),
  ),
  createdAt: Duration(milliseconds: 10),
  updatedAt: Duration(milliseconds: 20),
);

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}
