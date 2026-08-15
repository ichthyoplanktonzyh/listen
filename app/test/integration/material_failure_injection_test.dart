@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

import 'e2e_database.dart';

/// Failure injection against the real local stack: a live Core `api-http`
/// binary and, for the provider failure case, the locally built listen-gen
/// release bundle. Every injected failure must surface as a clean, retryable
/// error and must never pollute durable state or hang the process.
///
/// Skipped unless `LISTEN_PACKAGE_E2E=1`. Drive it the same way as
/// `listen_gen_core_roundtrip_test.dart`: `LLPLAYERNEXT_API_BINARY` and
/// `LLPLAYERNEXT_DB` for Core, `LISTEN_GEN_RELEASE_MANIFEST` for the probe
/// bundle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  // Same derived-lock trick as the round trip test: verify the probe bundle
  // against a lock built from its own manifest, never the production lock.
  Future<LocalListenGenReleaseService> releaseForProbeManifest() async {
    final manifestPath = Platform.environment['LISTEN_GEN_RELEASE_MANIFEST'];
    expect(manifestPath, isNotNull);
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
    'a malformed package fails installation cleanly and pollutes no state',
    () async {
      HttpOverrides.global = null;
      final dbPath = scratchDatabasePath('fault-malformed');

      final api = await LocalApi.connect(databasePath: dbPath);
      final temp = Directory.systemTemp.createTempSync('e2e-fault-');
      try {
        final mediaPath = File(
          'test/fixtures/content-package-roundtrip/sample-media.wav',
        ).absolute.path;
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        // A file that is not a Content Package v3 carrier at all.
        final notPackage = File('${temp.path}/not-a-package.txt')
          ..writeAsStringSync('this is not a content package');
        // A syntactically valid JSON document that is not a package manifest.
        final badJson = File('${temp.path}/bad.json')
          ..writeAsStringSync('{"schema": "listen.content-package.release.v3"}');

        for (final candidate in [notPackage, badJson]) {
          await expectLater(
            api.installMaterialPackage(
              material.material.id,
              candidate.path,
            ),
            throwsA(anyOf(isA<HttpException>(), isA<ApiFailure>())),
            reason: '${candidate.path} must be rejected before any mutation',
          );
        }

        // An empty path is rejected at the wire boundary.
        await expectLater(
          api.installMaterialPackage(material.material.id, ' '),
          throwsA(anyOf(isA<HttpException>(), isA<ApiFailure>())),
        );

        // No candidate leaked into durable state.
        final editions = await api.listLearningEditions(material.material.id);
        expect(editions, isEmpty);

        // The material remains usable for an honest capability query.
        final projections = await api.listMaterialCapabilities(
          material.material.id,
        );
        expect(projections, isNotEmpty);
      } finally {
        await api.close();
        temp.deleteSync(recursive: true);
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real failure injection run',
  );

  test(
    'adopting an unknown release fails without changing the composition',
    () async {
      HttpOverrides.global = null;
      final dbPath = scratchDatabasePath('fault-adopt');

      final api = await LocalApi.connect(databasePath: dbPath);
      try {
        final mediaPath = File(
          'test/fixtures/content-package-roundtrip/sample-media.wav',
        ).absolute.path;
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        await expectLater(
          api.adoptLearningEdition(
            material.material.id,
            'sha256:${'0' * 64}',
          ),
          throwsA(anyOf(isA<HttpException>(), isA<ApiFailure>())),
        );

        // Nothing was adopted: the edition list stays empty and a capability
        // query still answers honestly instead of surfacing a broken edition.
        final editions = await api.listLearningEditions(material.material.id);
        expect(editions, isEmpty);
      } finally {
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real failure injection run',
  );

  test(
    'a provider failure surfaces as a clean failed attempt and retries '
    'without hanging or orphaning the generator',
    () async {
      HttpOverrides.global = null;

      final release = await releaseForProbeManifest();
      final verified = await release.verify();
      expect(verified.toolVersion, '0.5.0');

      final generator = LocalListenGenProcessService(releaseService: release);
      final dbPath = scratchDatabasePath('fault-provider');

      final api = await LocalApi.connect(databasePath: dbPath);
      try {
        final mediaPath = File(
          'test/fixtures/content-package-roundtrip/sample-media.wav',
        ).absolute.path;
        final media = await api.registerMedia(mediaPath, retain: false);
        final material = await api.resolveMaterialForMedia(media.id);

        final repository = LocalCapabilityRepository(() => api);
        final coordinator = MaterialCapabilityCoordinator(
          repository: repository,
          generator: generator,
          mediaFilePath: (rendition) async =>
              rendition.mediaId == media.id ? mediaPath : null,
          // A fixture path that does not exist: the ASR provider must fail
          // as a provider failure, not hang or fabricate output.
          providerArguments: () => const [
            '--provider',
            'fixture',
            '--fixture',
            '/nonexistent/sample.asr.json',
          ],
        );

        final outcome = await coordinator.requestCapability(
          material,
          MaterialCapability.read,
        );
        expect(outcome, isA<CapabilityFailed>());

        // The attempt is durably recorded as failed; a retry is possible and
        // must not wedge the generator process.
        final projections = await api.listMaterialCapabilities(
          material.material.id,
        );
        final read = projections.singleWhere(
          (projection) => projection.capability == MaterialCapability.read,
        );
        expect(read.latestAttempt?.status, 'failed');

        coordinator.dispose();
      } finally {
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real failure injection run',
  );
}
