import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/listening_inbox_coordinator.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/listening.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';

Map<String, dynamic> _inboxItemJson({int? startMs, int? endMs}) => {
  'id': 'inbox-1',
  'target': {'kind': 'sentence', 'start_ms': startMs, 'end_ms': endMs},
  'anchors': <dynamic>[],
  'subtitle_snapshot': 'A snapshot sentence.',
  'captured_at_ms': 0,
  'status': 'active',
  'review_item_ids': <dynamic>[],
  'updated_at_ms': 0,
};

ListeningInboxItem _inboxItem({int? startMs, int? endMs}) =>
    ListeningInboxItem.fromJson(_inboxItemJson(startMs: startMs, endMs: endMs));

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

({
  ListeningInboxCoordinator coordinator,
  PlayerController player,
  ExtensiveListeningController extensive,
})
_wire(LocalApi? Function() getApi) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final extensive = ExtensiveListeningController();
  final adapter = DesktopPlayerAdapter();
  final playback =
      PlaybackActionsCoordinator(
        adapter: adapter,
        player: player,
        subtitle: subtitle,
      )..bind(
        getApi: getApi,
        isMounted: () => true,
        reloadLearningEntries: () async {},
      );
  final coordinator = ListeningInboxCoordinator(
    extensiveListening: extensive,
    player: player,
    subtitle: subtitle,
    playbackActions: playback,
  )..bind(getApi: getApi, isMounted: () => true);
  addTearDown(adapter.dispose);
  addTearDown(extensive.dispose);
  return (coordinator: coordinator, player: player, extensive: extensive);
}

void main() {
  test(
    'processListeningInboxItem reports the review-item resolution',
    () async {
      final api = _fakeApi((method, path, body) {
        if (path.contains('/process')) {
          return (statusCode: 200, body: jsonEncode(_inboxItemJson()));
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(() => api);

      await w.coordinator.processListeningInboxItem(
        _inboxItem(),
        'review_item',
      );

      expect(w.player.status, 'statusInboxSavedToReview');
    },
  );

  test(
    'replayListeningInboxItem guards an item with no playable range',
    () async {
      final w = _wire(() => null);

      await w.coordinator.replayListeningInboxItem(_inboxItem());

      expect(w.player.status, 'statusInboxNoPlayableRange');
    },
  );

  test('a null API leaves process as a no-op', () async {
    final w = _wire(() => null);
    final before = w.player.status;

    await w.coordinator.processListeningInboxItem(_inboxItem(), 'review_item');

    expect(w.player.status, before);
  });
}
