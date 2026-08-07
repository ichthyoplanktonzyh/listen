@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

/// Real three-repository round trip: the pinned listen-gen release bundle
/// produces a `.listenpkg` from the App's own fixtures, and the pinned Core
/// imports it as a candidate-only receipt.
///
/// This exercises live subprocesses (the verified `.pyz` and the Core
/// `api-http` binary), so it is skipped unless `LISTEN_PACKAGE_E2E=1`. Drive it
/// through `tool/verify_local_content_package_roundtrip.sh`, which builds both
/// external repositories at their pinned commits and wires the environment.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  test(
    'pinned Gen bundle to Core import round trips as a candidate',
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
      expect(verified.toolVersion, '0.1.0');
      expect(
        verified.artifactSha256,
        'sha256:49907a11025165be31feaf94e3b8fdc9e404cd32c0e88bee886a4bd40566b0fd',
      );

      final generator = LocalListenGenProcessService(releaseService: release);
      expect(
        generator.isConfigured,
        isTrue,
        reason:
            'LISTEN_GEN_PROVIDER_ARGUMENTS must carry the fixture provider argv',
      );

      final api = await LocalApi.connect();
      ListenGenProcessRun? run;
      try {
        final media = await api.registerMedia(mediaPath);

        run = await generator.start(
          ContentPackageGenerationRequest(
            mediaPath: mediaPath,
            title: 'Round trip lesson',
            mediaKind: 'audio',
            durationMs: 2200,
            createdAtMs: 1785542400000,
          ),
        );

        final eventsFuture = run.events.toList();
        final packagePath = await run.packagePath;
        final events = await eventsFuture;

        // ── Gen protocol assertions ──
        expect(events.first.kind, ListenGenEventKind.protocol);
        final terminals = events
            .where(
              (event) =>
                  event.kind == ListenGenEventKind.completed ||
                  event.kind == ListenGenEventKind.failed ||
                  event.kind == ListenGenEventKind.cancelled,
            )
            .toList(growable: false);
        expect(terminals, hasLength(1));
        expect(terminals.single.kind, ListenGenEventKind.completed);
        expect(events.last.kind, ListenGenEventKind.completed);

        final packageBytes = await File(packagePath).readAsBytes();
        expect(packageBytes, isNotEmpty);
        expect(
          'sha256:${sha256.convert(packageBytes)}',
          events.last.packageSha256,
        );

        // ── Core import assertions (candidate-only) ──
        final receipt = await api.importContentPackage(media.id, packagePath);
        expect(
          RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(receipt.manifestSha256),
          isTrue,
        );
        expect(receipt.track.mediaId, media.id);
        // The pinned Core labels a package-imported track with the resource
        // package schema it came from, not a generic "content-package".
        expect(receipt.track.source, 'listen-resource-package-v1');
        expect(receipt.track.status, 'available');

        expect(
          receipt.track.cues.map((cue) => cue.text),
          containsAllInOrder(const ['Listen, carefully!', 'Words matter.']),
        );

        final byKind = {
          for (final resource in receipt.resources) resource.kind: resource,
        };
        expect(
          byKind.keys,
          containsAll(const ['subtitle_text_track', 'word_timeline']),
        );

        for (final kind in const ['subtitle_text_track', 'word_timeline']) {
          final resource = byKind[kind]!;
          expect(
            resource.localIds,
            isNotEmpty,
            reason: '$kind should be consumed as a candidate',
          );
          // The pinned Core stamps the specific producing component
          // (e.g. listen-gen.asr-package) at the pinned tool version.
          expect(resource.provenance?.tool.id, startsWith('listen-gen'));
          expect(resource.provenance?.tool.version, '0.1.0');
        }

        // Candidate-only: this test never selects a subtitle, activates the
        // word timeline, or mutates any active resource. The receipt is left
        // as the `available` candidate Core returned.

        await run.cleanUp();
        run = null;
        expect(
          await File(packagePath).exists(),
          isFalse,
          reason: 'cleanUp must remove the temporary .listenpkg',
        );
      } finally {
        await run?.cleanUp();
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real three-repository round trip',
  );
}
