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
      expect(verified.toolVersion, '0.4.0');
      expect(
        verified.artifactSha256,
        'sha256:47cef5bb9c1711432db1bcd285c1f0e4f637842d1ef199e13abeef83ca46cf63',
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
          containsAll(const [
            'subtitle_text_track',
            'word_timeline',
            'phone_timeline',
            'sense_group_analysis',
            'word_acoustics',
            'prosody_analysis',
          ]),
        );
        expect(byKind, hasLength(6));
        for (final resource in byKind.values) {
          expect(resource.outcome, 'consumed');
        }
        for (final kind in const [
          'subtitle_text_track',
          'word_timeline',
          'phone_timeline',
          'sense_group_analysis',
          'prosody_analysis',
        ]) {
          expect(
            byKind[kind]!.localIds,
            isNotEmpty,
            reason: '$kind should be consumed as a candidate',
          );
        }
        expect(
          byKind['word_acoustics']!.localIds,
          isEmpty,
          reason: 'word acoustics is consumed into the LLTimeline artifact',
        );

        // The pinned Core stamps the specific producing component at the
        // pinned tool version. The word timeline must come from the
        // alignment stage (`listen-gen.alignment`), not from the ASR-supplied
        // timing — the aligned package is what this round trip proves.
        final subtitle = byKind['subtitle_text_track']!;
        expect(
          subtitle.localIds,
          isNotEmpty,
          reason: 'subtitle_text_track should be consumed as a candidate',
        );
        expect(subtitle.provenance?.tool.id, 'listen-gen.asr-package');
        expect(subtitle.provenance?.tool.version, '0.4.0');

        final wordTimeline = byKind['word_timeline']!;
        expect(
          wordTimeline.localIds,
          isNotEmpty,
          reason: 'word_timeline should be consumed as a candidate',
        );
        expect(
          wordTimeline.provenance?.tool.id,
          'listen-gen.alignment',
          reason:
              'word_timeline must be produced by the alignment stage, not '
              'the ASR-supplied word timing',
        );
        expect(wordTimeline.provenance?.tool.version, '0.4.0');

        expect(
          byKind['phone_timeline']!.provenance?.tool.id,
          'listen-gen.phone',
        );
        expect(
          byKind['sense_group_analysis']!.provenance?.tool.id,
          'listen-gen.sense-groups',
        );
        expect(
          byKind['word_acoustics']!.provenance?.tool.id,
          'listen-gen.acoustics',
        );
        expect(
          byKind['prosody_analysis']!.provenance?.tool.id,
          'listen-gen.prosody',
        );
        for (final kind in const [
          'phone_timeline',
          'sense_group_analysis',
          'word_acoustics',
          'prosody_analysis',
        ]) {
          expect(byKind[kind]!.provenance?.tool.version, '0.4.0');
        }

        final exportedTimeline = await api.exportTrackLLTimeline(
          receipt.track.id,
        );
        expect(exportedTimeline.activeWordTimelineId, isNull);
        expect(exportedTimeline.activePhoneTimelineId, isNull);
        // The imported prosody analysis is exported as a candidate: it is the
        // sole prosodic-chunk source but stays unactivated.
        expect(exportedTimeline.prosodyAnalyses, isNotEmpty);
        expect(exportedTimeline.activeProsodyAnalysisId, isNull);

        // Candidate-only: this test never selects a subtitle or activates any
        // imported analysis. Rich prosody stays a candidate and the retired
        // legacy ChunkTimeline family is absent entirely.

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
