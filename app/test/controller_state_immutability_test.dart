import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_view_model.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/models/timeline.dart';

void main() {
  group('controller state snapshots', () {
    test('do not expose mutable list fields', () {
      final lists = <List<Object?>>[
        LearningState().phraseCandidates,
        PlayerState().audioTracks,
        ReviewState().queue,
        SemanticSearchState().hits,
        SubtitleState().subtitleResources,
        VocabularyState().words,
        HuntingState().targets,
        HuntingSessionState().occurrences,
      ];

      for (final values in lists) {
        expect(values.clear, throwsUnsupportedError);
      }
    });

    test('do not expose mutable maps or sets', () {
      final maps = <Map<Object?, Object?>>[
        LearningState().wordEntries,
        SubtitleState().pronunciationBySentence,
        HuntingSessionState().perTargetPromptCount,
      ];
      final sets = <Set<Object?>>[HuntingSessionState().handledOccurrenceIds];

      for (final values in maps) {
        expect(values.clear, throwsUnsupportedError);
      }
      for (final values in sets) {
        expect(values.clear, throwsUnsupportedError);
      }
    });

    test('protects nested subtitle analysis collections', () {
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
      final words = <String, LexicalEntry>{
        'word': const LexicalEntry(
          id: 'word',
          normalizedForm: 'word',
          displayForm: 'word',
          kind: 'word',
          status: 'known_recognized',
          language: 'en',
        ),
      };

      final subtitle = SubtitleState(subtitleResources: tracks);
      final learning = LearningState(wordEntries: words);

      tracks.clear();
      words.clear();

      expect(subtitle.subtitleResources, hasLength(1));
      expect(learning.wordEntries, contains('word'));
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
