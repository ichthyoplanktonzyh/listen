import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/listening_session_menu.dart';
import 'package:llplayer_next/widgets/player/playback_controls.dart';

/// The transport carried three popup menus — listening session, chunks,
/// subtitles — and no A/B repeat, which is the one range control an intensive
/// listener actually reaches for. These pin what replaced them.
void main() {
  group('A/B repeat', () {
    testWidgets('says which of its three steps it is on', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Nothing marked yet.
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(_buttonLabel(tester), 'AB');
      expect(_tooltipOf(tester), 'AB 复读：标记起点');

      // A marked, waiting for B: the label changes, so a half-finished loop
      // is never invisible.
      await tester.pumpWidget(_harness(abAnchor: const Duration(seconds: 4)));
      await tester.pumpAndSettle();
      expect(_buttonLabel(tester), 'A•');
      expect(_tooltipOf(tester), 'AB 复读：标记终点');

      // Looping: the next click clears it.
      await tester.pumpWidget(
        _harness(sourceLoopStart: const Duration(seconds: 4)),
      );
      await tester.pumpAndSettle();
      expect(_buttonLabel(tester), 'AB');
      expect(_tooltipOf(tester), 'AB 复读：取消');
    });

    testWidgets('every click reports to one handler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var marks = 0;
      await tester.pumpWidget(_harness(onMarkAbPoint: () => marks += 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playback-ab-loop')));
      await tester.pumpAndSettle();
      expect(marks, 1);
    });
  });

  group('transport menus', () {
    testWidgets('the listening session is no longer on the transport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // A session that spans a whole sitting does not belong beside controls
      // that act on the next 200ms; it moved to the session header.
      expect(find.text('泛听'), findsNothing);
      // And the subtitle menu of three checkboxes became one toggle.
      expect(find.text('字幕'), findsNothing);
      expect(find.byIcon(Icons.subtitles_outlined), findsOneWidget);
    });

    testWidgets('the subtitle toggle reports the flip', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flips = <bool>[];
      await tester.pumpWidget(
        _harness(subtitlesVisible: true, onSubtitlesVisibleChanged: flips.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.subtitles_outlined));
      expect(flips, [false]);
    });
  });

  group('ListeningSessionMenu', () {
    testWidgets('marking needs a sentence to attach to', (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _menuHarness(
          const ListeningSessionMenu(
            active: false,
            huntingActive: false,
            markEnabled: false,
            inboxCount: 0,
            onToggleListening: _noop,
            onToggleHunting: _noop,
            onCaptureInbox: _noop,
            onHardInterrupt: _noop,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('listening-session-menu')));
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .where((item) => item.value != null);
      for (final item in items) {
        // Starting the session needs nothing; the other three attach to the
        // sentence being played.
        expect(
          item.enabled,
          item.value == 'toggle-listening',
          reason: '${item.value}',
        );
      }
    });

    testWidgets('the inbox count rides on the control itself', (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _menuHarness(
          const ListeningSessionMenu(
            active: true,
            huntingActive: false,
            markEnabled: true,
            inboxCount: 3,
            onToggleListening: _noop,
            onToggleHunting: _noop,
            onCaptureInbox: _noop,
            onHardInterrupt: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('listening-inbox-badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('viewing the box opens once there is something marked', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var viewed = 0;
      await tester.pumpWidget(
        _menuHarness(
          ListeningSessionMenu(
            active: true,
            huntingActive: false,
            markEnabled: true,
            inboxCount: 2,
            onToggleListening: _noop,
            onToggleHunting: _noop,
            onCaptureInbox: _noop,
            onHardInterrupt: _noop,
            onViewInbox: () => viewed++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('listening-session-menu')));
      await tester.pumpAndSettle();

      final view = tester.widget<PopupMenuItem<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'view-inbox',
        ),
      );
      expect(view.enabled, isTrue);

      await tester.tap(find.text('查看泛听收集箱'));
      await tester.pumpAndSettle();
      expect(viewed, 1);
    });

    testWidgets('viewing is disabled while the box is empty', (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _menuHarness(
          ListeningSessionMenu(
            active: true,
            huntingActive: false,
            markEnabled: true,
            inboxCount: 0,
            onToggleListening: _noop,
            onToggleHunting: _noop,
            onCaptureInbox: _noop,
            onHardInterrupt: _noop,
            onViewInbox: _noop,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('listening-session-menu')));
      await tester.pumpAndSettle();

      final view = tester.widget<PopupMenuItem<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'view-inbox',
        ),
      );
      expect(view.enabled, isFalse);
    });
  });
}

void _noop() {}

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('playback-ab-loop')),
        matching: find.byType(Text),
      ),
    )
    .data!;

String _tooltipOf(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('playback-ab-loop')),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

Widget _harness({
  Duration? abAnchor,
  Duration? sourceLoopStart,
  bool subtitlesVisible = true,
  VoidCallback? onMarkAbPoint,
  ValueChanged<bool>? onSubtitlesVisibleChanged,
}) {
  final adapter = DesktopPlayerAdapter();
  return _wrap(
    PlaybackControls(
      adapter: adapter,
      position: const AlwaysStoppedAnimation<Duration>(Duration(seconds: 15)),
      duration: const Duration(minutes: 10),
      playing: false,
      loopCue: false,
      sourceLoopStart: sourceLoopStart,
      statusStylesVisible: true,
      subtitlesVisible: subtitlesVisible,
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
      status: '',
      taskStatuses: const [],
      chunkControlsEnabled: true,
      chunkLoopActive: false,
      abAnchor: abAnchor,
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
      onSubtitlesVisibleChanged: onSubtitlesVisibleChanged ?? (_) {},
      onSecondaryVisibleChanged: (_) {},
      onRateChanged: (_) {},
      onVolumeChanged: (_) {},
      onMuteToggle: () {},
      onAudioTrackChanged: (_) {},
      onEmbeddedSubtitleTrackChanged: (_) {},
      onPrimaryOffsetChanged: (_) {},
      onSecondaryOffsetChanged: (_) {},
      onMarkAbPoint: onMarkAbPoint ?? () {},
    ),
  );
}

Widget _menuHarness(Widget child) =>
    _wrap(Align(alignment: Alignment.topLeft, child: child));

Widget _wrap(Widget child) => MaterialApp(
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
