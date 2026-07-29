import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_library_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';

Map<String, dynamic> _libraryEntryJson({
  String id = 'media-1',
  String path = '/nonexistent/media.mp4',
  String? triageIntent,
}) => {
  'media': {
    'id': id,
    'path': path,
    'fingerprint': 'fp',
    'title': 'Sample',
    'kind': 'video',
    'duration': 1000,
    'availability': 'available',
    'created_at_ms': 0,
    'updated_at_ms': 0,
  },
  'primary_track_id': null,
  'fit': null,
  'triage_intent': triageIntent,
  'familiar_material': false,
};

MediaLibraryEntry _libraryEntry({
  String id = 'media-1',
  String path = '/nonexistent/media.mp4',
}) => MediaLibraryEntry.fromJson(_libraryEntryJson(id: id, path: path));

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

({
  MediaLibraryCoordinator coordinator,
  PlayerController player,
  SettingsController settings,
  List<String> openedPaths,
  List<int> openMediaCalls,
  List<int> rebuilds,
})
_wire(LocalApi? Function() getApi) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final learning = LearningController();
  final settings = SettingsController();
  final extensive = ExtensiveListeningController();
  final openedPaths = <String>[];
  final openMediaCalls = <int>[];
  final rebuilds = <int>[];
  final coordinator =
      MediaLibraryCoordinator(
        player: player,
        subtitle: subtitle,
        learning: learning,
        settings: settings,
        extensiveListening: extensive,
      )..bind(
        getApi: getApi,
        isMounted: () => true,
        text: (key) => key,
        requestRebuild: () => rebuilds.add(1),
        openMediaPath: (path) async => openedPaths.add(path),
        openMedia: () async => openMediaCalls.add(1),
      );
  addTearDown(extensive.dispose);
  return (
    coordinator: coordinator,
    player: player,
    settings: settings,
    openedPaths: openedPaths,
    openMediaCalls: openMediaCalls,
    rebuilds: rebuilds,
  );
}

void main() {
  test('loadMediaLibrary stores parsed entries and requests rebuild', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'GET' && path == '/v1/media') {
        return (statusCode: 200, body: jsonEncode([_libraryEntryJson()]));
      }
      throw StateError('unexpected $method $path');
    });
    final w = _wire(() => api);

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, hasLength(1));
    expect(w.coordinator.mediaLibrary!.first.media.id, 'media-1');
    expect(w.rebuilds, isNotEmpty);
  });

  test('loadMediaLibrary failure keeps the previous entries', () async {
    final api = _fakeApi(
      (method, path, body) => (statusCode: 500, body: 'boom'),
    );
    final w = _wire(() => api);
    w.coordinator.mediaLibrary = [_libraryEntry()];

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, hasLength(1));
  });

  test('a null API leaves loadMediaLibrary as a no-op', () async {
    final w = _wire(() => null);

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, isNull);
    expect(w.rebuilds, isEmpty);
  });

  test('openLibraryEntry guards a missing media file', () async {
    final w = _wire(() => null);

    await w.coordinator.openLibraryEntry(_libraryEntry());

    expect(w.player.status, 'mediaFileMissing');
    expect(w.openedPaths, isEmpty);
  });

  test('openLibraryEntry opens an existing media file', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mlc').path}/m.mp4',
    )..writeAsStringSync('x');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final w = _wire(() => null);

    await w.coordinator.openLibraryEntry(_libraryEntry(path: file.path));

    expect(w.openedPaths, [file.path]);
  });

  test('startIntensiveFromLibrary guards a missing media file', () async {
    final w = _wire(() => null);

    await w.coordinator.startIntensiveFromLibrary(_libraryEntry());

    expect(w.player.status, 'mediaFileMissing');
    expect(w.openedPaths, isEmpty);
  });

  test('setLibraryTriageIntent replaces the updated entry in place', () async {
    final api = _fakeApi((method, path, body) {
      if (path.contains('/triage-intent')) {
        return (
          statusCode: 200,
          body: jsonEncode(_libraryEntryJson(triageIntent: 'pin_intensive')),
        );
      }
      throw StateError('unexpected $method $path');
    });
    final w = _wire(() => api);
    w.coordinator.mediaLibrary = [_libraryEntry()];

    await w.coordinator.setLibraryTriageIntent(
      _libraryEntry(),
      'pin_intensive',
    );

    expect(w.coordinator.mediaLibrary!.first.triageIntent, 'pin_intensive');
    expect(w.rebuilds, isNotEmpty);
  });

  test('setLibraryTriageIntent without a core reports it', () async {
    final w = _wire(() => null);

    await w.coordinator.setLibraryTriageIntent(_libraryEntry(), 'defer');

    expect(w.player.status, 'statusConnectLocalCoreFirst');
    expect(w.rebuilds, isEmpty);
  });

  test('setLibraryTriageIntent failure reports on the player status', () async {
    final api = _fakeApi(
      (method, path, body) => (statusCode: 500, body: 'boom'),
    );
    final w = _wire(() => api);

    await w.coordinator.setLibraryTriageIntent(_libraryEntry(), 'defer');

    // The named state is the whole message (#62). What the backend answered
    // with lives on the typed detail instead of being appended to the line.
    expect(w.player.status, 'statusTriageIntentFailed');
    expect(w.player.status, isNot(contains('HttpException')));
    expect(w.player.statusFailure?.raw, contains('boom'));
  });

  test('continueRecentMedia falls back to the picker without a path', () async {
    final w = _wire(() => null);

    await w.coordinator.continueRecentMedia();

    expect(w.openMediaCalls, hasLength(1));
    expect(w.openedPaths, isEmpty);
  });

  test('continueRecentMedia reopens an existing recent path', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mlc').path}/m.mp4',
    )..writeAsStringSync('x');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final w = _wire(() => null);
    w.settings.recordRecentMedia(
      path: file.path,
      title: 'Sample',
      positionMs: 0,
      durationMs: 1000,
      subtitleCount: 0,
    );

    await w.coordinator.continueRecentMedia();

    expect(w.openedPaths, [file.path]);
    expect(w.openMediaCalls, isEmpty);
  });

  test('recordRecentMedia is a no-op without a playing media path', () {
    final w = _wire(() => null);

    w.coordinator.recordRecentMedia();

    expect(w.settings.lastMediaPath, isEmpty);
  });
}
