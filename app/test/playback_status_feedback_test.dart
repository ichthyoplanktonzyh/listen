import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/player/playback_controls.dart';

/// §3.7 item 5: an info-level status ("Timeline resources refreshed") is about
/// a moment that has passed. It used to hold a permanent row open under the
/// transport, which cost the transcript above it a row for the rest of the
/// session. Errors are the opposite kind of message and keep their row.
void main() {
  testWidgets('an info status costs the transport no height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(_app(adapter: adapter, status: ''));
    await tester.pump();
    final quiet = tester.getSize(find.byType(PlaybackControls)).height;

    await tester.pumpWidget(_app(adapter: adapter, status: 'Timeline 资源已刷新'));
    await tester.pump();

    expect(find.byKey(const Key('playback-info-status')), findsOneWidget);
    expect(tester.getSize(find.byType(PlaybackControls)).height, quiet);
  });

  testWidgets('an info status leaves on its own', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(_app(adapter: adapter, status: 'Timeline 资源已刷新'));
    await tester.pump();

    expect(_fade(tester).opacity, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Faded out on its own, with no dismissal to perform and no row left
    // behind (§3.8 gives info 2.4s).
    expect(_fade(tester).opacity, 0);
  });

  testWidgets('an error keeps its row until it is dealt with', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(_app(adapter: adapter, status: ''));
    await tester.pump();
    final quiet = tester.getSize(find.byType(PlaybackControls)).height;

    await tester.pumpWidget(
      _app(adapter: adapter, status: '刷新失败', statusIsError: true),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Still there, and still holding its own row: an error is a thing to act
    // on, not a notification that passed (§3.8's error tier).
    expect(find.byKey(const Key('playback-error-status')), findsOneWidget);
    expect(find.byKey(const Key('playback-info-status')), findsNothing);
    expect(
      tester.getSize(find.byType(PlaybackControls)).height,
      greaterThan(quiet),
    );
  });
}

AnimatedOpacity _fade(WidgetTester tester) => tester.widget<AnimatedOpacity>(
  find
      .ancestor(
        of: find.byKey(const Key('playback-info-status')),
        matching: find.byType(AnimatedOpacity),
      )
      .first,
);

Widget _app({
  required DesktopPlayerAdapter adapter,
  required String status,
  bool statusIsError = false,
}) => MaterialApp(
  theme: ListenTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Column(
      children: [
        const Expanded(child: ColoredBox(color: Colors.black)),
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
          status: status,
          statusIsError: statusIsError,
          taskStatuses: const [],
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
          onMarkAbPoint: () {},
        ),
      ],
    ),
  ),
);
