import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/widgets/flows/subtitle_resource_flows.dart';

ResourceActionsCoordinator _resourceActions() =>
    ResourceActionsCoordinator(
      player: PlayerController(),
      subtitle: SubtitleController(),
      speechEnhancement: SpeechEnhancementWorkflowController(),
      repository: LocalResourceRepository(() => null),
    )..bind(
      isMounted: () => true,
      reloadSpeechEnhancements: (_) async {},
      activatePrimaryTrack: (_, {required nextStatus}) async {},
      reloadLearningEntries: () async {},
    );

void main() {
  testWidgets('cold-start flow without a factory reports missing core', (
    tester,
  ) async {
    final player = PlayerController();
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openColdStartMarkingFlow(
                context: context,
                createViewModel: null,
                playerController: player,
                subtitleController: SubtitleController(),
                resourceActions: _resourceActions(),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(player.status, 'Connect the local core first');
  });
}
