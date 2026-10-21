@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/models/document_format.dart';
import 'package:llplayer_next/models/document_session.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/services/composition_session_service.dart';
import 'package:llplayer_next/services/document_intake_flow.dart';
import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/services/document_reference_store.dart';
import 'package:llplayer_next/services/document_source_resolver.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';
import 'package:llplayer_next/services/capability_file_resolver.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

import 'e2e_database.dart';

String _python3Executable() {
  for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
    final candidate = File('$directory/python3');
    if (candidate.existsSync()) return candidate.path;
  }
  throw StateError('python3 is required for the Gen integration tests');
}

/// Real monorepo round trip: a locally built listen-gen release
/// bundle produces a Content Package v3 from a capability request, and a
/// locally built Core installs it as a candidate and then adopts it as the
/// Learning Edition. The coordinator drives the whole product path:
/// resolution, durable attempt, production, candidate installation, adoption,
/// and attempt finalize.
///
/// This exercises live subprocesses (the `.pyz` and the Core `api-http`
/// binary), so it is skipped unless `LISTEN_PACKAGE_E2E=1`. Drive it through
/// `tool/verify_local_content_package_roundtrip.sh`, which builds Core and Gen
/// from one isolated root snapshot and wires the environment. The
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
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final artifact = manifest['artifact'] as Map<String, dynamic>;
    final source = manifest['source'] as Map<String, dynamic>;
    final tool = manifest['tool'] as Map<String, dynamic>;
    final machineProtocol =
        manifest['machine_protocol'] as Map<String, dynamic>;
    final contract =
        manifest['content_package_contract'] as Map<String, dynamic>;
    final runtime = manifest['runtime'] as Map<String, dynamic>;
    final lock = <String, dynamic>{
      'manifest_version': 1,
      'repository': 'ichthyoplanktonzyh/listen',
      'source_git_sha': source['commit'],
      'release_manifest': {
        'schema': manifest['schema'],
        'filename': manifestFile.uri.pathSegments.last,
        'sha256': 'sha256:${sha256.convert(manifestBytes)}',
      },
      'tool': tool,
      'machine_protocol': machineProtocol,
      'content_package_contract': contract,
      'runtime': {'python_requires': runtime['python_requires']},
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
      expect(
        fixtureManifest['schema'],
        'listen_app.content-package-roundtrip-fixture.v3',
      );
      expect(fixtureManifest['source_repository'], 'ichthyoplanktonzyh/listen');
      expect(
        (fixtureManifest['media_streams']
            as Map<String, dynamic>)['sample-media.wav'],
        ['audio'],
      );
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
      expect(verified.toolVersion, isNotEmpty);

      final generator = LocalListenGenProcessService(
        pythonExecutable: _python3Executable,
        releaseService: release,
      );
      expect(
        generator.isConfigured,
        isTrue,
        reason:
            'LISTEN_GEN_RELEASE_MANIFEST must be configured for this round trip',
      );

      // Provider argv comes from the gate script (fixture ASR against the
      // pinned sample.asr.json); a local fallback keeps the test self-contained.
      final providerArguments =
          Platform.environment['LISTEN_GEN_PROVIDER_ARGUMENTS'] == null
          ? [
              '--provider',
              'fixture',
              '--fixture',
              '$fixtureRoot/sample.asr.json',
            ]
          : (jsonDecode(Platform.environment['LISTEN_GEN_PROVIDER_ARGUMENTS']!)
                    as List<dynamic>)
                .cast<String>();

      final api = await LocalApi.connect(databasePath: dbPath);
      MaterialCapabilityCoordinator? coordinator;
      try {
        // Register the fixture media, then resolve the material Core bound to
        // it. The material id and current revision anchor the round trip.
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        final activeCoordinator = MaterialCapabilityCoordinator(
          repository: LocalCapabilityRepository(() => api),
          generator: generator,
          mediaFilePath: (rendition) async =>
              rendition.mediaId == media.id ? mediaPath : null,
          providerArguments: () => providerArguments,
        );
        coordinator = activeCoordinator;

        // The fresh material has no adopted composition and no derivable
        // projection yet: the coordinator must resolve through production.
        final outcome = await activeCoordinator.requestCapability(
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
          edition.availableCapabilities,
          contains('read'),
          reason:
              'Core must expose the projected read capability on the edition',
        );
        expect(
          edition.renditions.map((rendition) => rendition.kind),
          contains('media'),
        );
        expect(
          edition.renditions.every((rendition) => rendition.kind == 'media'),
          isTrue,
          reason: 'Gen releases material only as audio/video renditions',
        );
        final resourceKinds = edition.resources
            .map((resource) => resource.kind)
            .toSet();
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
        expect(read.latestAttempt?.producerToolVersion, verified.toolVersion);

        // Re-requesting resolves through the adopted composition: no new
        // attempt is opened and the same edition comes back.
        final replay = await activeCoordinator.requestCapability(
          material,
          MaterialCapability.read,
        );
        expect(replay, isA<CapabilityAvailable>());
        expect(
          (replay as CapabilityAvailable).edition!.releaseId,
          edition.releaseId,
        );
      } finally {
        coordinator?.dispose();
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real monorepo round trip',
  );

  test(
    'local Gen document Listen binds the real Core source and App reads the adopted composition',
    () async {
      HttpOverrides.global = null;

      final dbPath = scratchDatabasePath('document-listen');
      final assetRoot = await Directory.systemTemp.createTemp(
        'listen-document-roundtrip-assets-',
      );
      addTearDown(() async {
        if (await assetRoot.exists()) await assetRoot.delete(recursive: true);
      });
      final referenceStore = DocumentReferenceStore(
        file: File(p.join(assetRoot.path, 'document-references.json')),
      );
      final assetStore = LocalManagedAssetStoreService(
        resolveRoot: () => assetRoot.path,
      );
      final api = await LocalApi.connect(databasePath: dbPath);
      MaterialCapabilityCoordinator? coordinator;
      DocumentSessionController? documentController;
      String? derivedAudioPath;
      try {
        final repository = LocalLearningMaterialRepository(() => api);
        const sourceText = 'Listen closely. Then listen once more.';
        final intakeFlow = DocumentIntakeFlow(
          materialRepository: repository,
          codec: LocalDocumentIntakeCodec(),
          store: assetStore,
          referenceStore: referenceStore,
        );

        // Take in the exact document bytes through App's real intake, which
        // creates the Core Source Asset and Document Rendition identities.
        final sourceBytes = utf8.encode(sourceText);
        final intake = await intakeFlow.takeInDocument(
          title: 'Offline TTS fixture',
          bytes: sourceBytes,
          format: DocumentFormat.plainText,
        );
        final material = intake.details;
        final sourceAsset = material.currentRevision.sourceAssets.single;
        final documentRendition =
            material.currentRevision.documentRenditions.single;
        expect(sourceAsset.id, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(documentRendition.sourceAssetId, sourceAsset.id);
        expect(documentRendition.digest, intake.sha256Digest);
        expect(documentRendition.byteSize, sourceBytes.length);

        final release = await releaseForProbeManifest();
        final verified = await release.verify();
        final generator = LocalListenGenProcessService(
          pythonExecutable: _python3Executable,
          releaseService: release,
        );
        expect(generator.isConfigured, isTrue);

        coordinator = MaterialCapabilityCoordinator(
          repository: LocalCapabilityRepository(() => api),
          generator: generator,
          // The deterministic fake synthesizer is bundled with Gen and needs
          // no model, network, or paid provider.
          providerArguments: () => const ['--tts-provider', 'fake'],
          fileResolver: LocalCapabilityFileResolver(
            managedStoreRoot: () => assetRoot.path,
          ),
        );

        final outcome = await coordinator.requestCapability(
          material,
          MaterialCapability.listen,
        );
        if (outcome is CapabilityFailed) {
          final error = outcome.error;
          if (error is ListenGenProcessFailure) {
            fail('document coordinator failed: ${error.code} ${error.message}');
          }
          fail('document coordinator failed: $error');
        }
        expect(outcome, isA<CapabilityAvailable>());
        final edition = (outcome as CapabilityAvailable).edition!;
        expect(edition.materialId, material.material.id);
        expect(edition.materialRevisionId, material.currentRevision.id);
        expect(edition.adopted, isTrue);
        expect(edition.availableCapabilities, contains('read'));
        expect(edition.availableCapabilities, contains('listen'));
        expect(
          edition.resources.map((resource) => resource.kind),
          contains('structured_reading'),
        );
        expect(
          edition.renditions.any((rendition) => rendition.kind == 'media'),
          isTrue,
        );

        // Source binding validation compares Gen's sha256:-prefixed package
        // identity to the exact raw Core SourceAsset ID created above.
        final adopted = await api.readAdoptedComposition(material.material.id);
        expect(
          adopted.renditions.where(
            (rendition) =>
                rendition.kind == 'document' && rendition.origin == 'source',
          ),
          hasLength(1),
        );
        final audio = adopted.derivedMediaRendition;
        expect(audio, isNotNull);
        final audioBytes = await api.readCompositionRenditionBlob(
          material.material.id,
          audio!.renditionId,
        );
        expect(audioBytes, isNotEmpty);

        // Exercise the same App document-session and Core composition read
        // that the workbench uses after generation completes.
        final retained = await api.retainLearningMaterial(material.material.id);
        final compositionService = CompositionSessionService(
          repository: LocalCapabilityRepository(() => api),
          resources: LocalResourceRepository(() => api),
        );
        documentController = DocumentSessionController(
          materialRepository: repository,
          fileService: const LocalDocumentIntakeFileService(),
          intakeFlow: intakeFlow,
          sourceResolver: LocalDocumentSourceResolver(
            store: assetStore,
            referenceStore: referenceStore,
            resolveStoreRoot: () => assetRoot.path,
          ),
          resolveComposition: compositionService.resolveComposition,
        );
        documentController.openLibraryEntry(
          PersonalLibraryEntry(details: retained, mediaEntries: const []),
        );
        expect(documentController.state, isA<DocumentSessionReady>());
        final sourceRead = await documentController.resolveSourceBytes(
          sourceAsset,
        );
        expect(sourceRead, isA<DocumentSourceAvailable>());
        expect(
          utf8.decode((sourceRead as DocumentSourceAvailable).bytes),
          sourceText,
        );

        await documentController.refreshComposition();
        final ready = documentController.state as DocumentSessionReady;
        final composition = ready.composition;
        expect(composition, isNotNull);
        expect(composition!.logicalText, sourceText);
        expect(composition.derivedMediaPath, isNotNull);
        derivedAudioPath = composition.derivedMediaPath;
        expect(await File(derivedAudioPath!).length(), audioBytes.length);

        final listen =
            (await api.listMaterialCapabilities(
              material.material.id,
            )).singleWhere(
              (projection) =>
                  projection.capability == MaterialCapability.listen,
            );
        expect(listen.status, MaterialCapabilityStatus.available);
        expect(listen.latestAttempt?.status, 'succeeded');
        expect(listen.latestAttempt?.producerToolVersion, verified.toolVersion);
      } finally {
        documentController?.dispose();
        coordinator?.dispose();
        await api.close();
        final path = derivedAudioPath;
        if (path != null) {
          final directory = Directory(p.dirname(path));
          if (await directory.exists()) await directory.delete(recursive: true);
        }
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real monorepo round trip',
  );
}
