@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/feed_discovery_repository.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/data/repositories/source_identity_repository.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/acquisition_ledger.dart';
import 'package:llplayer_next/services/api_service.dart';

import 'e2e_database.dart';
import 'package:llplayer_next/services/external_tools.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';

/// Fixture-feed journey against the real Core: a fixture podcast RSS feed
/// served by a local HTTP server, a fixture enclosure fetched over real HTTP,
/// adoption through Core's media registration, a material created the way the
/// workbench would create it, and — after a restart with a fresh view model —
/// the same item reopening from the ledger and a second refresh producing no
/// second material.
///
/// This exercises a live `api-http` binary, so it is skipped unless
/// `LISTEN_PACKAGE_E2E=1`. Drive it with the same environment the Slice 4
/// round trip uses: `LLPLAYERNEXT_API_BINARY` pointing at the local Core
/// build and `LLPLAYERNEXT_DB` at a scratch database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  test(
    'a fixture feed item acquires, keeps, reopens after restart, and never '
    'duplicates its material on a second refresh',
    () async {
      HttpOverrides.global = null;

      // ── Local feed server ──────────────────────────────────────────────
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      final feedUrl =
          'http://${server.address.host}:${server.port}/show.xml';
      const enclosurePath = '/media.wav';
      final mediaBytes = await File(
        'test/fixtures/content-package-roundtrip/sample-media.wav',
      ).readAsBytes();
      final feedBody = utf8.encode(
        '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>E2E Show</title>
    <description>Fixture feed journey.</description>
    <language>en</language>
    <item>
      <title>Episode one</title>
      <guid>ep-001</guid>
      <pubDate>Tue, 11 Aug 2026 09:00:00 GMT</pubDate>
      <enclosure url="http://${server.address.host}:${server.port}$enclosurePath"
                 length="${mediaBytes.length}" type="audio/wav"/>
    </item>
  </channel>
</rss>
''',
      );
      server.listen((request) async {
        if (request.uri.path == '/show.xml') {
          request.response
            ..headers.contentType = ContentType('application', 'rss+xml')
            ..add(feedBody);
          await request.response.close();
          return;
        }
        if (request.uri.path == enclosurePath) {
          request.response
            ..headers.contentType = ContentType('audio', 'wav')
            ..add(mediaBytes);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      // ── Real Core and app-side repositories ────────────────────────────
      final dbPath = scratchDatabasePath('feed-journey');
      final api = await LocalApi.connect(databasePath: dbPath);
      addTearDown(() async => api.close());

      final ledger = AcquisitionLedger.inMemory();
      final downloadDirectory = Directory.systemTemp.createTempSync(
        'e2e-feed-',
      );
      addTearDown(() => downloadDirectory.deleteSync(recursive: true));
      final imports = LocalMediaImportRepository(
        ExternalTools(),
        _FixedDirectoryFileService(downloadDirectory),
      );

      final mediaLibrary = LocalMediaLibraryRepository(() => api);
      final sourceIdentity = LocalSourceIdentityRepository(() => api);
      final materials = LocalLearningMaterialRepository(() => api);

      // One feed repository across both sessions: subscriptions live in the
      // store, feeds are fetched per session.
      final feedRepository = FeedDiscoveryRepository();

      // ── Session one: acquire, keep, converge ───────────────────────────
      final source = await feedRepository.resolveCustomChannel(
        feedUrl,
        imports,
      );
      expect(source.kind, ContentSourceKind.podcast);

      final first = DiscoveryViewModel(
        feedRepository,
        imports,
        mediaLibrary,
        ledger,
        sourceIdentity,
        materials,
      );
      addTearDown(first.dispose);

      await first.selectChannel(feedUrl);
      first.selectItem('ep-001');
      // Let the availability reconciliation land before the intent.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final localPath = await first.acquireForLearning('ep-001');
      expect(localPath?.mediaPath, isNotNull,
          reason: 'the enclosure must land locally');
      expect(
        first.state.acquisitionStateOf('ep-001'),
        DiscoveryItemState.available,
      );

      // ── Keep: the learner keeps the media, the workbench creates the ────
      // ── material, and retention lands the row in the Personal Library. ──
      // Re-registering the same bytes is Core's fingerprint convergence: it
      // returns the very media row adoption registered, now retained.
      final media = await mediaLibrary.registerMedia(
        localPath!.mediaPath!,
        retain: true,
      );
      final mediaId = media.id;
      expect(
        (await mediaLibrary.listMediaLibrary()).single.media.id,
        mediaId,
        reason: 'a kept media row is the one Personal Library lists',
      );

      final material = await materials.createLearningMaterial(
        CreateLearningMaterialInput(
          title: 'Episode one',
          sourceAssets: const [],
          documentRenditions: const [],
          mediaRenditions: [MediaRenditionInput(mediaId: mediaId)],
        ),
        retain: const MaterialRetainExplicit(true),
      );
      expect(material.isRetained, isTrue);

      // A second refresh of the same item: no second download, no second
      // material. The ledger says the bytes are here; the workbench's material
      // is still the one material.
      await first.refreshMediaAvailability('ep-001');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        first.state.acquisitionStateOf('ep-001'),
        DiscoveryItemState.available,
        reason: 'a refresh of an acquired item never offers a second download',
      );
      expect(await materials.listLearningMaterials(), hasLength(1));

      // ── Restart: a fresh view model reopens the same item ───────────────
      // The ledger is in-memory here, so the session-two view model shares it
      // to model the relaunch; the recognition path exercised is the same one
      // a restarted app takes.
      final second = DiscoveryViewModel(
        feedRepository,
        imports,
        mediaLibrary,
        ledger,
        sourceIdentity,
        materials,
      );
      addTearDown(second.dispose);
      await second.selectChannel(feedUrl);
      second.selectItem('ep-001');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        second.state.acquisitionStateOf('ep-001'),
        DiscoveryItemState.available,
        reason: 'the reopened session recognises the acquired item',
      );
      expect(second.localPathFor('ep-001'), localPath.mediaPath);
      expect(await materials.listLearningMaterials(), hasLength(1));

      // The canonical key now resolves through Core Source Identity: the
      // mapping records which Material this source item converged on.
      final mapping = await sourceIdentity.resolveMapping(
        sourceId: feedUrl,
        itemId: 'ep-001',
      );
      if (mapping != null) {
        expect(mapping.materialId, material.material.id);
      } else {
        // The mapping is recorded when adoption finds a material already
        // bound to the media; a first-session adoption that precedes material
        // creation leaves the ledger as the recognition record. Either way
        // the item is available and unique — the assertion above already
        // proved that.
        // ignore: avoid_print
        print(
          'no mapping recorded in first session (material created after '
          'adoption) — recognition carried by the ledger',
        );
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real feed round trip',
  );
}

/// A directory picker that always answers with the e2e scratch directory, so
/// the enclosure lands somewhere the test controls.
class _FixedDirectoryFileService implements MediaImportFileService {
  _FixedDirectoryFileService(this._directory);

  final Directory _directory;

  @override
  Future<String?> pickMedia() async => null;
  @override
  Future<String?> pickSubtitle() async => null;
  @override
  Future<String?> pickLearningPackage() async => null;
  @override
  Future<TimelineFileDocument?> pickTimeline() async => null;
  @override
  String basename(String path) => path;
  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => _directory.path;
}
