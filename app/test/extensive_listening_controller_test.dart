import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('extensive controller starts, captures, processes and finishes', () async {
    final requests = <({String method, String path, Object? body})>[];
    final activeItems = <Map<String, dynamic>>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        final decoded = body == null ? null : jsonDecode(body);
        requests.add((method: method, path: path, body: decoded));
        if (path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"extensive","media_id":"media-1","track_id":"track-1","source":"extensive_listening","started_at_ms":1,"ended_at_ms":null}',
          );
        }
        if (path.startsWith('/v1/listening-inbox/items?')) {
          return (statusCode: 200, body: jsonEncode(activeItems));
        }
        if (path == '/v1/listening-inbox/items') {
          final value = decoded as Map<String, dynamic>;
          final item = {
            'id': 'inbox-1',
            'session_id': value['session_id'],
            'media_id': 'media-1',
            'track_id': 'track-1',
            'target': value['target'],
            'anchors': value['anchors'],
            'label': value['label'],
            'subtitle_snapshot': value['subtitle_snapshot'],
            'context_before': value['context_before'],
            'context_after': value['context_after'],
            'captured_at_ms': 2,
            'expires_at_ms': 3,
            'status': 'active',
            'resolution': null,
            'review_item_ids': [],
            'practice_item_id': null,
            'updated_at_ms': 2,
          };
          activeItems
            ..clear()
            ..add(item);
          return (statusCode: 200, body: jsonEncode(item));
        }
        if (path == '/v1/listening-inbox/items/inbox-1/process') {
          final item = {
            ...activeItems.single,
            'status': 'archived',
            'resolution': (decoded as Map<String, dynamic>)['resolution'],
            'review_item_ids': ['review-1'],
            'updated_at_ms': 4,
          };
          activeItems.clear();
          return (statusCode: 200, body: jsonEncode(item));
        }
        if (path == '/v1/practice/sessions/session-1/complete') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'session': {
                'id': 'session-1',
                'mode': 'extensive',
                'media_id': 'media-1',
                'track_id': 'track-1',
                'source': 'extensive_listening',
                'started_at_ms': 1,
                'ended_at_ms': 5,
              },
              'stuck_points': [],
              'stuck_count': 0,
              'resolved_count': 0,
              'active_verified_count': 0,
              'review_count': 0,
              'unexplained_count': 0,
              'skipped_count': 0,
              'closed_count': 0,
              'open_count': 0,
              'attribution_counts': [],
              'familiar_material_marked': false,
            }),
          );
        }
        throw StateError('unexpected $method $path');
      },
    );
    final controller = ExtensiveListeningController();
    final cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: const Duration(milliseconds: 100),
      end: const Duration(milliseconds: 900),
      text: 'would have gone',
      tokens: const [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'would',
          normalized: 'would',
        ),
      ],
    );

    expect(
      await controller.startSession(
        api: api,
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );
    expect(controller.active, isTrue);
    expect(
      await controller.captureCurrentCue(
        api: api,
        cue: cue,
        previousCue: null,
        nextCue: null,
        mediaId: 'media-1',
        trackId: 'track-1',
        mediaTimeMs: (value) => value.inMilliseconds,
      ),
      isTrue,
    );
    expect(controller.items.single.subtitleSnapshot, 'would have gone');
    final processed = await controller.processItem(
      api,
      controller.items.single,
      'review_item',
    );
    expect(processed?.resolution, 'review_item');
    expect(controller.items, isEmpty);
    expect(
      await controller.finishSession(api, comprehensionReport: 'got_the_gist'),
      isTrue,
    );
    expect(controller.active, isFalse);
    expect(
      requests.any(
        (request) =>
            request.path == '/v1/practice/sessions/session-1/complete' &&
            (request.body as Map<String, dynamic>)['comprehension_report'] ==
                'got_the_gist',
      ),
      isTrue,
    );

    controller.dispose();
  });
}
