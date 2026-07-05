import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
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
                },
              ]),
            );
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
              }),
            );
          }
          throw StateError('unexpected $method $path');
        },
      );
      final controller = ReviewController();
      addTearDown(controller.dispose);

      expect(await controller.load(api), isTrue);
      expect(controller.state.remaining, 1);
      expect(controller.current?.playbackStartMs, 100);
      controller.reveal();
      expect(controller.state.revealed, isTrue);
      expect(await controller.rate(api, 'hard'), isTrue);
      expect(controller.state.completedCount, 1);
      expect(controller.state.finished, isTrue);
      expect(requests.last.body, {'item_id': 'review-1', 'rating': 'hard'});
    },
  );
}
