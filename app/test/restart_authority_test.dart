import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/services/composition_store.dart';

/// Restart authority (Slice 6 acceptance).
///
/// After a relaunch the adopted composition comes back from the retained
/// carrier — reading, listening and learning go through it and no other
/// projection — and the learner's own activity state lives in a store that
/// the composition never touches. Neither is rebuilt from the other.
void main() {
  late Directory compositionRoot;

  setUp(() {
    compositionRoot = Directory.systemTemp.createTempSync('restart-comp-');
  });

  tearDown(() => compositionRoot.deleteSync(recursive: true));

  List<int> carrierBytes({required String text}) {
    const hex = 'deadbeef';
    final blobName = 'sha256:$hex';
    final documentText = jsonEncode({
      'text': text,
      'segments': const [
        {'id': 's1', 'index': 0, 'start_char': 0, 'end_char': 12},
      ],
    });
    final release = {
      'release_schema_id': 'listen.content-package.release.v3',
      'version': 3,
      'material': {'material_id': 'material-1', 'material_revision_id': 'r1'},
      'edition': {'edition_id': 'edition:material-1'},
      'document_renditions': <Object>[],
      'media_renditions': <Object>[],
      'resources': [
        {
          'descriptor': {
            'kind': 'document_text',
            'payload_blob': {'digest': blobName},
          },
        },
      ],
    };

    final archive = Archive();
    archive.addFile(
      ArchiveFile(
        'release.json',
        utf8.encode(jsonEncode(release)).length,
        utf8.encode(jsonEncode(release)),
      ),
    );
    archive.addFile(
      ArchiveFile(
        'blobs/sha256/$hex',
        utf8.encode(documentText).length,
        utf8.encode(documentText),
      ),
    );
    return ZipEncoder().encode(archive);
  }

  test(
    'after a relaunch the adopted composition recovers from the retained '
    'carrier, and never from app-side state',
    () async {
      // ── first session: keep the material and remember a place in it ──
      final carrier = File('${compositionRoot.path}/carrier.zip')
        ..writeAsBytesSync(carrierBytes(text: 'Hello world. Listen carefully!'));
      await CompositionStore(root: compositionRoot.path).save(
        materialId: 'material-1',
        releaseId: 'release-1',
        packagePath: carrier.path,
      );

      // ── relaunch: a fresh store instance over the same disk ──
      final composition = await CompositionStore(
        root: compositionRoot.path,
      ).resolve(materialId: 'material-1', releaseId: 'release-1');

      // The adopted composition is authoritative: the learner content comes
      // back from the retained carrier, with nothing rebuilt by the app.
      expect(composition, isNotNull);
      expect(composition!.documentText, 'Hello world. Listen carefully!');
      expect(
        compositionRoot
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('carrier.zip')),
        hasLength(1),
      );
    },
  );

  test(
    'learner activity state is owned outside the composition store',
    () async {
      final activity = SettingsController();
      addTearDown(activity.dispose);

      activity.recordRecentMedia(
        path: '/library/p0p1qc9j.mp3',
        title: 'Episode one',
        positionMs: 12400,
        durationMs: 180000,
        subtitleCount: 1,
      );
      expect(activity.lastMediaPath, '/library/p0p1qc9j.mp3');
      expect(activity.lastMediaPositionMs, 12400);

      // Keeping a composition neither reads nor writes the learner's place
      // in the material: the stores are separate and stay separate.
      final carrier = File('${compositionRoot.path}/carrier.zip')
        ..writeAsBytesSync(carrierBytes(text: 'Another lesson.'));
      await CompositionStore(root: compositionRoot.path).save(
        materialId: 'material-2',
        releaseId: 'release-1',
        packagePath: carrier.path,
      );

      expect(activity.lastMediaPath, '/library/p0p1qc9j.mp3');
      expect(activity.lastMediaPositionMs, 12400);
      expect(activity.settings.version, 8);
    },
  );

  test(
    'reopening without the carrier falls back to nothing, not to a stale '
    'projection',
    () async {
      final composition = await CompositionStore(
        root: compositionRoot.path,
      ).resolve(materialId: 'never-kept', releaseId: 'release-1');

      expect(composition, isNull);
    },
  );
}
