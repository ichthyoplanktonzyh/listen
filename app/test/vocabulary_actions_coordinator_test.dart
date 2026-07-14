import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_actions_coordinator.dart';

({
  VocabularyActionsCoordinator coordinator,
  PlayerController player,
  int Function() diagnosisCalls,
})
_wire() {
  final player = PlayerController();
  var diagnosis = 0;
  final coordinator =
      VocabularyActionsCoordinator(
        workflow: LearningWorkflowController(),
        learning: LearningController(),
        subtitle: SubtitleController(),
        settings: SettingsController(),
        player: player,
      )..bind(
        getApi: () => null,
        isMounted: () => true,
        text: (key) => key,
        refreshDiagnosis: () async => diagnosis++,
      );
  return (
    coordinator: coordinator,
    player: player,
    diagnosisCalls: () => diagnosis,
  );
}

void main() {
  test(
    'markFirstWord refreshes diagnosis even when nothing is marked',
    () async {
      final w = _wire();

      await w.coordinator.markFirstWord('known_recognized');

      expect(w.diagnosisCalls(), 1);
    },
  );

  test('observeSelected without a selection is a silent no-op', () async {
    final w = _wire();
    final before = w.player.status;

    await w.coordinator.observeSelected(true);

    expect(w.player.status, before);
    expect(w.diagnosisCalls(), 0);
  });
}
