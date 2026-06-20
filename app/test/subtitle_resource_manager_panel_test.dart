import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/panels/subtitle_resource_manager_panel.dart';

void main() {
  testWidgets('subtitle resource manager exposes consumption capabilities', (
    tester,
  ) async {
    SubtitleTrack? activated;
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'Hello',
      tokens: [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'Hello',
          normalized: 'hello',
        ),
      ],
    );
    const track = SubtitleTrack(id: 'track-1', cues: [cue], source: 'imported');

    await tester.pumpWidget(
      _Harness(
        child: SubtitleResourceManagerPanel(
          mediaId: 'media-1',
          resources: const [track],
          capabilities: const {
            'track-1': SubtitleResourceCapabilities(
              sentenceTiming: true,
              wordTiming: true,
              chunkTiming: true,
              phoneTiming: false,
              sentenceCount: 1,
              wordTimingCount: 1,
              chunkCount: 1,
            ),
          },
          activeTrack: null,
          timelineDocument: null,
          wordTimelineSummaries: const [],
          timelineResourceError: null,
          onImportSubtitle: () async {},
          onImportLLTimeline: () async {},
          onRefreshResources: () async {},
          onActivateSubtitle: (track) async => activated = track,
          onArchiveSubtitle: (_) async {},
          onRestoreSubtitle: (_) async {},
          onDeleteSubtitle: (_) async {},
          onExportSubtitle: (_) async {},
          onActivateWordTimeline: (_) async {},
          onManualReviewTimeline: () async {},
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(find.text('Word 1'), findsOneWidget);
    expect(find.text('Chunk 1'), findsOneWidget);
    expect(find.text('Phone 0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    expect(activated?.id, 'track-1');
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
    home: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
  );
}
