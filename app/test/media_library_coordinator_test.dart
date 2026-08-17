import 'dart:async';
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

import 'support/learning_material_fixtures.dart';

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

/// A Core 4.0 `/v1/materials` row: one retained learning material with its
/// current revision. Defaults to a mixed-shape material with no renditions.
Map<String, dynamic> _materialDetailsJson({
  String materialId = 'material-1',
  String revisionId = 'revision-1',
  String title = 'Sample material',
  String shape = 'mixed',
  int updatedAtMs = 100,
  List<Map<String, dynamic>> mediaRenditions = const [],
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
    'source_assets': <Map<String, dynamic>>[],
    'document_renditions': <Map<String, dynamic>>[],
    'media_renditions': mediaRenditions,
    'created_at_ms': 0,
  },
  'shape': shape,
};

Map<String, dynamic> _mediaRenditionJson({
  required String id,
  required String mediaId,
}) => {
  'id': id,
  'origin': 'source',
  'kind': 'audio',
  'media_type': 'audio/mpeg',
  'fingerprint': 'fp',
  'availability': 'available',
  'media_id': mediaId,
  'media_sha256': null,
  'media_byte_size': null,
};

/// Directly constructed [MaterialDetails] for seeding previous state without
/// going through the wire.
MaterialDetails _materialDetails({
  String materialId = 'material-1',
  String title = 'Sample material',
  List<SourceAsset> sourceAssets = const [],
  List<DocumentRendition> documentRenditions = const [],
  List<MediaRendition> mediaRenditions = const [],
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
    sourceAssets: sourceAssets,
    documentRenditions: documentRenditions,
    mediaRenditions: mediaRenditions,
    createdAtMs: 0,
  ),
  shape: MaterialShape.mixed,
);

/// A [PersonalLibraryEntry] whose revision binds [mediaEntry] as an available
/// audio rendition — the row shape the coordinator's own entry methods take.
PersonalLibraryEntry _personalEntry(MediaLibraryEntry mediaEntry) =>
    PersonalLibraryEntry(
      details: _materialDetails(
        mediaRenditions: [
          mediaRendition(
            id: 'asset-1',
            mediaId: mediaEntry.media.id,
            kind: MediaRenditionKind.audio,
            fingerprint: 'fp',
          ),
        ],
      ),
      mediaEntries: [mediaEntry],
    );

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

/// A controllable transport for deterministic overlapping-load scenarios.
/// Each request position is either an immediate JSON body string, an explicit
/// `(statusCode, body)` response, or a [Completer] whose body the test
/// supplies later. Requests are served strictly in call order, so the
/// interleaving of two [MediaLibraryCoordinator.loadMediaLibrary] calls is
/// fully determined by the lists.
LocalApi _gatedApi({
  required List<Object> materials,
  required List<Object> media,
  void Function(String method, String path)? onRequest,
}) {
  var materialIndex = 0;
  var mediaIndex = 0;
  return LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      onRequest?.call(method, path);
      if (method == 'GET' && path == '/v1/materials') {
        return _serveGated(materials[materialIndex++]);
      }
      if (method == 'GET' && path == '/v1/media') {
        return _serveGated(media[mediaIndex++]);
      }
      throw StateError('unexpected $method $path');
    },
  );
}

Future<({int statusCode, String body})> _serveGated(Object request) async {
  if (request is String) return (statusCode: 200, body: request);
  if (request is ({int statusCode, String body})) return request;
  if (request is Completer<String>) {
    return (statusCode: 200, body: await request.future);
  }
  throw StateError('unexpected gated request $request');
}

({
  MediaLibraryCoordinator coordinator,
  PlayerController player,
  SettingsController settings,
  List<String> openedPaths,
  List<int> openMediaCalls,
  List<int> rebuilds,
  List<(List<MediaLibraryEntry>?, List<PersonalLibraryEntry>?)>
  rebuildSnapshots,
})
_wire(
  LocalApi? Function() getApi, {
  LocalApi? Function()? materialApi,
  bool Function()? isMounted,
}) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final learning = LearningController();
  final settings = SettingsController();
  final extensive = ExtensiveListeningController();
  final openedPaths = <String>[];
  final openMediaCalls = <int>[];
  final rebuilds = <int>[];
  final rebuildSnapshots =
      <(List<MediaLibraryEntry>?, List<PersonalLibraryEntry>?)>[];
  late final MediaLibraryCoordinator coordinator;
  coordinator =
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
        isMounted: isMounted ?? () => true,
        text: (key) => key,
        requestRebuild: () {
          rebuilds.add(1);
          rebuildSnapshots.add((
            coordinator.mediaLibrary,
            coordinator.personalLibrary,
          ));
        },
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
    rebuildSnapshots: rebuildSnapshots,
  );
}

void main() {
  test(
    'a retained document is published even when the full library cannot load',
    () async {
      final api = _fakeApi(
        (method, path, body) => (statusCode: 500, body: 'corrupt old row'),
      );
      final w = _wire(() => api);
      final retainedDocument = _materialDetails(
        materialId: 'saved-document',
        title: 'Saved text material',
        documentRenditions: [documentRenditionForText('Saved body')],
      );

      await w.coordinator.reconcileMembership(retainedDocument);

      expect(w.coordinator.personalLibrary, hasLength(1));
      expect(
        w.coordinator.personalLibrary!.single.title,
        'Saved text material',
      );
      expect(w.coordinator.personalLibrary!.single.canRead, isTrue);
    },
  );

  test(
    'loadMediaLibrary publishes material rows joined to the media snapshot',
    () async {
      final api = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                mediaRenditions: [
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
            mediaRenditions: [
              mediaRendition(
                id: 'asset-1',
                mediaId: 'media-1',
                kind: MediaRenditionKind.audio,
                fingerprint: 'fp',
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
      expect(w.rebuilds, hasLength(1));
      expect(w.coordinator.personalLibraryFailure, isNotNull);
    },
  );

  test('a null API leaves loadMediaLibrary as a no-op', () async {
    final w = _wire(() => null);

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, isNull);
    expect(w.rebuilds, isEmpty);
    expect(w.coordinator.personalLibraryFailure, isNull);
  });

  test('an unmounted coordinator publishes nothing', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'GET' && path == '/v1/materials') {
        return (
          statusCode: 200,
          body: jsonEncode([
            _materialDetailsJson(
              mediaRenditions: [
                _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
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
    final w = _wire(() => api, isMounted: () => false);

    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, isNull);
    expect(w.coordinator.personalLibrary, isNull);
    expect(w.rebuilds, isEmpty);
    expect(w.coordinator.personalLibraryFailure, isNull);
  });

  test(
    'a slow old material query cannot overwrite a newer full load',
    () async {
      final oldMaterials = Completer<String>();
      final newMaterials = jsonEncode([
        _materialDetailsJson(
          materialId: 'material-new',
          revisionId: 'revision-new',
          title: 'New',
          mediaRenditions: [
            _mediaRenditionJson(id: 'a1', mediaId: 'media-new'),
          ],
        ),
      ]);
      final newMedia = jsonEncode([_libraryEntryJson(id: 'media-new')]);
      final mediaRequests = <String>[];
      final api = _gatedApi(
        materials: [oldMaterials, newMaterials],
        media: [newMedia],
        onRequest: (method, path) {
          if (path == '/v1/media') mediaRequests.add(method);
        },
      );
      final w = _wire(() => api);

      // The old request starts first and blocks on the material response.
      final oldLoad = w.coordinator.loadMediaLibrary();
      // The new request completes end to end and publishes its own result.
      await w.coordinator.loadMediaLibrary();

      expect(w.coordinator.personalLibrary!.single.title, 'New');
      expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
      expect(w.rebuilds, hasLength(1));

      // Releasing the old material response must not republish anything: the
      // stale load is superseded before it even issues its media query.
      oldMaterials.complete(
        jsonEncode([
          _materialDetailsJson(
            materialId: 'material-old',
            revisionId: 'revision-old',
            title: 'Old',
            mediaRenditions: [
              _mediaRenditionJson(id: 'a2', mediaId: 'media-old'),
            ],
          ),
        ]),
      );
      await oldLoad;

      expect(w.coordinator.personalLibrary!.single.title, 'New');
      expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
      expect(w.rebuilds, hasLength(1));
      expect(mediaRequests, ['GET']);
    },
  );

  test('a slow old media query cannot overwrite a newer full load', () async {
    final oldMedia = Completer<String>();
    final oldMaterials = jsonEncode([
      _materialDetailsJson(
        materialId: 'material-old',
        revisionId: 'revision-old',
        title: 'Old',
        mediaRenditions: [_mediaRenditionJson(id: 'a2', mediaId: 'media-old')],
      ),
    ]);
    final oldMediaBody = jsonEncode([_libraryEntryJson(id: 'media-old')]);
    final newMaterials = jsonEncode([
      _materialDetailsJson(
        materialId: 'material-new',
        revisionId: 'revision-new',
        title: 'New',
        mediaRenditions: [_mediaRenditionJson(id: 'a1', mediaId: 'media-new')],
      ),
    ]);
    final newMedia = jsonEncode([_libraryEntryJson(id: 'media-new')]);
    // Completes exactly when the old request's media query reaches the
    // transport seam, proving it is blocked there before the new load starts.
    final oldMediaRequested = Completer<void>();
    final api = _gatedApi(
      materials: [oldMaterials, newMaterials],
      media: [oldMedia, newMedia],
      onRequest: (method, path) {
        if (path == '/v1/media' && !oldMediaRequested.isCompleted) {
          oldMediaRequested.complete();
        }
      },
    );
    final w = _wire(() => api);

    // The old request already holds its material rows; wait until its media
    // query is observably blocked on the seam, then let the new request
    // publish its own full result.
    final oldLoad = w.coordinator.loadMediaLibrary();
    await oldMediaRequested.future;
    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.personalLibrary!.single.title, 'New');
    expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
    expect(w.rebuilds, hasLength(1));

    // Releasing the stale media snapshot must not replace the newer state:
    // neither the old snapshot nor its material projection may land.
    oldMedia.complete(oldMediaBody);
    await oldLoad;

    expect(w.coordinator.personalLibrary!.single.title, 'New');
    expect(
      w.coordinator.personalLibrary!.single.mediaEntries.single.media.id,
      'media-new',
    );
    expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
    expect(w.rebuilds, hasLength(1));
  });

  test('a newer failed load invalidates an older in-flight success', () async {
    final oldMaterials = Completer<String>();
    final staleBody = jsonEncode([
      _materialDetailsJson(
        materialId: 'material-stale',
        revisionId: 'revision-stale',
        title: 'Stale',
      ),
    ]);
    final api = _gatedApi(
      materials: [oldMaterials, (statusCode: 500, body: 'boom')],
      media: [],
    );
    final w = _wire(() => api);
    final previousEntry = _libraryEntry();
    w.coordinator.mediaLibrary = [previousEntry];
    w.coordinator.personalLibrary = [
      PersonalLibraryEntry(
        details: _materialDetails(),
        mediaEntries: [previousEntry],
      ),
    ];

    // The old request is in flight; the new one fails on the material query
    // and must still retire it.
    final oldLoad = w.coordinator.loadMediaLibrary();
    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, [previousEntry]);
    expect(w.coordinator.personalLibrary, hasLength(1));
    expect(w.rebuilds, hasLength(1));

    // The old request then succeeds, but it is no longer the newest load and
    // must not publish anything.
    oldMaterials.complete(staleBody);
    await oldLoad;

    expect(w.coordinator.mediaLibrary, [previousEntry]);
    expect(w.coordinator.personalLibrary!.single.materialId, 'material-1');
    expect(w.rebuilds, hasLength(1));
  });

  test('a newer load that exits on an unavailable repository still invalidates '
      'the older in-flight load', () async {
    final oldMaterials = Completer<String>();
    final oldMediaRequests = <String>[];
    // The provider starts available and switches to null mid-flight.
    final oldMaterialsRequested = Completer<void>();
    LocalApi? api = _gatedApi(
      materials: [oldMaterials],
      media: [],
      onRequest: (method, path) {
        if (path == '/v1/materials' && !oldMaterialsRequested.isCompleted) {
          oldMaterialsRequested.complete();
        }
        if (path == '/v1/media') oldMediaRequests.add(method);
      },
    );
    final w = _wire(() => api);
    final previousEntry = _libraryEntry();
    final previousLibrary = [previousEntry];
    final previousPersonalLibrary = [
      PersonalLibraryEntry(
        details: _materialDetails(),
        mediaEntries: [previousEntry],
      ),
    ];
    w.coordinator.mediaLibrary = previousLibrary;
    w.coordinator.personalLibrary = previousPersonalLibrary;

    // The old request is in flight, observably blocked on its material
    // query.
    final oldLoad = w.coordinator.loadMediaLibrary();
    await oldMaterialsRequested.future;

    // The provider goes away. The new load exits early on the unavailable
    // material repository, but taking the generation still retires the
    // in-flight old load.
    api = null;
    await w.coordinator.loadMediaLibrary();

    expect(w.coordinator.mediaLibrary, same(previousLibrary));
    expect(w.coordinator.personalLibrary, same(previousPersonalLibrary));
    expect(w.rebuilds, isEmpty);

    // The old request then succeeds; superseded, it must not continue to
    // the media query nor publish anything.
    oldMaterials.complete(
      jsonEncode([
        _materialDetailsJson(
          materialId: 'material-stale',
          revisionId: 'revision-stale',
          title: 'Stale',
        ),
      ]),
    );
    await oldLoad;

    expect(w.coordinator.mediaLibrary, same(previousLibrary));
    expect(w.coordinator.personalLibrary, same(previousPersonalLibrary));
    expect(w.rebuilds, isEmpty);
    expect(oldMediaRequests, isEmpty);
  });

  test(
    'the newest successful load publishes atomically with one rebuild',
    () async {
      final oldMedia = Completer<String>();
      final oldMaterials = jsonEncode([
        _materialDetailsJson(
          materialId: 'material-old',
          revisionId: 'revision-old',
          title: 'Old',
          mediaRenditions: [
            _mediaRenditionJson(id: 'a2', mediaId: 'media-old'),
          ],
        ),
      ]);
      final newMaterials = jsonEncode([
        _materialDetailsJson(
          materialId: 'material-new',
          revisionId: 'revision-new',
          title: 'New',
          mediaRenditions: [
            _mediaRenditionJson(id: 'a1', mediaId: 'media-new'),
          ],
        ),
      ]);
      final newMediaBody = jsonEncode([_libraryEntryJson(id: 'media-new')]);
      // Completes exactly when the old request's media query reaches the
      // transport seam, proving it is blocked there before the new load starts.
      final oldMediaRequested = Completer<void>();
      final api = _gatedApi(
        materials: [oldMaterials, newMaterials],
        media: [oldMedia, newMediaBody],
        onRequest: (method, path) {
          if (path == '/v1/media' && !oldMediaRequested.isCompleted) {
            oldMediaRequested.complete();
          }
        },
      );
      final w = _wire(() => api);

      // The old request has its stale material rows; wait until its media
      // query is observably blocked on the seam, then let the new load
      // publish mediaLibrary + personalLibrary together.
      final oldLoad = w.coordinator.loadMediaLibrary();
      await oldMediaRequested.future;
      await w.coordinator.loadMediaLibrary();

      expect(w.rebuilds, hasLength(1));
      expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
      expect(w.coordinator.personalLibrary!.single.materialId, 'material-new');

      // Releasing the stale media query with the *new* media value is exactly
      // the interleaving that would let an unguarded old request publish a
      // "new mediaLibrary + old personalLibrary" hybrid. It must publish
      // nothing at all.
      oldMedia.complete(newMediaBody);
      await oldLoad;

      expect(w.rebuilds, hasLength(1));
      expect(w.coordinator.mediaLibrary!.single.media.id, 'media-new');
      expect(w.coordinator.personalLibrary!.single.materialId, 'material-new');
      expect(w.rebuildSnapshots, hasLength(1));
      expect(w.rebuildSnapshots.single.$1, same(w.coordinator.mediaLibrary));
      expect(w.rebuildSnapshots.single.$2, same(w.coordinator.personalLibrary));
    },
  );

  test(
    'loadMediaLibrary lists materials when only the material repo is up',
    () async {
      final materialApi = _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/materials') {
          return (
            statusCode: 200,
            body: jsonEncode([
              _materialDetailsJson(
                mediaRenditions: [
                  _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
                ],
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
                mediaRenditions: [
                  _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
                  _mediaRenditionJson(id: 'a2', mediaId: 'media-2'),
                ],
              ),
              _materialDetailsJson(
                materialId: 'material-2',
                revisionId: 'revision-2',
                title: 'Second',
                mediaRenditions: [
                  _mediaRenditionJson(id: 'a3', mediaId: 'media-3'),
                ],
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
                mediaRenditions: [
                  _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
                ],
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
                mediaRenditions: [
                  _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
                ],
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

  test('offlineLibrary keeps document rows offline without any media', () {
    final w = _wire(() => null);
    final textOnly = PersonalLibraryEntry(
      details: _materialDetails(
        documentRenditions: [documentRendition(id: 'text-1')],
      ),
      mediaEntries: const [],
    );
    w.coordinator.personalLibrary = [textOnly];

    // A document rendition's bytes are resolvable (managed or referenced):
    // no file exists to check, so the row is offline by itself.
    expect(w.coordinator.offlineLibrary, hasLength(1));
  });

  test('offlineLibrary keeps media rows only when the local file exists', () {
    final file = File(
      '${Directory.systemTemp.createTempSync('mlc').path}/m.mp4',
    )..writeAsStringSync('x');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final w = _wire(() => null);
    final present = _personalEntry(_libraryEntry(path: file.path));
    final missing = _personalEntry(_libraryEntry(id: 'media-2'));
    w.coordinator.personalLibrary = [present, missing];

    expect(w.coordinator.offlineLibrary, hasLength(1));
    expect(
      w.coordinator.offlineLibrary!.single.primaryMedia?.media.path,
      file.path,
    );
  });

  test('offlineLibrary keeps a mixed row with only its document rendition', () {
    final w = _wire(() => null);
    final mixed = PersonalLibraryEntry(
      details: _materialDetails(
        documentRenditions: [documentRendition(id: 'text-1')],
        mediaRenditions: [
          mediaRendition(
            id: 'asset-1',
            mediaId: 'media-gone',
            kind: MediaRenditionKind.audio,
            fingerprint: 'fp',
          ),
        ],
      ),
      mediaEntries: [_libraryEntry(id: 'media-gone')],
    );
    w.coordinator.personalLibrary = [mixed];

    // The media file is gone but the document rendition's bytes are still
    // resolvable: mixed rows need just one working capability to be offline.
    expect(w.coordinator.offlineLibrary, hasLength(1));
  });

  test('setLibraryTriageIntent keeps the authoritative list in sync', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'GET' && path == '/v1/materials') {
        return (
          statusCode: 200,
          body: jsonEncode([
            _materialDetailsJson(
              mediaRenditions: [
                _mediaRenditionJson(id: 'a1', mediaId: 'media-1'),
              ],
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
      w.coordinator.personalLibrary!.single,
      'pin_intensive',
    );

    expect(w.coordinator.mediaLibrary!.first.triageIntent, 'pin_intensive');
    expect(w.coordinator.personalLibrary!.single.triageIntent, 'pin_intensive');
    expect(w.rebuilds, hasLength(2));
  });

  test('openLibraryEntry guards a missing media file', () async {
    final w = _wire(() => null);

    await w.coordinator.openLibraryEntry(_personalEntry(_libraryEntry()));

    expect(w.player.status, 'mediaFileMissing');
    // The missing file is an error report, not an idle hint — it must render
    // in the error style wherever the status line exists.
    expect(w.player.statusIsError, isTrue);
    expect(w.openedPaths, isEmpty);
  });

  test('openLibraryEntry opens an existing media file', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mlc').path}/m.mp4',
    )..writeAsStringSync('x');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final w = _wire(() => null);

    await w.coordinator.openLibraryEntry(
      _personalEntry(_libraryEntry(path: file.path)),
    );

    expect(w.openedPaths, [file.path]);
  });

  test('openLibraryEntry ignores a text-only row', () async {
    final w = _wire(() => null);
    final textOnly = PersonalLibraryEntry(
      details: _materialDetails(
        documentRenditions: [documentRenditionForText('Hello', id: 'text-1')],
      ),
      mediaEntries: const [],
    );

    await w.coordinator.openLibraryEntry(textOnly);

    expect(w.openedPaths, isEmpty);
    expect(w.player.status, isNot('mediaFileMissing'));
  });

  test('startIntensiveFromLibrary guards a missing media file', () async {
    final w = _wire(() => null);

    await w.coordinator.startIntensiveFromLibrary(
      _personalEntry(_libraryEntry()),
    );

    expect(w.player.status, 'mediaFileMissing');
    expect(w.player.statusIsError, isTrue);
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
      _personalEntry(_libraryEntry()),
      'pin_intensive',
    );

    expect(w.coordinator.mediaLibrary!.first.triageIntent, 'pin_intensive');
    expect(w.rebuilds, isNotEmpty);
  });

  test('setLibraryTriageIntent ignores a text-only row', () async {
    final w = _wire(() => null);
    final textOnly = PersonalLibraryEntry(
      details: _materialDetails(
        documentRenditions: [documentRenditionForText('Hello', id: 'text-1')],
      ),
      mediaEntries: const [],
    );

    await w.coordinator.setLibraryTriageIntent(textOnly, 'defer');

    // Text materials have no media to triage: the status line stays untouched
    // (no core-unavailable complaint), no rebuild, and the media library stays
    // as it was.
    expect(w.player.status, 'Starting local core...');
    expect(w.rebuilds, isEmpty);
    expect(w.coordinator.mediaLibrary, isNull);
  });

  test('setLibraryTriageIntent without a core reports it', () async {
    final w = _wire(() => null);

    await w.coordinator.setLibraryTriageIntent(
      _personalEntry(_libraryEntry()),
      'defer',
    );

    expect(w.player.status, 'statusConnectLocalCoreFirst');
    expect(w.rebuilds, isEmpty);
  });

  test('setLibraryTriageIntent failure reports on the player status', () async {
    final api = _fakeApi(
      (method, path, body) => (statusCode: 500, body: 'boom'),
    );
    final w = _wire(() => api);

    await w.coordinator.setLibraryTriageIntent(
      _personalEntry(_libraryEntry()),
      'defer',
    );

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
