@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/capability_file_resolver.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

import 'e2e_database.dart';

/// Real three-repository round trip: a locally built listen-gen release
/// bundle produces a Content Package v3 from a capability request, and a
/// locally built Core installs it as a candidate and then adopts it as the
/// Learning Edition. The coordinator drives the whole product path:
/// resolution, durable attempt, production, candidate installation, adoption,
/// and attempt finalize.
///
/// This exercises live subprocesses (the `.pyz` and the Core `api-http`
/// binary), so it is skipped unless `LISTEN_PACKAGE_E2E=1`. Drive it through
/// `tool/verify_local_content_package_roundtrip.sh`, which builds both
/// external repositories at their local HEAD and wires the environment. The
/// production `listen_gen.lock.json` is deliberately not touched: the test
/// derives an equivalent lock from the freshly built manifest so the
/// product's release verification runs against the exact probe artifact.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  /// Derive a release lock from the freshly built release manifest so
  /// [LocalListenGenReleaseService.verify] can validate the probe artifact
  /// without touching the committed production lock. Every field the lock
  /// parser and the manifest validator require is copied from the manifest;
  /// the manifest hash is computed from the on-disk bytes.
  Future<LocalListenGenReleaseService> releaseForProbeManifest() async {
    final manifestPath = Platform.environment['LISTEN_GEN_RELEASE_MANIFEST'];
    expect(
      manifestPath,
      isNotNull,
      reason: 'LISTEN_GEN_RELEASE_MANIFEST must point at the probe manifest',
    );
    final manifestFile = File(manifestPath!);
    final manifestBytes = await manifestFile.readAsBytes();
    final manifest = jsonDecode(utf8.decode(manifestBytes))
        as Map<String, dynamic>;
    final artifact = manifest['artifact'] as Map<String, dynamic>;
    final source = manifest['source'] as Map<String, dynamic>;
    final tool = manifest['tool'] as Map<String, dynamic>;
    final machineProtocol = manifest['machine_protocol'] as Map<String, dynamic>;
    final contract = manifest['content_package_contract'] as Map<String, dynamic>;
    final runtime = manifest['runtime'] as Map<String, dynamic>;
    final lock = <String, dynamic>{
      'manifest_version': 1,
      'repository': 'ichthyoplanktonzyh/listen-gen',
      'source_git_sha': source['commit'],
      'release_manifest': {
        'schema': manifest['schema'],
        'filename': manifestFile.uri.pathSegments.last,
        'sha256': 'sha256:${sha256.convert(manifestBytes)}',
      },
      'tool': tool,
      'machine_protocol': machineProtocol,
      'content_package_contract': contract,
      'runtime': {
        'python_requires': runtime['python_requires'],
      },
      'runtime_identity': manifest['runtime_identity'],
      'artifact': artifact,
    };
    return LocalListenGenReleaseService(
      manifestPath: manifestPath,
      loadLockBytes: () async => utf8.encode(jsonEncode(lock)),
    );
  }

  test(
    'local Gen bundle to local Core round trips through capability '
    'production, installation, and adoption',
    () async {
      // TestWidgetsFlutterBinding installs an HttpOverrides that stubs every
      // request to status 400. This test talks to a real Core sidecar, so drop
      // the override and use the platform HttpClient.
      HttpOverrides.global = null;

      const fixtureRoot = 'test/fixtures/content-package-roundtrip';

      // The test owns its fixtures; verify their bytes before trusting them
      // and never reach into a sibling Gen checkout.
      final dbPath = scratchDatabasePath('roundtrip-read');
      final fixtureManifest =
          jsonDecode(await File('$fixtureRoot/manifest.json').readAsString())
              as Map<String, dynamic>;
      final files = fixtureManifest['files'] as Map<String, dynamic>;
      for (final entry in files.entries) {
        final bytes = await File('$fixtureRoot/${entry.key}').readAsBytes();
        expect(
          sha256.convert(bytes).toString(),
          entry.value,
          reason: 'fixture ${entry.key} does not match its pinned hash',
        );
      }
      final mediaPath = File('$fixtureRoot/sample-media.wav').absolute.path;

      // Verify the freshly built probe release: manifest and artifact must
      // pass the product's release verification against the derived lock.
      final release = await releaseForProbeManifest();
      final verified = await release.verify();
      expect(verified.toolVersion, '0.5.0');

      final generator = LocalListenGenProcessService(releaseService: release);
      expect(
        generator.isConfigured,
        isTrue,
        reason:
            'LISTEN_GEN_RELEASE_MANIFEST must be configured for this round trip',
      );

      // Provider argv comes from the gate script (fixture ASR against the
      // pinned sample.asr.json); a local fallback keeps the test self-contained.
      final providerArguments = Platform.environment['LISTEN_GEN_PROVIDER_ARGUMENTS'] == null
          ? [
              '--provider',
              'fixture',
              '--fixture',
              '$fixtureRoot/sample.asr.json',
            ]
          : (jsonDecode(
                  Platform.environment['LISTEN_GEN_PROVIDER_ARGUMENTS']!) as List<dynamic>)
              .cast<String>();

      final api = await LocalApi.connect(databasePath: dbPath);
      try {
        // Register the fixture media, then resolve the material Core bound to
        // it. The material id and current revision anchor the round trip.
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        final coordinator = MaterialCapabilityCoordinator(
          repository: LocalCapabilityRepository(() => api),
          generator: generator,
          mediaFilePath: (rendition) async =>
              rendition.mediaId == media.id ? mediaPath : null,
          providerArguments: () => providerArguments,
        );

        // The fresh material has no adopted composition and no derivable
        // projection yet: the coordinator must resolve through production.
        final outcome = await coordinator.requestCapability(
          material,
          MaterialCapability.read,
        );
        if (outcome is CapabilityFailed) {
          final error = outcome.error;
          if (error is ListenGenProcessFailure) {
            fail('coordinator failed: ${error.code} ${error.message}');
          }
          fail('coordinator failed: $error');
        }
        expect(outcome, isA<CapabilityAvailable>());

        final edition = (outcome as CapabilityAvailable).edition!;

        // ── Edition assertions ──
        expect(edition.materialId, material.material.id);
        expect(edition.adopted, isTrue);
        expect(edition.adoptedAtMs, isNotNull);

        // The read derivation produced a playable media rendition plus the
        // structured reading and time alignment resources.
        expect(edition.providesRead, isTrue);
        expect(
          edition.renditions.map((rendition) => rendition.kind),
          contains('media'),
        );
        final resourceKinds =
            edition.resources.map((resource) => resource.kind).toSet();
        expect(
          resourceKinds,
          containsAll(const ['structured_reading', 'anchor_time_alignment']),
        );

        // ── Durable attempt assertions ──
        final projections = await api.listMaterialCapabilities(
          material.material.id,
        );
        final read = projections.singleWhere(
          (projection) => projection.capability == MaterialCapability.read,
        );
        expect(read.status, MaterialCapabilityStatus.available);
        expect(read.latestAttempt?.status, 'succeeded');
        expect(read.latestAttempt?.producerToolId, 'listen-gen');
        expect(read.latestAttempt?.producerToolVersion, '0.5.0');

        // Re-requesting resolves through the adopted composition: no new
        // attempt is opened and the same edition comes back.
        final replay = await coordinator.requestCapability(
          material,
          MaterialCapability.read,
        );
        expect(replay, isA<CapabilityAvailable>());
        expect(
          (replay as CapabilityAvailable).edition!.releaseId,
          edition.releaseId,
        );
        coordinator.dispose();
      } finally {
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real three-repository round trip',
  );

  test(
    'a document material produces listen through the fake TTS provider and '
    'its derived audio resolves from the adopted composition through Core',
    () async {
      HttpOverrides.global = null;

      final release = await releaseForProbeManifest();
      final verified = await release.verify();
      expect(verified.toolVersion, '0.5.0');

      final generator = LocalListenGenProcessService(releaseService: release);
      final dbPath = scratchDatabasePath('roundtrip-listen');
      final api = await LocalApi.connect(databasePath: dbPath);
      final managedRoot =
          await Directory.systemTemp.createTemp('roundtrip-managed');
      final coordinator = MaterialCapabilityCoordinator(
        repository: LocalCapabilityRepository(() => api),
        generator: generator,
        providerArguments: () => const ['--tts-provider', 'fake'],
        fileResolver: LocalCapabilityFileResolver(
          // The managed store is content-addressed: the learner-authorized
          // bytes live at <root>/<digest>, exactly as the App stores them.
          managedStorePath: (SourceAsset asset) =>
              '${managedRoot.path}/${asset.sha256Digest}',
        ),
      );
      try {
        final sourceBytes = utf8.encode('Listen, carefully! Words matter.');
        final digest = sha256.convert(sourceBytes).toString();
        await File('${managedRoot.path}/$digest').writeAsBytes(sourceBytes);
        final created = await api.createLearningMaterial(
          CreateLearningMaterialInput(
            title: 'Document listen lesson',
            sourceAssets: [
              SourceAssetInput(
                mediaType: 'text/plain',
                byteLength: sourceBytes.length,
                sha256Digest: sha256.convert(sourceBytes).toString(),
                binding: const SourceAssetBinding(
                  type: SourceAssetBindingType.managed,
                ),
              ),
            ],
            documentRenditions: [
              DocumentRenditionInput(
                mediaType: 'text/plain',
                digest: sha256.convert(sourceBytes).toString(),
                byteSize: sourceBytes.length,
                language: 'en',
                sourceAssetIndex: 0,
              ),
            ],
            mediaRenditions: const [],
          ),
        );

        final outcome = await coordinator.requestCapability(
          created,
          MaterialCapability.listen,
        );
        if (outcome is CapabilityFailed) {
          final error = outcome.error;
          if (error is ListenGenProcessFailure) {
            fail('listen failed: ${error.code} ${error.message}');
          }
          fail('listen failed: $error');
        }
        expect(outcome, isA<CapabilityAvailable>());
        final edition = (outcome as CapabilityAvailable).edition!;
        expect(edition.adopted, isTrue);

        // The fake TTS derivation produced a playable media rendition and the
        // synchronized alignment resources.
        expect(edition.hasAvailableMediaRendition, isTrue);
        expect(edition.providesSynchronizedReadListen, isTrue);
        expect(
          edition.resources.map((resource) => resource.kind),
          containsAll(const ['structured_reading', 'anchor_time_alignment']),
        );

        // The adopted composition resolves through Core's composition
        // interface — never through an app-side retained carrier: the reading
        // structure, the alignment, and the produced audio come back from
        // Core, re-verified by it.
        final repository = LocalCapabilityRepository(() => api);
        final adopted = await repository.readAdoptedComposition(
          created.material.id,
        );
        expect(adopted.releaseId, edition.releaseId);
        final sr = adopted.resourceOfKind('structured_reading');
        expect(sr, isNotNull);
        final srPayload = await repository.readCompositionResourcePayload(
          created.material.id,
          sr!.resourceId,
        );
        final srJson = jsonDecode(utf8.decode(srPayload))
            as Map<String, dynamic>;
        expect(srJson['text'], isNotEmpty);
        final media = adopted.derivedMediaRendition;
        expect(media, isNotNull);
        final blob = await repository.readCompositionRenditionBlob(
          created.material.id,
          media!.renditionId,
        );
        expect(blob, isNotEmpty);

        coordinator.dispose();
      } finally {
        await managedRoot.delete(recursive: true);
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real three-repository round trip',
  );
}
