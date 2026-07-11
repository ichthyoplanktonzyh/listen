import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/media_workbench.dart';
import 'package:llplayer_next/widgets/player/playback_controls.dart';

void main() {
  Widget localized(Widget child) => MaterialApp(
    theme: ListenTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  testWidgets('media workbench keeps media and transcript visible when wide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      localized(
        const MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: ColoredBox(key: Key('media-stage'), color: Colors.black),
          learningPanel: ColoredBox(
            key: Key('learning-panel'),
            color: Colors.white,
          ),
          mediaFraction: 0.42,
          onMediaFractionChanged: _noopFraction,
        ),
      ),
    );

    expect(find.byKey(const Key('media-stage')), findsOneWidget);
    expect(find.byKey(const Key('learning-panel')), findsOneWidget);
    expect(find.text('CNN 10.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide workbench divider resizes media and transcript panes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      localized(
        const MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: ColoredBox(
            key: Key('resizable-media-stage'),
            color: Colors.black,
          ),
          learningPanel: ColoredBox(color: Colors.white),
          mediaFraction: 0.42,
          onMediaFractionChanged: _noopFraction,
        ),
      ),
    );
    final widthBefore = tester
        .getSize(find.byKey(const Key('resizable-media-stage')))
        .width;

    await tester.drag(
      find.byKey(const Key('media-workbench-splitter')),
      const Offset(120, 0),
    );
    await tester.pump();

    final widthAfter = tester
        .getSize(find.byKey(const Key('resizable-media-stage')))
        .width;
    expect(widthAfter, greaterThan(widthBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('media workbench stacks panes in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      localized(
        const MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: ColoredBox(color: Colors.black),
          learningPanel: ColoredBox(color: Colors.white),
          mediaFraction: 0.42,
          onMediaFractionChanged: _noopFraction,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('playback controls fit without a horizontal scroller', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      localized(
        PlaybackControls(
          adapter: adapter,
          position: const Duration(seconds: 15),
          duration: const Duration(minutes: 10),
          playing: false,
          loopCue: false,
          statusStylesVisible: true,
          subtitlesVisible: true,
          secondarySubtitlesVisible: false,
          secondarySubtitlesAvailable: false,
          rate: 1,
          volume: 80,
          muted: false,
          audioTracks: const [],
          selectedAudioId: null,
          embeddedSubtitleTracks: const [],
          selectedEmbeddedSubtitleId: null,
          primarySubtitleOffset: Duration.zero,
          secondarySubtitleOffset: Duration.zero,
          status: 'Ready',
          taskStatuses: const [],
          extensiveListeningActive: false,
          listeningMarkEnabled: true,
          listeningInboxCount: 0,
          chunkControlsEnabled: true,
          chunkLoopActive: false,
          onSeek: (_) {},
          onSeekToPreviousCue: () {},
          onSeekToZero: () {},
          onPlayPause: () {},
          onStop: () {},
          onSeekToNextCue: () {},
          onSeekToPreviousChunk: () {},
          onSeekToNextChunk: () {},
          onLoopCurrentChunk: () {},
          onLoopExpandedChunk: () {},
          onLoopCueChanged: (_) {},
          onStopSourceLoop: () {},
          onStatusStylesChanged: (_) {},
          onSubtitlesVisibleChanged: (_) {},
          onSecondaryVisibleChanged: (_) {},
          onRateChanged: (_) {},
          onVolumeChanged: (_) {},
          onMuteToggle: () {},
          onAudioTrackChanged: (_) {},
          onEmbeddedSubtitleTrackChanged: (_) {},
          onPrimaryOffsetChanged: (_) {},
          onSecondaryOffsetChanged: (_) {},
          onToggleExtensiveListening: () {},
          onCaptureListeningInbox: () {},
          onHardInterruptListening: () {},
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact playback uses a three-part player layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      localized(
        PlaybackControls(
          adapter: adapter,
          position: const Duration(minutes: 5, seconds: 54),
          duration: const Duration(minutes: 10, seconds: 21),
          playing: false,
          loopCue: false,
          statusStylesVisible: true,
          subtitlesVisible: true,
          secondarySubtitlesVisible: false,
          secondarySubtitlesAvailable: false,
          rate: 1,
          volume: 80,
          muted: false,
          audioTracks: const [],
          selectedAudioId: null,
          embeddedSubtitleTracks: const [],
          selectedEmbeddedSubtitleId: null,
          primarySubtitleOffset: Duration.zero,
          secondarySubtitleOffset: Duration.zero,
          status: 'Ready',
          taskStatuses: const [],
          extensiveListeningActive: false,
          listeningMarkEnabled: true,
          listeningInboxCount: 0,
          chunkControlsEnabled: true,
          chunkLoopActive: false,
          onSeek: (_) {},
          onSeekToPreviousCue: () {},
          onSeekToZero: () {},
          onPlayPause: () {},
          onStop: () {},
          onSeekToNextCue: () {},
          onSeekToPreviousChunk: () {},
          onSeekToNextChunk: () {},
          onLoopCurrentChunk: () {},
          onLoopExpandedChunk: () {},
          onLoopCueChanged: (_) {},
          onStopSourceLoop: () {},
          onStatusStylesChanged: (_) {},
          onSubtitlesVisibleChanged: (_) {},
          onSecondaryVisibleChanged: (_) {},
          onRateChanged: (_) {},
          onVolumeChanged: (_) {},
          onMuteToggle: () {},
          onAudioTrackChanged: (_) {},
          onEmbeddedSubtitleTrackChanged: (_) {},
          onPrimaryOffsetChanged: (_) {},
          onSecondaryOffsetChanged: (_) {},
          onToggleExtensiveListening: () {},
          onCaptureListeningInbox: () {},
          onHardInterruptListening: () {},
          isCompact: true,
          mediaTitle: 'How a cell phone ban transformed this school.mp4',
          onExpand: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('compact-player-media-info')), findsOneWidget);
    expect(find.byKey(const Key('compact-player-play-pause')), findsOneWidget);
    expect(find.text('00:05:54 / 00:10:21'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noopFraction(double value) {}
