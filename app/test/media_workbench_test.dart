import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/media_workbench.dart';
import 'package:llplayer_next/models/content_channel.dart';
import 'package:llplayer_next/widgets/layout/content_channel_switcher.dart';
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
    // The header reads the title, not the file name (§3.7).
    expect(find.text('CNN 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session header shows the title and keeps the file name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fileName =
        'How a cell phone ban has transformed this Brooklyn middle '
        'school｜June 9, 2026 [9FFSOYLiFxc].mp4';
    await tester.pumpWidget(
      localized(
        const MediaWorkbench(
          mediaTitle: fileName,
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

    final title = tester.widget<Text>(
      find.byKey(const Key('workbench-media-title')),
    );
    expect(
      title.data,
      'How a cell phone ban has transformed this Brooklyn middle school',
    );

    // Nothing is hidden: the raw name is one hover away.
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('workbench-media-title')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, fileName);
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

    // The splitter also answers a double-click, so a drag leaves that
    // recognizer's tracking timer behind. Let it expire inside the test.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('double-clicking the splitter restores the default split', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The two layout buttons this replaces sat in a 56px toolbar above the
    // video, permanently, for an action taken once in a while.
    final fractions = <double>[];
    await tester.pumpWidget(
      localized(
        MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: const ColoredBox(color: Colors.black),
          learningPanel: const ColoredBox(color: Colors.white),
          mediaFraction: 0.6,
          onMediaFractionChanged: fractions.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('media-workbench-splitter')));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.byKey(const Key('media-workbench-splitter')));
    await tester.pump(kDoubleTapTimeout);

    expect(fractions, [0.42]);
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

  testWidgets('content channels gate unavailable capabilities honestly', (
    tester,
  ) async {
    ContentChannel? selected;
    await tester.pumpWidget(
      localized(
        MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: const ColoredBox(color: Colors.black),
          learningPanel: const ColoredBox(color: Colors.white),
          mediaFraction: 0.42,
          onMediaFractionChanged: _noopFraction,
          selectedChannel: ContentChannel.listening,
          channelAvailability: const {
            ContentChannel.listening: ContentChannelAvailability.available(),
            ContentChannel.reading: ContentChannelAvailability.available(),
            ContentChannel.speaking: ContentChannelAvailability.unavailable(
              '尚无录音能力',
            ),
          },
          onChannelSelected: (channel) => selected = channel,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('content-channel-reading')));
    expect(selected, ContentChannel.reading);
    selected = null;
    await tester.tap(find.byKey(const ValueKey('content-channel-speaking')));
    expect(selected, isNull);
  });

  testWidgets('immersive channel owns the workbench body', (tester) async {
    await tester.pumpWidget(
      localized(
        const MediaWorkbench(
          mediaTitle: 'CNN 10.mp4',
          playerStage: ColoredBox(key: Key('old-stage'), color: Colors.black),
          learningPanel: ColoredBox(key: Key('old-panel'), color: Colors.white),
          immersiveStage: ColoredBox(
            key: Key('reading-stage'),
            color: Colors.white,
          ),
          mediaFraction: 0.42,
          onMediaFractionChanged: _noopFraction,
        ),
      ),
    );

    expect(find.byKey(const Key('reading-stage')), findsOneWidget);
    expect(find.byKey(const Key('old-stage')), findsNothing);
    expect(find.byKey(const Key('old-panel')), findsNothing);
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
          position: const AlwaysStoppedAnimation<Duration>(
            Duration(seconds: 15),
          ),
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
          position: const AlwaysStoppedAnimation<Duration>(
            Duration(minutes: 5, seconds: 54),
          ),
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
