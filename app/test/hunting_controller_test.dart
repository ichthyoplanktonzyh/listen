import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/data/repositories/hunting_repository.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test(
    'hunting list loads manual targets, adds one, and archives one',
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
          if (method == 'GET' && path.startsWith('/v1/hunting/targets?')) {
            return (statusCode: 200, body: jsonEncode([targetJson]));
          }
          if (method == 'POST' && path == '/v1/hunting/targets') {
            return (
              statusCode: 200,
              body: jsonEncode({
                ...targetJson,
                'id': 'target-2',
                'lexical_entry_id': 'lexical-2',
                'target_snapshot': 'notice',
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
      final controller = HuntingController(
        repository: LocalHuntingRepository(() => api),
      );
      addTearDown(controller.dispose);

      expect(await controller.load(), isTrue);
      expect(controller.state.targets.single.targetSnapshot, 'notice');

      expect(
        await controller.addManual(
          const LexicalEntry(
            id: 'lexical-2',
            normalizedForm: 'notice',
            displayForm: 'notice',
            kind: 'word',
            status: 'known_recognized',
            language: 'en',
          ),
        ),
        isTrue,
      );
      expect(controller.state.targets, hasLength(2));
      expect(requests.last.body, {
        'lexical_entry_id': 'lexical-2',
        'source_kind': 'manual',
        'source_id': null,
      });

      expect(await controller.archive(controller.state.targets.first), isTrue);
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
