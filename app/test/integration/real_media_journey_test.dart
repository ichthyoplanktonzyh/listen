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
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

import 'e2e_database.dart';

/// Real-media (fixture-ASR) journey against the real local stack, driven by
/// `REAL_MEDIA_PATH` pointing at a local audio/video file (for example a file
/// from the read-only desktop sample folder). The path is never committed:
/// without the environment variable the test is skipped.
///
/// The media file is real; the Structured Reading comes from the committed
/// fixture ASR transcript, so this is a fixture-backed journey, not a real
/// transcription. The journey: register and open the real media, produce
/// Structured Reading through capability production, install and adopt the
/// edition, then restart the Core sidecar against the same database and
/// reopen the same material — the adopted composition must still satisfy the
/// capability without a new attempt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';
  final realMediaPath = Platform.environment['REAL_MEDIA_PATH'];

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
    'a real media file opens, gains structured reading from the fixture ASR, '
    'survives a sidecar restart, and reopens from the adopted composition',
    () async {
      HttpOverrides.global = null;
      expect(realMediaPath, isNotNull, reason: 'REAL_MEDIA_PATH is required');
      final mediaPath = File(realMediaPath!).absolute.path;
      expect(File(mediaPath).existsSync(), isTrue,
          reason: 'REAL_MEDIA_PATH must exist');

      final dbPath = scratchDatabasePath('real-media');
      final release = await releaseForProbeManifest();
      final generator = LocalListenGenProcessService(releaseService: release);

      final api = await LocalApi.connect(databasePath: dbPath);
      late String mediaId;
      try {
        final media = await api.registerMedia(mediaPath, retain: false);
        mediaId = media.id;
        final material = await api.resolveMaterialForMedia(media.id);

        final coordinator = MaterialCapabilityCoordinator(
          repository: LocalCapabilityRepository(() => api),
          generator: generator,
          mediaFilePath: (rendition) =>
              rendition.mediaId == media.id ? mediaPath : null,
          providerArguments: () => const [
            '--provider',
            'fixture',
            '--fixture',
            'test/fixtures/content-package-roundtrip/sample.asr.json',
          ],
        );
        final outcome = await coordinator.requestCapability(
          material,
          MaterialCapability.read,
        );
        expect(outcome, isA<CapabilityAvailable>(),
            reason: 'real media must gain a read capability');
        final edition = (outcome as CapabilityAvailable).edition!;
        expect(edition.adopted, isTrue);
        expect(edition.providesRead, isTrue);
        final releaseId = edition.releaseId;
        coordinator.dispose();

        // Restart: a fresh sidecar on the same database.
        await api.close();
        final restarted = await LocalApi.connect(databasePath: dbPath);
        try {
          final material2 = await restarted.resolveMaterialForMedia(mediaId);
          final projections = await restarted.listMaterialCapabilities(
            material2.material.id,
          );
          final read = projections.singleWhere(
            (projection) =>
                projection.capability == MaterialCapability.read,
          );
          expect(read.status, MaterialCapabilityStatus.available);
          expect(read.latestAttempt?.status, 'succeeded');

          // Reopen through the coordinator: the adopted composition answers
          // without opening a new attempt.
          final replay = MaterialCapabilityCoordinator(
            repository: LocalCapabilityRepository(() => restarted),
            generator: generator,
            mediaFilePath: (rendition) =>
                rendition.mediaId == mediaId ? mediaPath : null,
            providerArguments: () => const [
              '--provider',
              'fixture',
              '--fixture',
              'test/fixtures/content-package-roundtrip/sample.asr.json',
            ],
          );
          final reopened = await replay.requestCapability(
            material2,
            MaterialCapability.read,
          );
          expect(reopened, isA<CapabilityAvailable>());
          expect(
            (reopened as CapabilityAvailable).edition!.releaseId,
            releaseId,
            reason: 'reopen must resolve the same adopted edition',
          );
          replay.dispose();
        } finally {
          await restarted.close();
        }
      } finally {
        await api.close();
      }
    },
    skip: (runE2e && realMediaPath != null)
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 and REAL_MEDIA_PATH for the real-media journey',
  );
}
