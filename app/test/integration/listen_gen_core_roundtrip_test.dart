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
import 'package:llplayer_next/services/composition_store.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

/// Real three-repository round trip: the pinned listen-gen release bundle
/// produces a Content Package v3 from a capability request, and the pinned
/// Core installs it as a candidate and then adopts it as the Learning Edition.
/// The coordinator drives the whole product path: resolution, durable attempt,
/// production, candidate installation, adoption, and attempt finalize.
///
/// This exercises live subprocesses (the verified `.pyz` and the Core
/// `api-http` binary), so it is skipped unless `LISTEN_PACKAGE_E2E=1`. Drive it
/// through `tool/verify_local_content_package_roundtrip.sh`, which builds both
/// external repositories at their pinned commits and wires the environment.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  test(
    'pinned Gen 0.5.0 bundle to Core 4.0 round trips through capability '
    'production, installation, and adoption',
    () async {
      // TestWidgetsFlutterBinding installs an HttpOverrides that stubs every
      // request to status 400. This test talks to a real Core sidecar, so drop
      // the override and use the platform HttpClient. The binding is still what
      // lets `rootBundle` read the committed lock asset.
      HttpOverrides.global = null;

      const fixtureRoot = 'test/fixtures/content-package-roundtrip';

      // The test owns its fixtures; verify their bytes before trusting them
      // and never reach into a sibling Gen checkout.
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

      // Verify the pinned release from the committed asset lock + env manifest.
      final release = LocalListenGenReleaseService();
      expect(
        release.isConfigured,
        isTrue,
        reason: 'LISTEN_GEN_RELEASE_MANIFEST must point at the pinned manifest',
      );
      final verified = await release.verify();
      expect(verified.toolVersion, '0.5.0');
      expect(
        verified.artifactSha256,
        'sha256:946c0b40a2d4d4ccd32915b5f54ac58644755b24a127af637f8a460819cb7ef5',
      );

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

      final api = await LocalApi.connect();
      try {
        // Register the fixture media, then resolve the material Core bound to
        // it. The material id and current revision anchor the round trip.
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        final coordinator = MaterialCapabilityCoordinator(
          repository: LocalCapabilityRepository(() => api),
          generator: generator,
          targetLanguage: () => 'en-US',
          mediaFilePath: (rendition) =>
              rendition.mediaId == media.id ? mediaPath : null,
          providerArguments: providerArguments,
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
        // document text, structured reading, and time alignment resources.
        expect(edition.providesRead, isTrue);
        expect(
          edition.renditions.map((rendition) => rendition.kind),
          contains('media'),
        );
        final resourceKinds =
            edition.resources.map((resource) => resource.kind).toSet();
        expect(
          resourceKinds,
          containsAll(const [
            'document_text',
            'structured_reading',
            'anchor_time_alignment',
          ]),
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
    'its derived audio resolves from the retained carrier',
    () async {
      HttpOverrides.global = null;

      final release = LocalListenGenReleaseService();
      final verified = await release.verify();
      expect(verified.toolVersion, '0.5.0');

      final generator = LocalListenGenProcessService(releaseService: release);
      final api = await LocalApi.connect();
      final storeRoot = Directory.systemTemp.createTempSync('e2e-store-');
      final coordinator = MaterialCapabilityCoordinator(
        repository: LocalCapabilityRepository(() => api),
        generator: generator,
        targetLanguage: () => 'en-US',
        providerArguments: const ['--tts-provider', 'fake'],
        compositionStore: CompositionStore(root: storeRoot.path),
      );
      try {
        final created = await api.createLearningMaterial(
          CreateLearningMaterialInput(
            title: 'Document listen lesson',
            sourceAssets: const [],
            documentRenditions: [
              DocumentRenditionInput(
                mediaType: 'text/plain',
                text: 'Listen, carefully! Words matter.',
                language: 'en',
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
          containsAll(const ['document_text', 'anchor_time_alignment']),
        );

        // The retained carrier resolves the produced audio for the player.
        final store = CompositionStore(root: storeRoot.path);
        final composition = await store.resolve(
          materialId: created.material.id,
          releaseId: edition.releaseId,
        );
        expect(composition, isNotNull);
        expect(composition!.derivedMediaPath, isNotNull);
        expect(
          await File(composition.derivedMediaPath!).length(),
          greaterThan(0),
        );
        expect(composition.alignments, isNotEmpty);
        expect(composition.sentences, isNotEmpty);

        coordinator.dispose();
      } finally {
        await api.close();
        storeRoot.deleteSync(recursive: true);
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real three-repository round trip',
  );
}
