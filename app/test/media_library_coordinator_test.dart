import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_library_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
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

/// A Core 3.2 `/v1/materials` row: one retained learning material with its
/// current revision. Defaults to a mixed-shape material with no assets.
Map<String, dynamic> _materialDetailsJson({
  String materialId = 'material-1',
  String revisionId = 'revision-1',
  String title = 'Sample material',
  String shape = 'mixed',
  int updatedAtMs = 100,
  List<Map<String, dynamic>> assets = const [],
}) => {
  'material': {
    'id': materialId,
    'current_revision_id': revisionId,
    'retained_at_ms': 42,
    'created_at_ms': 0,
    'updated_at_ms': updatedAtMs,
  },
  'current_revision': {
    'id': revisionId,
    'material_id': materialId,
    'title': title,
    'assets': assets,
    'created_at_ms': 0,
  },
  'shape': shape,
};

Map<String, dynamic> _mediaRenditionJson({
  required String id,
  required String mediaId,
}) => {
  'asset_type': 'media_rendition',
  'id': id,
  'media_id': mediaId,
  'media_kind': 'audio',
  'fingerprint': 'fp',
  'availability': 'available',
};

/// Directly constructed [MaterialDetails] for seeding previous state without
/// going through the wire.
MaterialDetails _materialDetails({
  String materialId = 'material-1',
  String title = 'Sample material',
  List<MaterialAsset> assets = const [],
}) => MaterialDetails(
  material: LearningMaterial(
    id: materialId,
    currentRevisionId: 'revision-1',
    retainedAtMs: 42,
    createdAtMs: 0,
    updatedAtMs: 100,
  ),
  currentRevision: MaterialRevision(
    id: 'revision-1',
    materialId: materialId,
    title: title,
    assets: assets,
    createdAtMs: 0,
  ),
  shape: MaterialShape.mixed,
);

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
_wire(LocalApi? Function() getApi, {LocalApi? Function()? materialApi}) {
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
        repository: LocalMediaLibraryRepository(getApi),
        materialRepository: LocalLearningMaterialRepository(
          materialApi ?? getApi,
        ),
      )..bind(
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
  test(
    'loadMediaLibrary publishes material rows joined to the media snapshot',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                assets: [
                  _mediaRenditionJson(id: 'asset-1', mediaId: 'media-1'),
                ],
              ),
            ]),
          );
        }
        if (method == 'GET' && path == '/v1/media') {
          return (statusCode: 200, body: jsonEncode([_libraryEntryJson()]));
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(() => api);

      await w.coordinator.loadMediaLibrary();

      expect(w.coordinator.mediaLibrary, hasLength(1));
      expect(w.coordinator.mediaLibrary!.first.media.id, 'media-1');
      expect(w.coordinator.personalLibrary, hasLength(1));
      expect(w.coordinator.personalLibrary!.single.title, 'Sample material');
      expect(
        w.coordinator.personalLibrary!.single.primaryMedia?.media.id,
        'media-1',
      );
      expect(w.rebuilds, isNotEmpty);
    },
  );

  test('LocalApi exposes media-library rows as typed models', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'GET' && path == '/v1/media') {
        return (statusCode: 200, body: jsonEncode([_libraryEntryJson()]));
      }
      throw StateError('unexpected $method $path');
    });

    final entries = await api.listMediaLibrary();

    expect(entries, hasLength(1));
    expect(entries.single, isA<MediaLibraryEntry>());
    expect(entries.single.media.id, 'media-1');
  });

  test(
    'loadMediaLibrary material failure preserves the previous library',
    () async {
      final api = _fakeApi(
        (method, path, body) => (statusCode: 500, body: 'boom'),
      );
      final w = _wire(() => api);
      final previousEntry = _libraryEntry();
      w.coordinator.mediaLibrary = [previousEntry];
      w.coordinator.personalLibrary = [
        PersonalLibraryEntry(
          details: _materialDetails(
            assets: [
              MediaRenditionMaterialAsset(
                id: 'asset-1',
                mediaId: 'media-1',
                mediaKind: MediaRenditionKind.audio,
                fingerprint: 'fp',
                availability: MediaRenditionAvailability.available,
              ),
            ],
          ),
          mediaEntries: [previousEntry],
        ),
      ];

      await w.coordinator.loadMediaLibrary();

      expect(w.coordinator.mediaLibrary, [previousEntry]);
      expect(w.coordinator.personalLibrary, hasLength(1));
      expect(
        w.coordinator.personalLibrary!.single.primaryMedia?.media.id,
        'media-1',
      );
      expect(w.rebuilds, isEmpty);
    },
  );

  test('a null API leaves loadMediaLibrary as a no-op', () async {
    final w = _wire(() => null);

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, isNull);
    expect(w.rebuilds, isEmpty);
  });

  test(
    'loadMediaLibrary lists materials when only the material repo is up',
    () async {
      final materialApi = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                assets: [_mediaRenditionJson(id: 'a1', mediaId: 'media-1')],
              ),
            ]),
          );
        }
        throw StateError('unexpected $method $path');
      });
      // The media repository is independently unavailable; the material
      // repository still answers. Material authority must not be gated on the
      // media snapshot query.
      final w = _wire(() => null, materialApi: () => materialApi);
      final previous = _libraryEntry();
      w.coordinator.mediaLibrary = [previous];

      await w.coordinator.loadMediaLibrary();

      expect(w.coordinator.personalLibrary, hasLength(1));
      final row = w.coordinator.personalLibrary!.single;
      expect(row.title, 'Sample material');
      // The media query is skipped, so the previous raw snapshot survives
      // untouched and keeps feeding registered paths.
      expect(w.coordinator.mediaLibrary, [previous]);
      expect(w.coordinator.registeredMediaPaths, ['/nonexistent/media.mp4']);
      expect(w.rebuilds, isNotEmpty);
    },
  );

  test(
    'loadMediaLibrary joins by current revision ids in material order',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                materialId: 'material-1',
                revisionId: 'revision-1',
                title: 'First',
                assets: [
                  _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
                  _mediaRenditionJson(id: 'a2', mediaId: 'media-2'),
                ],
              ),
              _materialDetailsJson(
                materialId: 'material-2',
                revisionId: 'revision-2',
                title: 'Second',
                assets: [_mediaRenditionJson(id: 'a3', mediaId: 'media-3')],
              ),
            ]),
          );
        }
        if (method == 'GET' && path == '/v1/media') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _libraryEntryJson(id: 'media-1'),
              _libraryEntryJson(id: 'media-2', path: '/nonexistent/2.mp4'),
              _libraryEntryJson(id: 'media-3', path: '/nonexistent/3.mp4'),
              _libraryEntryJson(id: 'media-999', path: '/nonexistent/999.mp4'),
            ]),
          );
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(() => api);

      await w.coordinator.loadMediaLibrary();

      // Rows keep the material-listing order, and each joins only the media ids
      // its own current revision mentions.
      final personal = w.coordinator.personalLibrary!;
      expect(personal.map((row) => row.title), ['First', 'Second']);
      expect(personal[0].mediaEntries.map((entry) => entry.media.id), [
        'media-1',
        'media-2',
      ]);
      expect(personal[1].mediaEntries.map((entry) => entry.media.id), [
        'media-3',
      ]);
      // media-999 appears in no current revision, so it never joins a row even
      // though the raw snapshot still carries it.
      expect(w.coordinator.mediaLibrary, hasLength(4));
      expect(w.rebuilds, isNotEmpty);
    },
  );

  test(
    'loadMediaLibrary media failure still publishes material rows',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                assets: [_mediaRenditionJson(id: 'a1', mediaId: 'media-1')],
              ),
              _materialDetailsJson(
                materialId: 'material-text',
                revisionId: 'revision-text',
                title: 'Text only',
                shape: 'text',
              ),
            ]),
          );
        }
        if (method == 'GET' && path == '/v1/media') {
          return (statusCode: 500, body: 'boom');
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(() => api);

      await w.coordinator.loadMediaLibrary();

      // All retained materials publish even though the media snapshot failed;
      // text-only rows carry no media and still show up.
      expect(w.coordinator.personalLibrary, hasLength(2));
      expect(w.coordinator.personalLibrary!.first.title, 'Sample material');
      expect(w.coordinator.personalLibrary!.last.title, 'Text only');
      expect(w.coordinator.personalLibrary!.last.mediaEntries, isEmpty);
      // No previous raw snapshot existed, so it stays null — never a fake
      // "nothing is registered".
      expect(w.coordinator.mediaLibrary, isNull);
      expect(w.rebuilds, isNotEmpty);
    },
  );

  test(
    'loadMediaLibrary media failure keeps the raw snapshot for paths',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                assets: [_mediaRenditionJson(id: 'a1', mediaId: 'media-1')],
              ),
            ]),
          );
        }
        if (method == 'GET' && path == '/v1/media') {
          return (statusCode: 500, body: 'boom');
        }
        throw StateError('unexpected $method $path');
      });
      final w = _wire(() => api);
      final previous = _libraryEntry();
      w.coordinator.mediaLibrary = [previous];

      await w.coordinator.loadMediaLibrary();

      // The previous raw snapshot is untouched, still feeds registered paths,
      // and still joins the freshly published material row.
      expect(w.coordinator.mediaLibrary, [previous]);
      expect(w.coordinator.registeredMediaPaths, ['/nonexistent/media.mp4']);
      final row = w.coordinator.personalLibrary!.single;
      expect(row.mediaEntries.single.media.id, 'media-1');
      expect(row.primaryMedia?.media.id, 'media-1');
    },
  );

  test('setLibraryTriageIntent keeps the authoritative list in sync', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'GET' && path == '/v1/materials') {
        return (
          statusCode: 200,
          body: jsonEncode([
            _materialDetailsJson(
              assets: [_mediaRenditionJson(id: 'a1', mediaId: 'media-1')],
            ),
          ]),
        );
      }
      if (method == 'GET' && path == '/v1/media') {
        return (statusCode: 200, body: jsonEncode([_libraryEntryJson()]));
      }
      if (path.contains('/triage-intent')) {
        return (
          statusCode: 200,
          body: jsonEncode(_libraryEntryJson(triageIntent: 'pin_intensive')),
        );
      }
      throw StateError('unexpected $method $path');
    });
    final w = _wire(() => api);

    await w.coordinator.loadMediaLibrary();
    expect(w.coordinator.personalLibrary!.single.triageIntent, isNull);

    await w.coordinator.setLibraryTriageIntent(
      w.coordinator.mediaLibrary!.first,
      'pin_intensive',
    );

    expect(w.coordinator.mediaLibrary!.first.triageIntent, 'pin_intensive');
    expect(w.coordinator.personalLibrary!.single.triageIntent, 'pin_intensive');
    expect(w.rebuilds, hasLength(2));
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
