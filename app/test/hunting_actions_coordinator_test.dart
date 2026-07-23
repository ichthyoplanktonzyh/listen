import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/hunting_actions_coordinator.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Localization stub: returns templates carrying the placeholders the
/// coordinator substitutes, so we can assert both the key and the substitution.
String _text(String key) => switch (key) {
  'huntingStopped' => 'stopped',
  'huntingIndexNeeded' => 'index-needed',
  'huntingStarted' => 'started {count}',
  'huntingAnswerSaved' => 'answer-saved',
  'dictionaryReindexDone' => 'reindexed {count}',
  'dictionaryReindexFailed' => 'reindex-failed {error}',
  _ => key,
};

Map<String, dynamic> _huntingOccurrence(String id, String targetId, int ms) => {
  'target_id': targetId,
  'lexical_entry_id': 'lexical-$targetId',
  'target_snapshot': 'target $targetId',
  'occurrence': {
    'id': id,
    'language': 'en',
    'kind': 'lexical',
    'normalized_key': 'target',
    'display_text': 'target',
    'media_id': 'media-1',
    'track_id': 'track-1',
    'sentence_id': 'sentence-$id',
    'start_ms': ms,
    'end_ms': ms + 1000,
    'source_snapshot': 'A target appears here.',
  },
};

typedef _Handler =
    ({int statusCode, String body}) Function(
      String method,
      String path,
      String? body,
    );

/// Builds a fake [LocalApi] whose transport dispatches to [handler]; unmatched
/// routes throw so tests fail loudly on unexpected calls.
LocalApi _fakeApi(_Handler handler) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

({
  HuntingActionsCoordinator coordinator,
  PlayerController player,
  HuntingSessionController hunting,
  ExtensiveListeningController extensive,
})
_wire({LocalApi? Function()? getApi, bool Function()? isMounted}) {
  final player = PlayerController();
  final hunting = HuntingSessionController();
  final extensive = ExtensiveListeningController();
  final subtitle = SubtitleController();
  final coordinator =
      HuntingActionsCoordinator(
        huntingSession: hunting,
        player: player,
        extensiveListening: extensive,
        subtitle: subtitle,
      )..bind(
        getApi: getApi ?? () => null,
        isMounted: isMounted ?? () => true,
        text: _text,
      );
  return (
    coordinator: coordinator,
    player: player,
    hunting: hunting,
    extensive: extensive,
  );
}

void main() {
  test(
    'toggleHuntingMode starts a session and reports the occurrence count',
    () async {
      ({int statusCode, String body}) handler(
        String method,
        String path,
        String? body,
      ) {
        if (method == 'POST' && path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'session-1',
              'mode': 'extensive',
              'media_id': 'media-1',
              'track_id': 'track-1',
              'source': 'extensive_listening',
              'started_at_ms': 0,
            }),
          );
        }
        if (path.startsWith('/v1/listening-inbox/items')) {
          return (statusCode: 200, body: jsonEncode(<dynamic>[]));
        }
        if (path.startsWith('/v1/hunting/occurrences')) {
          return (
            statusCode: 200,
            body: jsonEncode({
              'indexed': true,
              'occurrences': [
                _huntingOccurrence('o1', 't1', 2000),
                _huntingOccurrence('o2', 't2', 5000),
              ],
            }),
          );
        }
        throw StateError('unexpected $method $path');
      }

      final api = _fakeApi(handler);
      final w = _wire(getApi: () => api);
      addTearDown(w.hunting.dispose);
      addTearDown(w.extensive.dispose);
      w.player.setMedia(
        id: 'media-1',
        path: '/tmp/media.mp4',
        title: 'Media',
        fingerprint: 'fp',
      );

      await w.coordinator.toggleHuntingMode();

      expect(w.hunting.state.enabled, isTrue);
      expect(w.player.status, 'started 2');
    },
  );

  test('toggleHuntingMode stops an already-enabled session', () async {
    final api = _fakeApi((method, path, body) {
      if (path.startsWith('/v1/hunting/occurrences')) {
        return (
          statusCode: 200,
          body: jsonEncode({
            'indexed': true,
            'occurrences': [_huntingOccurrence('o1', 't1', 2000)],
          }),
        );
      }
      throw StateError('unexpected $method $path');
    });
    final w = _wire(getApi: () => api);
    addTearDown(w.hunting.dispose);
    addTearDown(w.extensive.dispose);
    // Bring the session into the enabled state directly.
    expect(
      await w.hunting.start(
        api: api,
        sessionId: 'session-1',
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );
    expect(w.hunting.state.enabled, isTrue);

    await w.coordinator.toggleHuntingMode();

    expect(w.hunting.state.enabled, isFalse);
    expect(w.player.status, 'stopped');
  });

  test(
    'reindexHuntingCorpus reports the indexed track count on success',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'POST' && path == '/v1/corpus/reindex') {
          return (statusCode: 200, body: jsonEncode({'indexed_tracks': 7}));
        }
        if (path.startsWith('/v1/hunting/occurrences')) {
          return (
            statusCode: 200,
            body: jsonEncode({'indexed': false, 'occurrences': <dynamic>[]}),
          );
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(getApi: () => api);
      addTearDown(w.hunting.dispose);
      addTearDown(w.extensive.dispose);

      await w.coordinator.reindexHuntingCorpus();

      expect(w.player.status, 'reindexed 7');
    },
  );

  test(
    'reindexHuntingCorpus reports failure when the request throws',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'POST' && path == '/v1/corpus/reindex') {
          return (statusCode: 500, body: 'boom');
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(getApi: () => api);
      addTearDown(w.hunting.dispose);
      addTearDown(w.extensive.dispose);

      await w.coordinator.reindexHuntingCorpus();

      expect(w.player.status, startsWith('reindex-failed'));
    },
  );

  test(
    'a null API reports the unavailable state on all three actions',
    () async {
      final w = _wire(getApi: () => null);
      addTearDown(w.hunting.dispose);
      addTearDown(w.extensive.dispose);

      await w.coordinator.toggleHuntingMode();
      expect(w.player.status, 'statusOpenMediaAndCoreFirst');
      expect(w.hunting.state.enabled, isFalse);

      await w.coordinator.reindexHuntingCorpus();
      expect(w.player.status, 'statusConnectLocalCoreFirst');

      w.player.setStatus('');
      await w.coordinator.answerHuntingCheck('recognized');
      expect(w.player.status, 'statusConnectLocalCoreFirst');
    },
  );
}
