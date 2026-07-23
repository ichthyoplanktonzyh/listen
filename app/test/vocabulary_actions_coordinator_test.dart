import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_actions_coordinator.dart';
import 'package:llplayer_next/services/api_service.dart';

/// A core that answers nothing: guards that fire before any request keep it
/// untouched, which is exactly what these tests assert.
LocalApi _idleApi() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => (statusCode: 200, body: '{}'),
);

({
  VocabularyActionsCoordinator coordinator,
  PlayerController player,
  int Function() diagnosisCalls,
})
_wire({LocalApi? Function()? getApi}) {
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
        getApi: getApi ?? () => null,
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
    'markFirstWord without a core reports it and skips the diagnosis refresh',
    () async {
      final w = _wire();

      await w.coordinator.markFirstWord('known_recognized');

      expect(w.player.status, 'statusConnectLocalCoreFirst');
      expect(w.diagnosisCalls(), 0);
    },
  );

  test('observeSelected without a core reports it', () async {
    final w = _wire();

    await w.coordinator.observeSelected(true);

    expect(w.player.status, 'statusConnectLocalCoreFirst');
    expect(w.diagnosisCalls(), 0);
  });

  test('observeSelected without a selection is a silent no-op', () async {
    final w = _wire(getApi: _idleApi);
    final before = w.player.status;

    await w.coordinator.observeSelected(true);

    expect(w.player.status, before);
    expect(w.diagnosisCalls(), 0);
  });
}
