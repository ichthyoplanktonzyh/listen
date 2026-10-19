import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/coach_dashboard_controller.dart';
import 'package:llplayer_next/controllers/cold_start_marking_view_model.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/reading_controller.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/controllers/speaking_task_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_view_model.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/models/timeline.dart';

void main() {
  group('controller state snapshots', () {
    test('do not expose mutable list fields', () {
      final lists = <List<Object?>>[
        LearningState().phraseCandidates,
        PlayerState().audioTracks,
        ReadingState().paragraphs,
        DiffSide().adjudications,
        ReadingTaskState().draftPoints,
        RealtimeConversationState().items,
        ReviewState().queue,
        SemanticSearchState().hits,
        SubtitleState().subtitleResources,
        VocabularyState().words,
        WritingTaskState().findings,
        ColdStartMarkingState().candidates,
        CoachEvidenceFeed().items,
        HuntingState().targets,
        HuntingSessionState().occurrences,
      ];

      for (final values in lists) {
        expect(values.clear, throwsUnsupportedError);
      }
    });

    test('do not expose mutable map or set fields', () {
      final maps = <Map<Object?, Object?>>[
        LearningState().wordEntries,
        ReadingState().slicePlayCounts,
        ReadingTaskState().draftVerdicts,
        SubtitleState().pronunciationBySentence,
        WritingTaskState().decisions,
        CoachDashboardState().evidence,
        HuntingSessionState().perTargetPromptCount,
      ];
      final sets = <Set<Object?>>[
        SpeakingTaskState().confirmedTargetIds,
        HuntingSessionState().handledOccurrenceIds,
      ];

      for (final values in maps) {
        expect(values.clear, throwsUnsupportedError);
      }
      for (final values in sets) {
        expect(values.clear, throwsUnsupportedError);
      }
    });

    test('protect nested collection values', () {
      final state = SubtitleState(
        timingsBySentence: {'sentence': []},
        senseGroupsBySentence: {'sentence': []},
      );

      expect(
        state.timingsBySentence['sentence']!.clear,
        throwsUnsupportedError,
      );
      expect(
        state.senseGroupsBySentence['sentence']!.clear,
        throwsUnsupportedError,
      );
    });

    test('defensively copies constructor collections', () {
      final tracks = <SubtitleTrack>[
        const SubtitleTrack(id: 'track', cues: []),
      ];
      final translations = <String, String>{'cue': 'translation'};
      final confirmedIds = <String>{'target'};

      final subtitle = SubtitleState(subtitleResources: tracks);
      final reading = ReadingState(translationByAnchor: translations);
      final speaking = SpeakingTaskState(confirmedTargetIds: confirmedIds);

      tracks.clear();
      translations.clear();
      confirmedIds.clear();

      expect(subtitle.subtitleResources, hasLength(1));
      expect(reading.translationByAnchor, {'cue': 'translation'});
      expect(speaking.confirmedTargetIds, {'target'});
    });

    test('defensively copies nested constructor collections', () {
      final timings = <WordTiming>[
        const WordTiming(
          sentenceId: 'sentence',
          tokenIndex: 0,
          start: Duration.zero,
          end: Duration(milliseconds: 100),
          source: 'test',
          provider: 'test',
        ),
      ];
      final bySentence = <String, List<WordTiming>>{'sentence': timings};
      final state = SubtitleState(timingsBySentence: bySentence);

      timings.clear();
      bySentence.clear();

      expect(state.timingsBySentence['sentence'], hasLength(1));
    });
  });
}
