import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
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
        child: _resourceManager(
          track: track,
          activeTrack: null,
          onActivateSubtitle: (track) async => activated = track,
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Learning capabilities'), findsWidgets);

    // S2 token provenance: the pane header is a `row` inset with a `control`
    // glyph, and the language pill is `tight` — the 7/3 it used to carry was
    // not a step on any ladder.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.subtitles_outlined).first).size,
      ListenIconSize.control,
    );
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byIcon(Icons.subtitles_outlined).first,
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding,
      ListenPadding.row,
    );
    // And no glyph in the pane sits off the ladder — including the ones whose
    // size arrives through a variable, which the source gate cannot see.
    final steps = <double>{
      ListenIconSize.inline,
      ListenIconSize.control,
      ListenIconSize.chrome,
      ListenIconSize.illustration,
    };
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.size != null) expect(steps, contains(icon.size));
    }
    expect(
      find.textContaining('Subtitles · Available · 1 cues'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Word sync · Available · 1 Words'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Chunk replay · Available · 1 Chunks'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Phone evidence · Unavailable · 0 Phones'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Listening structure · Activate to inspect'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    expect(activated?.id, 'track-1');
  });

  testWidgets('subtitle and timeline resource panes resize without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'How a cell phone ban has transformed this Brooklyn middle school',
      tokens: [],
    );
    const track = SubtitleTrack(id: 'track-1', cues: [cue], source: 'imported');

    await tester.pumpWidget(
      _Harness(
        child: SizedBox(
          width: 560,
          height: 420,
          child: _resourceManager(
            track: track,
            activeTrack: track,
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
                extra: {},
              ),
              activeWordTimelineId: null,
              activePhoneTimelineId: null,
              activeChunkTimelineId: null,
              rhythmFrames: [],
              artifacts: [],
            ),
            activeWordTimingCount: 1773,
          ),
        ),
      ),
    );

    final listPane = find.byKey(const Key('subtitle-resource-list-pane'));
    final timelinePane = find.byKey(const Key('timeline-resource-pane'));
    final listHeightBefore = tester.getSize(listPane).height;
    final timelineHeightBefore = tester.getSize(timelinePane).height;

    await tester.drag(
      find.byKey(const Key('subtitle-resource-splitter')),
      const Offset(0, 70),
    );
    await tester.pump();

    expect(tester.getSize(listPane).height, greaterThan(listHeightBefore));
    expect(tester.getSize(timelinePane).height, lessThan(timelineHeightBefore));
    expect(tester.takeException(), isNull);
  });
}

SubtitleResourceManagerPanel _resourceManager({
  required SubtitleTrack track,
  required SubtitleTrack? activeTrack,
  Future<void> Function(SubtitleTrack track)? onActivateSubtitle,
  LLTimelineDocument? document,
  int activeWordTimingCount = 0,
}) => SubtitleResourceManagerPanel(
  mediaId: 'media-1',
  resources: [track],
  capabilities: {
    track.id: SubtitleResourceCapabilities(
      sentenceTiming: true,
      wordTiming: true,
      chunkTiming: true,
      phoneTiming: false,
      sentenceCount: track.cues.length,
      wordTimingCount: activeWordTimingCount == 0 ? 1 : activeWordTimingCount,
      chunkCount: 1,
    ),
  },
  activeTrack: activeTrack,
  timelineDocument: document,
  wordTimelineSummaries: const [],
  phoneTimelineSummaries: const [],
  chunkTimelineSummaries: const [],
  activeWordTimingCount: activeWordTimingCount,
  timelineResourceError: null,
  onImportSubtitle: () async {},
  onImportLLTimeline: () async {},
  onRefreshResources: () async {},
  onActivateSubtitle: onActivateSubtitle ?? (_) async {},
  onArchiveSubtitle: (_) async {},
  onRestoreSubtitle: (_) async {},
  onDeleteSubtitle: (_) async {},
  onExportSubtitle: (_) async {},
  onLanguageChanged: (_, _) async {},
  availableLanguages: const ['en', 'zh', 'ja'],
  onExportLLTimeline: (_) async {},
  onActivateWordTimeline: (_) async {},
  onManualReviewTimeline: () async {},
  onActivatePhoneTimeline: (_) async {},
  onArchivePhoneTimeline: (_) async {},
  onDeletePhoneTimeline: (_) async {},
  onGenerateChunkTimeline: () async {},
  onActivateChunkTimeline: (_) async {},
  onArchiveChunkTimeline: (_) async {},
  onDeleteChunkTimeline: (_) async {},
);

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ListenTheme.light(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox(width: 900, height: 900, child: child)),
  );
}
