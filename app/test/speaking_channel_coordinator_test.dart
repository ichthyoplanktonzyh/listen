import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/speaking_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speaking_channel_coordinator.dart';
import 'package:llplayer_next/controllers/speaking_task_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/player_adapter.dart';

LexicalEntry _entry(String id, String displayForm) => LexicalEntry(
  id: id,
  normalizedForm: displayForm.toLowerCase(),
  displayForm: displayForm,
  kind: 'word',
  language: 'en',
);

class _Harness {
  _Harness() {
    coordinator.bind(
      getApi: () => null,
      isMounted: () => true,
      askPersonalExpressionAssessment: () async {
        assessmentsAsked++;
        return 'expressed';
      },
      onReturnToReview: () => returns.add('review'),
      onReturnToPersonalExpression: () => returns.add('personal-expression'),
    );
  }

  int assessmentsAsked = 0;
  final returns = <String>[];

  final subtitle = SubtitleController();
  final player = PlayerController();
  final settings = SettingsController();
  final slicePlayer = SlicePlayerController();
  final task = SpeakingTaskController();
  final readingTask = ReadingTaskController();
  final realtime = RealtimeConversationController();
  final learning = LearningController();

  late final actions = SpeakingActionsCoordinator(
    task: task,
    player: player,
    subtitle: subtitle,
    settings: settings,
    slicePlayer: slicePlayer,
    adapter: DesktopPlayerAdapter(),
    recordingAdapter: DesktopPlayerAdapter(),
  );

  late final coordinator = SpeakingChannelCoordinator(
    actions: actions,
    task: task,
    readingTask: readingTask,
    realtimeConversation: realtime,
    learning: learning,
    player: player,
  );

  void dispose() {
    coordinator.dispose();
    actions.dispose();
    task.dispose();
    readingTask.dispose();
    realtime.dispose();
    learning.dispose();
    subtitle.dispose();
    player.dispose();
    settings.dispose();
    slicePlayer.dispose();
  }
}

void main() {
  group('target candidates', () {
    test('match on word boundaries, not on substrings', () {
      final harness = _Harness();
      harness.learning.setWordEntries({
        'a': _entry('a', 'cat'),
        'b': _entry('b', 'catalogue'),
        'c': _entry('c', 'dog'),
      });
      harness.task.store.replace(
        const SpeakingTaskState(
          correctedTranscript: 'The cat sat down.',
          asrReliability: 'reliable',
        ),
      );
      expect(
        harness.coordinator.targetCandidates().map(
          (candidate) => candidate.surfaceForm,
        ),
        ['cat'],
      );
      harness.dispose();
    });

    test('non-ASCII targets match by substring', () {
      final harness = _Harness();
      harness.learning.setWordEntries({'a': _entry('a', '天気')});
      harness.task.store.replace(
        const SpeakingTaskState(
          correctedTranscript: '今日は天気がいい',
          asrReliability: 'reliable',
        ),
      );
      expect(harness.coordinator.targetCandidates(), hasLength(1));
      harness.dispose();
    });

    test('an unreliable transcript is never evidence of production', () {
      final harness = _Harness();
      harness.learning.setWordEntries({'a': _entry('a', 'cat')});
      harness.task.store.replace(
        const SpeakingTaskState(
          correctedTranscript: 'The cat sat down.',
          asrReliability: 'unreliable',
        ),
      );
      expect(harness.coordinator.targetCandidates(), isEmpty);
      harness.dispose();
    });
  });

  group('surfaces', () {
    test('realtime conversation needs a source and an ASR model', () {
      final harness = _Harness();
      harness.coordinator.openRealtimeConversation();
      expect(harness.coordinator.realtimeConversationOpen, isFalse);
      harness.dispose();
    });

    test('closing the realtime panel when it is shut is a no-op', () async {
      final harness = _Harness();
      await harness.coordinator.closeRealtimeConversation();
      expect(harness.coordinator.realtimeConversationOpen, isFalse);
      harness.dispose();
    });

    test('closing the L1 check without one open leaves the task alone', () {
      final harness = _Harness();
      harness.readingTask.store.replace(
        const ReadingTaskState(phase: 'answering'),
      );
      harness.coordinator.closeL1Check();
      // closeTask would have reset the phase; the guard kept it untouched.
      expect(harness.readingTask.state.phase, 'answering');
      harness.dispose();
    });

    test('the L1 check needs a speaking source and a rubric', () async {
      final harness = _Harness();
      await harness.coordinator.openL1Check();
      expect(harness.coordinator.l1CheckSource, isNull);
      harness.dispose();
    });
  });

  group('closing the surface', () {
    test('a plain session asks nothing and returns nowhere', () async {
      final harness = _Harness();
      await harness.coordinator.closeSurface();
      expect(harness.assessmentsAsked, 0);
      expect(harness.returns, isEmpty);
      harness.dispose();
    });

    test('an unfinished personal-expression session is not filed', () async {
      final harness = _Harness();
      harness.coordinator.activePersonalPattern = null;
      harness.task.store.replace(const SpeakingTaskState(phase: 'recording'));
      await harness.coordinator.closeSurface();
      expect(harness.assessmentsAsked, 0);
      harness.dispose();
    });
  });
}
