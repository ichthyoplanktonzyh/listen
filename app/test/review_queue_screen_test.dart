import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/data/repositories/occurrence_media_repository.dart';
import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/screens/review_queue_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/occurrence_media_file_service.dart';

/// A no-op second decoder so a review clip can "play" without opening a real
/// video_player instance.
class _FakeSlicePlaybackAdapter implements SlicePlaybackAdapter {
  bool playing = false;
  bool disposed = false;

  @override
  SlicePlaybackRenderHandle? get renderHandle => null;
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

class _ResolverRepository implements OccurrenceMediaRepository {
  @override
  Future<MediaItem> readMedia(String id) async => MediaItem(
    id: id,
    path: '/fake/$id.mp4',
    fingerprint: 'fp-$id',
    title: 'Source $id',
    kind: 'video',
    durationMs: 12000,
    availability: 'available',
    createdAtMs: 1,
    updatedAtMs: 1,
  );

  @override
  Future<String> fingerprintFile(String path) async => 'fp';

  @override
  Future<void> registerMedia(String path) async {}
}

class _ResolverFileService implements OccurrenceMediaFileService {
  _ResolverFileService(this.reachable);

  final bool reachable;

  @override
  Future<bool> exists(String path) async => reachable;

  @override
  Future<String?> pickSourceMedia({
    required bool filterMediaExtensions,
  }) async => null;
}

/// A resolver that never touches the disk. [reachable] decides whether the
/// linked media's file is found (resolves) or not (falls through to the file
/// picker, which returns null → an explicit "not selected" failure).
OccurrenceMediaResolver _fakeResolver({bool reachable = true}) =>
    OccurrenceMediaResolver(
      repository: _ResolverRepository(),
      fileService: _ResolverFileService(reachable),
    );

Map<String, dynamic> _reviewItem({
  required String id,
  required String kind,
  String? cue,
  required String answer,
  String? target,
  String? mediaId,
  List<Map<String, dynamic>> anchors = const [],
  double? intervalDays,
  int lapseCount = 0,
  String state = 'new',
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
    'interval_days': intervalDays,
    'lapse_count': lapseCount,
  },
  'state': state,
  'card': {'kind': kind, 'cue': cue, 'answer': answer, 'target': target},
  'origin': {
    'kind': 'native',
    'anki_guid': null,
    'deck_id': null,
    'deck_name': null,
    'has_listening_enhancements': true,
  },
};

/// The `/v1/review/queue` envelope: entries plus the daily-budget status that
/// explains a short or empty queue. [limitStatus] defaults to a budget nothing
/// has run into.
Map<String, dynamic> _queueBody(
  List<Map<String, dynamic>> entries, {
  Map<String, dynamic>? limitStatus,
}) => {
  'entries': entries,
  'limit_status':
      limitStatus ??
      {
        'limits': {'new_cards': 20, 'reviews': 200},
        'new_completed': 0,
        'reviews_completed': 0,
        'new_limit_reached': false,
        'review_limit_reached': false,
      },
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
  'generated_observation_ids': const <dynamic>[],
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
          if (path.endsWith('/interval-preview')) {
            return (statusCode: 200, body: '[]');
          }
          if (path != '/v1/review/queue?limit=20') {
            throw StateError('unexpected $method $path');
          }
          return (
            statusCode: 200,
            body: jsonEncode(
              _queueBody([
                _reviewItem(
                  id: 'review-${scenario.kind}',
                  kind: scenario.kind,
                  cue: scenario.cue.isEmpty ? null : scenario.cue,
                  answer: scenario.answer,
                  target: scenario.target.isEmpty ? null : scenario.target,
                ),
              ]),
            ),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewQueueScreen(
            controller: ReviewController(LocalReviewRepository(api)),
            resolver: _fakeResolver(),
            slicePlayer: SlicePlayerController(),
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

  // S11: the head names the state the FSRS scheduler reports in the entry's
  // `state` field. It used to print "New card" for every card with zero
  // lapses — including a card reviewed for months and never once forgotten,
  // which is a false statement about what the learner is looking at, not a
  // styling gap. The `review`/0-lapse row below is exactly that case. The
  // interval beside it comes from `interval_days`, which the backend has
  // always sent and the head threw away.
  for (final scenario
      in <
        ({
          String state,
          double? intervalDays,
          int lapseCount,
          String label,
          String? detail,
        })
      >[
        (
          state: 'new',
          intervalDays: null,
          lapseCount: 0,
          label: 'New card',
          detail: null,
        ),
        (
          state: 'learning',
          intervalDays: 0.007,
          lapseCount: 0,
          label: 'Learning',
          detail: 'Interval 10 min',
        ),
        (
          state: 'relearning',
          intervalDays: 0.007,
          lapseCount: 2,
          label: 'Relearning',
          detail: 'Interval 10 min · Relearn 2',
        ),
        (
          state: 'review',
          intervalDays: 9,
          lapseCount: 0,
          label: 'In review',
          detail: 'Interval 9 d',
        ),
      ]) {
    testWidgets(
      'a "${scenario.state}" card with ${scenario.lapseCount} lapses reads as '
      '"${scenario.label}"',
      (tester) async {
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            return (
              statusCode: 200,
              body: jsonEncode(
                _queueBody([
                  _reviewItem(
                    id: 'review-state-1',
                    kind: 'word_recognition',
                    answer: 'would',
                    intervalDays: scenario.intervalDays,
                    lapseCount: scenario.lapseCount,
                    state: scenario.state,
                  ),
                ]),
              ),
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ReviewQueueScreen(
              controller: ReviewController(LocalReviewRepository(api)),
              resolver: _fakeResolver(),
              slicePlayer: SlicePlayerController(),
              onStartShadowing: (_) async {},
              onStartDelayedRetelling: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.label), findsOneWidget);
        if (scenario.state != 'new') {
          // The regression this whole group exists for.
          expect(find.text('New card'), findsNothing);
        }
        if (scenario.detail == null) {
          // No interval yet — the head says nothing rather than rounding a
          // missing number down to "0 d".
          expect(find.textContaining('Interval'), findsNothing);
        } else {
          expect(find.text(scenario.detail!), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'R1: a source clip plays on its own decoder with no media loaded, and '
    'toggles in place',
    (tester) async {
      final adapter = _FakeSlicePlaybackAdapter();
      final slicePlayer = SlicePlayerController(
        createAdapter: (_) async => adapter,
      );
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path.endsWith('/interval-preview')) {
            return (statusCode: 200, body: '[]');
          }
          if (path != '/v1/review/queue?limit=20') {
            throw StateError('unexpected $method $path');
          }
          return (
            statusCode: 200,
            body: jsonEncode(
              _queueBody([
                _reviewItem(
                  id: 'review-playback-1',
                  kind: 'source_sentence_recall',
                  answer: 'A bounded source sentence.',
                  mediaId: 'media-1',
                  anchors: _bounded,
                ),
              ]),
            ),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          // No currentMediaId is even accepted anymore: the clip is decoupled
          // from the main player entirely.
          home: ReviewQueueScreen(
            controller: ReviewController(LocalReviewRepository(api)),
            resolver: _fakeResolver(),
            slicePlayer: slicePlayer,
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async {},
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
      await tester.pumpWidget(const SizedBox.shrink());
      slicePlayer.dispose();
    },
  );

  testWidgets('R1: an unreachable source reports the failure in place', (
    tester,
  ) async {
    final adapter = _FakeSlicePlaybackAdapter();
    final slicePlayer = SlicePlayerController(
      createAdapter: (_) async => adapter,
    );
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.endsWith('/interval-preview')) {
          return (statusCode: 200, body: '[]');
        }
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody([
              _reviewItem(
                id: 'review-playback-1',
                kind: 'source_sentence_recall',
                answer: 'A bounded source sentence.',
                mediaId: 'media-1',
                anchors: _bounded,
              ),
            ]),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(reachable: false),
          slicePlayer: slicePlayer,
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
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
    await tester.pumpWidget(const SizedBox.shrink());
    slicePlayer.dispose();
  });

  testWidgets('R5: pressing Easy submits the fourth rating to the backend', (
    tester,
  ) async {
    String? submittedRating;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.endsWith('/interval-preview')) {
          return (statusCode: 200, body: '[]');
        }
        if (path == '/v1/review/attempts') {
          final decoded = jsonDecode(body!) as Map<String, dynamic>;
          submittedRating = decoded['rating'] as String?;
          return (statusCode: 200, body: jsonEncode(_submission('easy')));
        }
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody([
              _reviewItem(
                id: 'review-playback-1',
                kind: 'source_sentence_recall',
                answer: 'A bounded source sentence.',
              ),
            ]),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(),
          slicePlayer: SlicePlayerController(),
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

  testWidgets('each grade carries the interval FSRS predicts for it', (
    tester,
  ) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path == '/v1/review/items/review-preview-1/interval-preview') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'rating': 'again',
                'due_at_ms': 600000,
                'interval_days': 0.007,
                'state': 'relearning',
              },
              {
                'rating': 'hard',
                'due_at_ms': 86400000,
                'interval_days': 1.0,
                'state': 'review',
              },
              {
                'rating': 'good',
                'due_at_ms': 345600000,
                'interval_days': 4.0,
                'state': 'review',
              },
              {
                'rating': 'easy',
                'due_at_ms': 777600000,
                'interval_days': 9.0,
                'state': 'review',
              },
            ]),
          );
        }
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody([
              _reviewItem(
                id: 'review-preview-1',
                kind: 'source_sentence_recall',
                answer: 'A bounded source sentence.',
              ),
            ]),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(),
          slicePlayer: SlicePlayerController(),
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The prediction belongs to the answer side, so it is not fetched before
    // the card flips.
    expect(find.text('10 min'), findsNothing);

    await tester.tap(find.text('Show the sentence'));
    await tester.pumpAndSettle();

    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('1 d'), findsOneWidget);
    expect(find.text('4 d'), findsOneWidget);
    expect(find.text('9 d'), findsOneWidget);
  });

  testWidgets('a failed prediction leaves the grades bare, never invented', (
    tester,
  ) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.endsWith('/interval-preview')) {
          return (statusCode: 500, body: '{"message":"nope"}');
        }
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody([
              _reviewItem(
                id: 'review-preview-2',
                kind: 'source_sentence_recall',
                answer: 'A bounded source sentence.',
              ),
            ]),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(),
          slicePlayer: SlicePlayerController(),
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show the sentence'));
    await tester.pumpAndSettle();

    // All four grades still work; none of them claims an interval.
    for (final grade in ['Missed it', 'Fuzzy', 'Got it', 'Easy']) {
      expect(find.text(grade), findsOneWidget);
    }
    expect(find.textContaining(' d'), findsNothing);
    expect(find.textContaining(' min'), findsNothing);
  });

  testWidgets('a queue emptied by the daily budget says so, and does not '
      'pretend nothing is due', (tester) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody(
              const [],
              limitStatus: const {
                'limits': {'new_cards': 20, 'reviews': 200},
                'new_completed': 20,
                'reviews_completed': 143,
                'new_limit_reached': true,
                'review_limit_reached': false,
              },
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(),
          slicePlayer: SlicePlayerController(),
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('That is enough for today'), findsOneWidget);
    expect(find.text('No sound cards due right now'), findsNothing);
    expect(find.textContaining('20/20 new, 143/200 reviews'), findsOneWidget);
  });

  testWidgets('the card head names the listening item kind', (tester) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.endsWith('/interval-preview')) {
          return (statusCode: 200, body: '[]');
        }
        return (
          statusCode: 200,
          body: jsonEncode(
            _queueBody([
              _reviewItem(
                id: 'review-head-1',
                kind: 'word_recognition',
                answer: 'would',
              ),
            ]),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          controller: ReviewController(LocalReviewRepository(api)),
          resolver: _fakeResolver(),
          slicePlayer: SlicePlayerController(),
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Word recognition'), findsOneWidget);
    expect(find.textContaining('Listening ·'), findsNothing);
  });
}
