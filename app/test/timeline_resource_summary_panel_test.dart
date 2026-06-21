import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
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
            activeChunkTimelineId: 'chunk-active',
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
          chunkSummaries: const [
            ChunkTimelineSummary(
              id: 'chunk-active',
              trackId: 'track-1',
              mediaId: 'media-1',
              providerId: 'partitioner',
              providerVersion: 'v4',
              algorithm: 'acoustic_semantic_v1',
              precision: 'precise',
              createdBy: 'algorithm',
              status: 'active',
              chunkCount: 4,
              canActivate: true,
              canArchive: true,
              canDelete: true,
            ),
          ],
          error: null,
          onImport: () async {},
          onRefresh: () async {},
          onActivate: (timelineId) async => activated = timelineId,
          onManualReview: () async => reviewRuns++,
          onGenerateChunkTimeline: () async {},
          onActivateChunkTimeline: (_) async {},
          onArchiveChunkTimeline: (_) async {},
          onDeleteChunkTimeline: (_) async {},
          onExportLLTimeline: () async => exports++,
        ),
      ),
    );

    expect(find.text('LLTimeline present'), findsOneWidget);
    expect(find.text('Production report ready'), findsOneWidget);
    expect(find.textContaining('whisperx 1.0'), findsWidgets);
    expect(find.textContaining('mfa 2.0'), findsOneWidget);
    expect(find.textContaining('acoustic_semantic_v1'), findsWidgets);

    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();

    expect(activated, 'timeline-mfa');
    await tester.tap(find.byIcon(Icons.rate_review_outlined));
    await tester.pump();
    expect(reviewRuns, 1);
    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pump();
    expect(exports, 1);
  });

  testWidgets('timeline resource summary shows legacy fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(
        child: TimelineResourceSummaryPanel(
          document: null,
          summaries: const [],
          chunkSummaries: const [],
          error: null,
          onImport: () async {},
          onRefresh: () async {},
          onActivate: (_) async {},
          onManualReview: () async {},
          onGenerateChunkTimeline: () async {},
          onActivateChunkTimeline: (_) async {},
          onArchiveChunkTimeline: (_) async {},
          onDeleteChunkTimeline: (_) async {},
          onExportLLTimeline: () async {},
        ),
      ),
    );

    expect(find.text('Legacy timing fallback'), findsOneWidget);
    expect(find.text('No WordTimeline candidates'), findsOneWidget);
  });
}

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
