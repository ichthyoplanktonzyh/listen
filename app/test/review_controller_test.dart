import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';

ReviewQueueEntry _entry(String id) => ReviewQueueEntry.fromJson({
  'item': {
    'id': id,
    'source': {
      'kind': 'sentence',
      'id': 'sentence-$id',
      'practice_attempt_id': null,
      'lexical_entry_id': null,
      'media_id': null,
      'track_id': null,
    },
    'anchors': const <dynamic>[],
    'prompt_snapshot': id,
    'status': 'active',
    'created_at_ms': 1,
    'updated_at_ms': 1,
  },
  'schedule': {
    'item_id': id,
    'algorithm': 'test',
    'due_at_ms': 1,
    'stability': null,
    'difficulty': null,
    'interval_days': null,
    'lapse_count': 0,
  },
  'card': {'kind': 'word_recognition', 'answer': id},
});

class _ControlledReviewRepository implements ReviewRepository {
  final dueRequests = <Completer<List<ReviewQueueEntry>>>[];

  @override
  Future<List<ReviewQueueEntry>> dueItems({int limit = 20}) {
    final request = Completer<List<ReviewQueueEntry>>();
    dueRequests.add(request);
    return request.future;
  }

  @override
  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions() async => const [];

  @override
  Future<String> fingerprintFile(String path) => throw UnimplementedError();

  @override
  Future<MediaItem> readMedia(String mediaId) => throw UnimplementedError();

  @override
  Future<void> registerMedia(String path) => throw UnimplementedError();

  @override
  Future<void> resolveUpgradeSuggestion(String id, {required bool confirm}) =>
      throw UnimplementedError();

  @override
  Future<ReviewSubmission> submitRating(String itemId, String rating) =>
      throw UnimplementedError();
}

void main() {
  test(
    'the newest load wins when queue requests complete out of order',
    () async {
      final repository = _ControlledReviewRepository();
      final controller = ReviewController(repository);
      addTearDown(controller.dispose);

      final oldLoad = controller.load();
      final newLoad = controller.load();
      repository.dueRequests[1].complete([_entry('new')]);
      expect(await newLoad, isTrue);
      expect(controller.current?.item.id, 'new');

      repository.dueRequests[0].complete([_entry('old')]);
      expect(await oldLoad, isFalse);
      expect(controller.current?.item.id, 'new');
    },
  );

  test('a load completing after dispose publishes no state', () async {
    final repository = _ControlledReviewRepository();
    final controller = ReviewController(repository);

    final load = controller.load();
    controller.dispose();
    repository.dueRequests.single.complete([_entry('late')]);

    expect(await load, isFalse);
  });

  test(
    'review controller loads, reveals and records a three-way rating',
    () async {
      final requests = <({String method, String path, Object? body})>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          final decoded = body == null ? null : jsonDecode(body);
          requests.add((method: method, path: path, body: decoded));
          if (path == '/v1/review/items?limit=20') {
            return (
              statusCode: 200,
              body: jsonEncode([
                {
                  'item': {
                    'id': 'review-1',
                    'source': {
                      'kind': 'listening_inbox',
                      'id': 'inbox-1',
                      'practice_attempt_id': null,
                      'lexical_entry_id': null,
                      'media_id': 'media-1',
                      'track_id': 'track-1',
                    },
                    'anchors': [
                      {
                        'kind': 'sentence',
                        'id': 'sentence-1',
                        'label': 'would have',
                        'lexical_entry_id': null,
                        'sentence_id': 'sentence-1',
                        'token_start': 0,
                        'token_end': 1,
                        'start_ms': 100,
                        'end_ms': 900,
                      },
                    ],
                    'prompt_snapshot': 'would have',
                    'status': 'active',
                    'created_at_ms': 1,
                    'updated_at_ms': 1,
                  },
                  'schedule': {
                    'item_id': 'review-1',
                    'algorithm': 'listen_review_v1_heuristic_proxy',
                    'due_at_ms': 1,
                    'stability': null,
                    'difficulty': null,
                    'interval_days': null,
                    'lapse_count': 0,
                  },
                  'card': {
                    'kind': 'phrase_presence',
                    'cue': 'would have',
                    'answer': 'I would have gone',
                    'target': 'would have',
                  },
                },
              ]),
            );
          }
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          if (path == '/v1/review/attempts') {
            return (
              statusCode: 200,
              body: jsonEncode({
                'attempt': {
                  'id': 'attempt-1',
                  'item_id': 'review-1',
                  'reviewed_at_ms': 2,
                  'rating': 'hard',
                  'practice_attempt_id': null,
                  'next_due_at_ms': 86400002,
                },
                'schedule': {
                  'item_id': 'review-1',
                  'algorithm': 'listen_review_v1_heuristic_proxy',
                  'due_at_ms': 86400002,
                  'stability': null,
                  'difficulty': null,
                  'interval_days': 1.0,
                  'lapse_count': 0,
                },
                'generated_observation_ids': const <dynamic>[],
                'hunting_candidate_ids': const <dynamic>[],
                'upgrade_suggestions': [upgradeSuggestionJson],
              }),
            );
          }
          if (path == '/v1/review/upgrade-suggestions/suggestion-1/confirm') {
            return (
              statusCode: 200,
              body: jsonEncode({
                ...upgradeSuggestionJson,
                'status': 'accepted',
              }),
            );
          }
          throw StateError('unexpected $method $path');
        },
      );
      final controller = ReviewController(LocalReviewRepository(api));
      addTearDown(controller.dispose);

      expect(await controller.load(), isTrue);
      expect(controller.state.remaining, 1);
      expect(controller.current?.playbackStartMs, 100);
      expect(controller.current?.card.kind, 'phrase_presence');
      expect(controller.current?.card.target, 'would have');
      controller.reveal();
      expect(controller.state.revealed, isTrue);
      expect(await controller.rate('hard'), isTrue);
      expect(controller.state.completedCount, 1);
      expect(controller.state.finished, isTrue);
      expect(
        controller.state.upgradeSuggestions.single.lexicalDisplayForm,
        'would have',
      );
      expect(requests.last.body, {'item_id': 'review-1', 'rating': 'hard'});
      expect(
        await controller.resolveUpgradeSuggestion(
          'suggestion-1',
          confirm: true,
        ),
        isTrue,
      );
      expect(controller.state.upgradeSuggestions, isEmpty);
      expect(
        requests.last.path,
        '/v1/review/upgrade-suggestions/suggestion-1/confirm',
      );
    },
  );
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
