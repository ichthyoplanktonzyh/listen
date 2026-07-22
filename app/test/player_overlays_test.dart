import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_actions_coordinator.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/practice_actions_coordinator.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/widgets/panels/hunting_prompt_card.dart';
import 'package:llplayer_next/widgets/layout/player_overlays.dart';

class _Harness {
  final subtitle = SubtitleController();
  final player = PlayerController();
  final settings = SettingsController();
  final learning = LearningController();
  final practice = PracticeController();
  final slicePlayer = SlicePlayerController();
  final huntingSession = HuntingSessionController();
  final extensive = ExtensiveListeningController();
  final adapter = DesktopPlayerAdapter();

  late final playback = PlaybackActionsCoordinator(
    adapter: adapter,
    player: player,
    subtitle: subtitle,
  );

  late final practiceActions = PracticeActionsCoordinator(
    practice: practice,
    player: player,
    subtitle: subtitle,
    learning: learning,
    slicePlayer: slicePlayer,
    playbackActions: playback,
    settings: settings,
    adapter: adapter,
    recordingAdapter: DesktopPlayerAdapter(),
  );

  late final huntingActions = HuntingActionsCoordinator(
    huntingSession: huntingSession,
    player: player,
    extensiveListening: extensive,
    subtitle: subtitle,
  );

  Widget get widget => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(child: ColoredBox(color: Colors.black)),
          PlayerOverlays(
            api: null,
            practiceController: practice,
            slicePlayerController: slicePlayer,
            huntingSessionController: huntingSession,
            subtitleController: subtitle,
            playerController: player,
            practiceActions: practiceActions,
            huntingActions: huntingActions,
            onCloseSlicePlayback: () async {},
          ),
        ],
      ),
    ),
  );

  void dispose() {
    practice.dispose();
    slicePlayer.dispose();
    huntingSession.dispose();
    extensive.dispose();
    subtitle.dispose();
    player.dispose();
    settings.dispose();
    learning.dispose();
  }
}

void main() {
  testWidgets('overlays span the whole workbench stack, not a collapsed box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = _Harness();
    await tester.pumpWidget(harness.widget);

    // The overlay layer wraps its own Stack in Positioned.fill; without that
    // the inner Stack holds only positioned children and collapses to zero,
    // taking the hunting prompt and both windows off screen.
    final overlayStack = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byType(PlayerOverlays),
        matching: find.byType(Stack),
      ),
    );
    expect(overlayStack.size, const Size(1200, 900));

    // The prompt card keeps its 24px inset against that full-size box.
    final promptCard = tester.getTopLeft(find.byType(HuntingPromptCard));
    expect(promptCard.dy, 18);
    harness.dispose();
  });
}
