import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/player_stage.dart';
import 'package:llplayer_next/widgets/player/playback_controls.dart';

/// #25-A: the fullscreen entries around the immersive state — the transport
/// button and the double-click on the bare video surface.
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

  Widget controls({
    required bool isFullscreen,
    VoidCallback? onToggleFullscreen,
    DesktopPlayerAdapter? adapter,
  }) => PlaybackControls(
    adapter: adapter!,
    position: const AlwaysStoppedAnimation<Duration>(Duration(seconds: 15)),
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
    isFullscreen: isFullscreen,
    onToggleFullscreen: onToggleFullscreen,
  );

  testWidgets('the transport fullscreen button toggles and flips its face', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    var toggles = 0;
    await tester.pumpWidget(
      localized(
        controls(
          isFullscreen: false,
          onToggleFullscreen: () => toggles++,
          adapter: adapter,
        ),
      ),
    );
    final button = find.byKey(const Key('playback-fullscreen-toggle'));
    expect(button, findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_outlined), findsOneWidget);
    await tester.tap(button);
    expect(toggles, 1);

    await tester.pumpWidget(
      localized(
        controls(
          isFullscreen: true,
          onToggleFullscreen: () => toggles++,
          adapter: adapter,
        ),
      ),
    );
    expect(find.byIcon(Icons.fullscreen_exit_outlined), findsOneWidget);
  });

  testWidgets('no fullscreen host, no button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      localized(controls(isFullscreen: false, adapter: adapter)),
    );
    expect(find.byKey(const Key('playback-fullscreen-toggle')), findsNothing);
  });

  testWidgets('double-clicking the bare video surface toggles fullscreen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);
    final playerController = PlayerController();
    final subtitleController = SubtitleController();
    final learningController = LearningController();
    final settingsController = SettingsController();

    var toggles = 0;
    await tester.pumpWidget(
      localized(
        PlayerStage(
          adapter: adapter,
          playerController: playerController,
          subtitleController: subtitleController,
          learningController: learningController,
          settingsController: settingsController,
          onSeekCue: (_) async {},
          onSeekChunk: (_) async {},
          onOpenWord: (_, _) async {},
          onOpenPhrase: (_, _) async {},
          onLoopSoundRibbonFinding: (_, _) async {},
          onLoopRhythmCue: (_, _, _) async {},
          onSetSoundPatternDisplayMode: (_) async {},
          onSaveSettings: () async {},
          onOpenMedia: () async {},
          onToggleFullscreen: () => toggles++,
        ),
      ),
    );

    expect(find.byKey(const Key('player-stage-surface')), findsOneWidget);
    // Tap away from the centered open-media prompt: the double-click must
    // land on the bare surface itself.
    const bareSurfacePoint = Offset(80, 80);
    await tester.tapAt(bareSurfacePoint);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(bareSurfacePoint);
    await tester.pumpAndSettle();
    expect(toggles, 1);
  });
}
