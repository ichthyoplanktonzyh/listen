import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/practice_actions_coordinator.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';

({
  PracticeActionsCoordinator coordinator,
  PlayerController player,
  int Function() diagnosisCalls,
  List<Cue?> Function() seeks,
})
_wire() {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final adapter = DesktopPlayerAdapter();
  final recordingAdapter = DesktopPlayerAdapter();
  final playback =
      PlaybackActionsCoordinator(
        adapter: adapter,
        player: player,
        subtitle: subtitle,
      )..bind(
        getApi: () => null,
        isMounted: () => true,
        reloadLearningEntries: () async {},
      );
  final practice = PracticeController();
  final slicePlayer = SlicePlayerController();
  var diagnosis = 0;
  final seeks = <Cue?>[];
  final coordinator =
      PracticeActionsCoordinator(
        practice: practice,
        player: player,
        subtitle: subtitle,
        learning: LearningController(),
        slicePlayer: slicePlayer,
        playbackActions: playback,
        settings: SettingsController(),
        adapter: adapter,
        recordingAdapter: recordingAdapter,
      )..bind(
        getApi: () => null,
        isMounted: () => true,
        refreshDiagnosis: () async => diagnosis++,
        seekCue: (cue) async => seeks.add(cue),
      );
  addTearDown(adapter.dispose);
  addTearDown(recordingAdapter.dispose);
  addTearDown(practice.dispose);
  addTearDown(slicePlayer.dispose);
  return (
    coordinator: coordinator,
    player: player,
    diagnosisCalls: () => diagnosis,
    seeks: () => seeks,
  );
}

void main() {
  test('replayPracticeWindow is a no-op without an active draft', () async {
    final w = _wire();

    await w.coordinator.replayPracticeWindow();

    expect(w.player.sourceLoopStart, isNull);
    expect(w.player.sourceLoopEnd, isNull);
  });

  test('submitPractice always refreshes diagnosis afterwards', () async {
    final w = _wire();

    await w.coordinator.submitPractice();

    expect(w.diagnosisCalls(), 1);
  });

  test('navigatePracticeSentence does not seek without a target cue', () async {
    final w = _wire();

    await w.coordinator.navigatePracticeSentence(1);

    expect(w.seeks(), isEmpty);
  });

  test(
    'savePracticeReview leaves status unchanged without an attempt',
    () async {
      final w = _wire();
      final before = w.player.status;

      await w.coordinator.savePracticeReview();

      expect(w.player.status, before);
    },
  );
}
