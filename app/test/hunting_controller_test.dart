import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test(
    'hunting controller loads, promotes a candidate and archives a target',
    () async {
      final requests = <({String method, String path, Object? body})>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          requests.add((
            method: method,
            path: path,
            body: body == null ? null : jsonDecode(body),
          ));
          if (path == '/v1/hunting/targets?status=active&limit=100&offset=0') {
            return (statusCode: 200, body: jsonEncode([targetJson]));
          }
          if (path ==
              '/v1/hunting/candidates?status=active&limit=100&offset=0') {
            return (statusCode: 200, body: jsonEncode([candidateJson]));
          }
          if (method == 'POST' && path == '/v1/hunting/targets') {
            return (
              statusCode: 200,
              body: jsonEncode({
                ...targetJson,
                'id': 'target-2',
                'lexical_entry_id': 'lexical-2',
                'source_kind': 'review_candidate',
                'source_id': 'candidate-1',
                'target_snapshot': 'would have',
              }),
            );
          }
          if (method == 'DELETE' && path == '/v1/hunting/targets/target-1') {
            return (
              statusCode: 200,
              body: jsonEncode({...targetJson, 'status': 'archived'}),
            );
          }
          throw StateError('unexpected $method $path');
        },
      );
      final controller = HuntingController();
      addTearDown(controller.dispose);

      expect(await controller.load(api), isTrue);
      expect(controller.state.targets.single.targetSnapshot, 'notice');
      expect(controller.state.candidates.single.failureCount, 3);

      expect(
        await controller.promoteCandidate(
          api,
          controller.state.candidates.single,
        ),
        isTrue,
      );
      expect(controller.state.targets.length, 2);
      expect(controller.state.candidates, isEmpty);
      expect(requests.last.body, {
        'lexical_entry_id': 'lexical-2',
        'source_kind': 'review_candidate',
        'source_id': 'candidate-1',
      });

      expect(
        await controller.archive(api, controller.state.targets.first),
        isTrue,
      );
      expect(controller.state.targets.single.id, 'target-2');
      expect(requests.last.path, '/v1/hunting/targets/target-1');
    },
  );
}

const targetJson = <String, dynamic>{
  'id': 'target-1',
  'lexical_entry_id': 'lexical-1',
  'source_kind': 'manual',
  'source_id': null,
  'target_snapshot': 'notice',
  'status': 'active',
  'created_at_ms': 1,
  'updated_at_ms': 1,
};

const candidateJson = <String, dynamic>{
  'id': 'candidate-1',
  'lexical_entry_id': 'lexical-2',
  'review_item_id': 'review-1',
  'sentence_id': 'sentence-1',
  'media_id': 'media-1',
  'track_id': 'track-1',
  'target_snapshot': 'would have',
  'prompt_snapshot': 'I would have gone.',
  'failure_count': 3,
  'status': 'active',
  'created_at_ms': 1,
  'last_failed_at_ms': 2,
};
