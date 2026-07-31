import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/models/practice.dart';
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
            'review_item_ids': <dynamic>[],
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
        if (path == '/v1/listening/sessions/session-1/complete') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'session-1',
              'mode': 'extensive',
              'media_id': 'media-1',
              'track_id': 'track-1',
              'source': 'extensive_listening',
              'started_at_ms': 1,
              'ended_at_ms': 5,
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
      await controller.finishSession(
        api,
        comprehensionReport: 'got_the_gist',
        huntingSummary: const HuntingCompletionSummary(
          promptedCount: 3,
          recognizedCount: 1,
          notRecognizedCount: 1,
          notNoticedCount: 1,
        ),
      ),
      isTrue,
    );
    expect(controller.active, isFalse);
    expect(
      requests.any(
        (request) =>
            request.path == '/v1/listening/sessions/session-1/complete' &&
            (request.body as Map<String, dynamic>)['comprehension_report'] ==
                'got_the_gist' &&
            (request.body
                    as Map<
                      String,
                      dynamic
                    >)['hunting_summary']['prompted_count'] ==
                3 &&
            (request.body
                    as Map<
                      String,
                      dynamic
                    >)['hunting_summary']['recognized_count'] ==
                1,
      ),
      isTrue,
    );

    controller.dispose();
  });

  ({LocalApi api, List<String> paths}) sessionOnlyApi() {
    final paths = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        paths.add(path);
        if (path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"extensive","media_id":"media-1","track_id":"track-1","source":"extensive_listening","started_at_ms":1,"ended_at_ms":null}',
          );
        }
        if (path.startsWith('/v1/listening-inbox/items')) {
          return (statusCode: 200, body: '[]');
        }
        if (path == '/v1/listening/sessions/session-1/complete') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"extensive","media_id":"media-1","track_id":"track-1","source":"extensive_listening","started_at_ms":1,"ended_at_ms":5}',
          );
        }
        throw StateError('unexpected $method $path');
      },
    );
    return (api: api, paths: paths);
  }

  test('played duration counts only playing time during the session', () async {
    var now = DateTime(2026, 7, 22, 10);
    final fake = sessionOnlyApi();
    final controller = ExtensiveListeningController(clock: () => now);

    expect(
      await controller.startSession(
        api: fake.api,
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );
    controller.notePlaybackState(true);
    now = now.add(const Duration(minutes: 5));
    controller.notePlaybackState(false);
    // A paused stretch must not count: this is what separates the figure from
    // started→ended wall clock.
    now = now.add(const Duration(minutes: 3));
    controller.notePlaybackState(true);
    now = now.add(const Duration(minutes: 2));
    expect(controller.playedDuration, const Duration(minutes: 7));

    expect(
      await controller.finishSession(fake.api, comprehensionReport: 'unclear'),
      isTrue,
    );
    // Frozen at completion: post-session playback no longer accumulates.
    now = now.add(const Duration(minutes: 9));
    expect(controller.playedDuration, const Duration(minutes: 7));

    controller.dispose();
  });

  test('session starting mid-playback ticks from session start and '
      'resets per session', () async {
    var now = DateTime(2026, 7, 22, 10);
    final fake = sessionOnlyApi();
    final controller = ExtensiveListeningController(clock: () => now);

    controller.notePlaybackState(true);
    // Pre-session playback is not this session's listening time.
    now = now.add(const Duration(minutes: 4));
    expect(
      await controller.startSession(
        api: fake.api,
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );
    now = now.add(const Duration(minutes: 6));
    expect(controller.playedDuration, const Duration(minutes: 6));

    expect(
      await controller.finishSession(fake.api, comprehensionReport: null),
      isTrue,
    );
    expect(
      await controller.startSession(
        api: fake.api,
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );
    now = now.add(const Duration(minutes: 2));
    // The second session starts from zero even though playback never paused.
    expect(controller.playedDuration, const Duration(minutes: 2));

    controller.dispose();
  });
}
