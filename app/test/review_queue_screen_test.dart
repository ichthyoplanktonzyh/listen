import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/screens/review_queue_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:video_player/video_player.dart';

/// A no-op second decoder so a review clip can "play" without opening a real
/// video_player instance.
class _FakeSlicePlaybackAdapter implements SlicePlaybackAdapter {
  bool playing = false;
  bool disposed = false;

  @override
  VideoPlayerController? get videoController => null;
  @override
  bool get isPlaying => playing;
  @override
  Future<Duration?> readPosition() async => Duration.zero;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRate(double rate) async {}
}

/// A resolver that never touches the disk. [reachable] decides whether the
/// linked media's file is found (resolves) or not (falls through to the file
/// picker, which returns null → an explicit "not selected" failure).
OccurrenceMediaResolver _fakeResolver({bool reachable = true}) =>
    OccurrenceMediaResolver(
      readMedia: (id) async => MediaItem(
        id: id,
        path: '/fake/$id.mp4',
        fingerprint: 'fp-$id',
        title: 'Source $id',
        kind: 'video',
        durationMs: 12000,
        availability: 'available',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
      fingerprintFile: (_) async => 'fp',
      registerMedia: (_) async {},
      pickFile: (_) async => null,
      fileExists: (_) async => reachable,
    );

Map<String, dynamic> _reviewItem({
  required String id,
  required String kind,
  String? cue,
  required String answer,
  String? target,
  String? mediaId,
  List<Map<String, dynamic>> anchors = const [],
}) => {
  'item': {
    'id': id,
    'source': {
      'kind': 'sentence',
      'id': 'sentence-1',
      'practice_attempt_id': null,
      'lexical_entry_id': null,
      'media_id': mediaId,
      'track_id': mediaId == null ? null : 'track-1',
    },
    'anchors': anchors,
    'prompt_snapshot': answer,
    'status': 'active',
    'created_at_ms': 1,
    'updated_at_ms': 1,
  },
  'schedule': {
    'item_id': id,
    'algorithm': 'listen_review_v1_heuristic_proxy',
    'due_at_ms': 1,
    'stability': null,
    'difficulty': null,
    'interval_days': null,
    'lapse_count': 0,
  },
  'card': {'kind': kind, 'cue': cue, 'answer': answer, 'target': target},
};

Map<String, dynamic> _submission(String rating) => {
  'attempt': {
    'id': 'attempt-1',
    'item_id': 'review-playback-1',
    'reviewed_at_ms': 2,
    'rating': rating,
    'practice_attempt_id': null,
    'next_due_at_ms': null,
  },
  'schedule': {
    'item_id': 'review-playback-1',
    'algorithm': 'listen_review_v1_heuristic_proxy',
    'due_at_ms': 2,
    'stability': null,
    'difficulty': null,
    'interval_days': null,
    'lapse_count': 0,
  },
  'generated_observation_ids': const [],
  'hunting_candidate_ids': const [],
  'upgrade_suggestions': const [],
};

const _bounded = [
  {
    'kind': 'sentence',
    'id': 'sentence-1',
    'label': 'en',
    'lexical_entry_id': null,
    'sentence_id': 'sentence-1',
    'token_start': null,
    'token_end': null,
    'start_ms': 1000,
    'end_ms': 3000,
  },
];

void main() {
  for (final scenario
      in <
        ({String kind, String cue, String answer, String target, String action})
      >[
        (
          kind: 'word_recognition',
          cue: '',
          answer: 'would',
          target: 'would',
          action: 'Show the word',
        ),
        (
          kind: 'chunk_cloze',
          cue: 'I ____ gone',
          answer: 'I would have gone',
          target: 'would have',
          action: 'Check answer',
        ),
        (
          kind: 'phrase_presence',
          cue: 'would have',
          answer: 'I would have gone',
          target: 'would have',
          action: 'Present',
        ),
        (
          kind: 'source_sentence_recall',
          cue: '',
          answer: 'I would have gone',
          target: '',
          action: 'Show the sentence',
        ),
      ]) {
    testWidgets('${scenario.kind} exposes its distinct review interaction', (
      tester,
    ) async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          if (path != '/v1/review/items?limit=20') {
            throw StateError('unexpected $method $path');
          }
          return (
            statusCode: 200,
            body: jsonEncode([
              _reviewItem(
                id: 'review-${scenario.kind}',
                kind: scenario.kind,
                cue: scenario.cue.isEmpty ? null : scenario.cue,
                answer: scenario.answer,
                target: scenario.target.isEmpty ? null : scenario.target,
              ),
            ]),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewQueueScreen(
            api: api,
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (scenario.kind == 'chunk_cloze') {
        expect(find.text(scenario.cue), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'would have');
      } else if (scenario.kind == 'phrase_presence') {
        expect(find.text(scenario.target), findsOneWidget);
      }

      await tester.tap(find.text(scenario.action));
      await tester.pumpAndSettle();

      expect(find.text(scenario.answer), findsOneWidget);
      // R5: four grades, Again/Hard/Good/Easy.
      expect(find.text('Missed it'), findsOneWidget);
      expect(find.text('Fuzzy'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
    });
  }

  testWidgets(
    'delayed retelling shows a prompt instead of collapsing, and enters '
    'speaking',
    (tester) async {
      var launched = false;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          return (
            statusCode: 200,
            body: jsonEncode([
              _reviewItem(
                id: 'review-speaking-1',
                kind: 'delayed_retelling',
                answer: 'The ferry leaves on Tuesday.',
                mediaId: 'media-1',
                anchors: const [
                  {
                    'kind': 'sentence',
                    'id': 'cue-1',
                    'label': 'en',
                    'lexical_entry_id': null,
                    'sentence_id': 'cue-1',
                    'token_start': null,
                    'token_end': null,
                    'start_ms': 1000,
                    'end_ms': 12000,
                  },
                ],
              ),
            ]),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewQueueScreen(
            api: api,
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async => launched = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // R3: the card no longer collapses to an empty box; it frames the task.
      expect(
        find.text('Source hidden · retell from memory, then start speaking.'),
        findsOneWidget,
      );
      expect(find.text('Start delayed retelling'), findsOneWidget);
      expect(find.text('Show the sentence'), findsNothing);
      await tester.tap(find.text('Start delayed retelling'));
      await tester.pumpAndSettle();
      expect(launched, isTrue);
    },
  );

  testWidgets(
    'R1: a source clip plays on its own decoder with no media loaded, and '
    'toggles in place',
    (tester) async {
      final adapter = _FakeSlicePlaybackAdapter();
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          if (path != '/v1/review/items?limit=20') {
            throw StateError('unexpected $method $path');
          }
          return (
            statusCode: 200,
            body: jsonEncode([
              _reviewItem(
                id: 'review-playback-1',
                kind: 'source_sentence_recall',
                answer: 'A bounded source sentence.',
                mediaId: 'media-1',
                anchors: _bounded,
              ),
            ]),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          // No currentMediaId is even accepted anymore: the clip is decoupled
          // from the main player entirely.
          home: ReviewQueueScreen(
            api: api,
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async {},
            resolver: _fakeResolver(),
            createSlicePlaybackAdapter: (_) async => adapter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      // The clip resolves and opens asynchronously; a periodic poll then keeps
      // the second decoder running, so settle by hand rather than pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(adapter.playing, isTrue);
      expect(
        find.byIcon(Icons.pause),
        findsOneWidget,
        reason: 'The same review card must expose an in-place pause action.',
      );

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(milliseconds: 60));
      expect(adapter.playing, isFalse);
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    },
  );

  testWidgets('R1: an unreachable source reports the failure in place', (
    tester,
  ) async {
    final adapter = _FakeSlicePlaybackAdapter();
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path ==
            '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
          return (statusCode: 200, body: '[]');
        }
        return (
          statusCode: 200,
          body: jsonEncode([
            _reviewItem(
              id: 'review-playback-1',
              kind: 'source_sentence_recall',
              answer: 'A bounded source sentence.',
              mediaId: 'media-1',
              anchors: _bounded,
            ),
          ]),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          api: api,
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
          resolver: _fakeResolver(reachable: false),
          createSlicePlaybackAdapter: (_) async => adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(adapter.playing, isFalse);
    // Honest in-place failure, not a grayed-out whole card.
    expect(find.text('Source media was not selected'), findsOneWidget);
  });

  testWidgets('R5: pressing Easy submits the fourth rating to the backend', (
    tester,
  ) async {
    String? submittedRating;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path ==
            '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
          return (statusCode: 200, body: '[]');
        }
        if (path == '/v1/review/attempts') {
          final decoded = jsonDecode(body!) as Map<String, dynamic>;
          submittedRating = decoded['rating'] as String?;
          return (statusCode: 200, body: jsonEncode(_submission('easy')));
        }
        return (
          statusCode: 200,
          body: jsonEncode([
            _reviewItem(
              id: 'review-playback-1',
              kind: 'source_sentence_recall',
              answer: 'A bounded source sentence.',
            ),
          ]),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          api: api,
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show the sentence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();

    expect(submittedRating, 'easy');
  });

  testWidgets('finished queue shows a non-blocking upgrade suggestion', (
    tester,
  ) async {
    final requests = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        requests.add('$method $path');
        if (path == '/v1/review/items?limit=20') {
          return (statusCode: 200, body: '[]');
        }
        if (path ==
            '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
          return (statusCode: 200, body: jsonEncode([upgradeSuggestionJson]));
        }
        if (path == '/v1/review/upgrade-suggestions/suggestion-1/reject') {
          return (
            statusCode: 200,
            body: jsonEncode({...upgradeSuggestionJson, 'status': 'rejected'}),
          );
        }
        throw StateError('unexpected $method $path');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          api: api,
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('heard in 5 contexts'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(
      requests.last,
      'POST /v1/review/upgrade-suggestions/suggestion-1/reject',
    );
    expect(find.textContaining('heard in 5 contexts'), findsNothing);
  });
}

const upgradeSuggestionJson = <String, dynamic>{
  'id': 'suggestion-1',
  'lexical_entry_id': 'lexical-1',
  'lexical_display_form': 'would have',
  'previous_status': 'known_not_recognized',
  'suggested_status': 'known_recognized',
  'status': 'pending',
  'evidence_context_count': 5,
  'evidence_ids': ['evidence-1'],
  'threshold': 5,
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 1,
  'resolved_at_ms': null,
  'cooldown_until_ms': null,
};
