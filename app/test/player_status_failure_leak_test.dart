import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/named_failure.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/player/playback_controls.dart';

/// The transport bar's status line, driven by a playback failure that really
/// happens.
///
/// `DesktopPlayerAdapter` published `Stream<String>` and put the decoder's own
/// text in it — `'Playback failed: $error'`, `'Position polling failed:
/// $error'` — and the composition root passed that string to `setStatus`
/// unchanged. So the transport bar printed whatever `video_player` threw.
///
/// Nothing here is a hand-written failure string. `open()` is given a path
/// that does not exist, so the real `VideoPlayerController.file` really runs,
/// the real platform channel really has no implementation behind it, and the
/// real `UnimplementedError` really reaches the adapter's own `catch`. What
/// the adapter published before the fix, verbatim:
///
///     Playback failed: UnimplementedError: init() has not been implemented.
///
/// These are plain `test`/`testWidgets` bodies rather than one: a widget
/// test's clock is fake and `initialize()` never settles under it, so the
/// failure is raised in a real-clock test and the rendering asserted
/// separately from the state it produced.
void main() {
  /// A localization key resolves to a sentence; an exception's text does not.
  /// Whatever reaches the status line has to be one of the two.
  const leaks = [
    'UnimplementedError',
    'Exception',
    'init() has not been implemented',
    'Playback failed:',
    'Position polling failed:',
    'HttpException',
    'correlation_id',
    '127.0.0.1',
  ];

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a playback failure publishes a key, not the decoder\'s sentence',
    () async {
      final adapter = DesktopPlayerAdapter();
      // Typed as Object so this assertion compiles against the pre-fix
      // `Stream<String>` too — it has to, or it could never have run red.
      final published = <Object>[];
      final subscription = adapter.errors.listen(published.add);

      await expectLater(
        adapter.open('/nonexistent/never-here.mp4'),
        throwsA(anything),
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(published, hasLength(1));
      final text = '${published.single}';
      for (final leak in leaks) {
        expect(
          text,
          isNot(contains(leak)),
          reason:
              '"$leak" is what the decoder said; the adapter publishes a name '
              'for it instead. The adapter published:\n$text',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the exception is kept, just somewhere it cannot be rendered',
    () async {
      final adapter = DesktopPlayerAdapter();
      final published = <NamedFailureRecord>[];
      final subscription = adapter.errors.listen(
        (failure) =>
            published.add((key: failure.messageKey, detail: failure.detail)),
      );

      await expectLater(
        adapter.open('/nonexistent/never-here.mp4'),
        throwsA(anything),
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      final failure = published.single;
      expect(failure.key, 'statusPlaybackFailed');
      // Still carried — `raw` is the sanctioned diagnostic home, and the
      // disclosure is documented as never rendering it.
      expect(failure.detail?.raw, contains('UnimplementedError'));
      // And there is nothing a disclosure could honestly show for a decoder
      // error, so it grows no affordance at all.
      expect(failure.detail?.correlationId, isNull);
      expect(failure.detail?.message, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('the status line names the failure and does not quote it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);

    // The seam the composition root uses, driven with the failure the adapter
    // really publishes when a decoder cannot start.
    final controller = PlayerController();
    addTearDown(controller.dispose);
    late AppLocalizations l;

    await tester.pumpWidget(
      _app(
        adapter: adapter,
        status: '',
        statusIsError: false,
        onContext: (context) => l = AppLocalizations.of(context),
      ),
    );
    controller.setNamedFailure(
      const NamedFailure(
        'statusPlaybackFailed',
        detail: ApiFailure(raw: rawFromRealAdapter),
      ),
      l.text,
    );

    await tester.pumpWidget(
      _app(
        adapter: adapter,
        status: controller.status,
        statusIsError: controller.statusIsError,
        statusFailure: controller.statusFailure,
        onContext: (_) {},
      ),
    );
    await tester.pump();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');
    for (final leak in leaks) {
      expect(
        rendered,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; the transport bar is not a place to '
            'print it. The bar said:\n$rendered',
      );
    }
    expect(find.text('Playback failed'), findsOneWidget);
    // A decoder error has no reference id, so there is nothing to disclose and
    // no door is drawn. `ApiFailureDetailsButton` decides that itself.
    expect(find.byKey(const Key('playback-error-details')), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });
}

typedef NamedFailureRecord = ({String key, ApiFailure? detail});

/// What the real adapter really put in `raw` for a missing file, copied from a
/// run of the assertions above rather than invented here.
const rawFromRealAdapter =
    'UnimplementedError: init() has not been implemented.';

Widget _app({
  required DesktopPlayerAdapter adapter,
  required String status,
  required bool statusIsError,
  required void Function(BuildContext) onContext,
  ApiFailure? statusFailure,
}) => MaterialApp(
  theme: ListenTheme.dark(),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Builder(
      builder: (context) {
        onContext(context);
        return Column(
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
              statusFailure: statusFailure,
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
          ],
        );
      },
    ),
  ),
);
