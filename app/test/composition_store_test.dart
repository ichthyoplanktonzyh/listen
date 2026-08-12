import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/composition_store.dart';

/// CompositionStore parses the retained Content Package v3 carrier into the
/// learner content of an adopted composition: document text and its sentence
/// segments, the structured reading anchors, anchor-to-time alignment, and
/// the extracted derived audio.
void main() {
  late Directory root;
  late CompositionStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('composition-store-');
    store = CompositionStore(root: root.path);
  });

  tearDown(() => root.delete(recursive: true));

  Future<ResolvedComposition> resolveV3({
    required bool includeDerivedMedia,
    String text = 'Hello world. Listen carefully!',
    List<Map<String, dynamic>>? segments,
  }) async {
    final carrier = File('${root.path}/carrier.zip')
      ..writeAsBytesSync(
        _packageBytes(
          _v3Content(
            includeDerivedMedia: includeDerivedMedia,
            text: text,
            segments: segments,
          ),
        ),
      );
    await store.save(
      materialId: 'material-1',
      releaseId: 'release-1',
      packagePath: carrier.path,
    );
    final composition = await store.resolve(
      materialId: 'material-1',
      releaseId: 'release-1',
    );
    expect(composition, isNotNull);
    return composition!;
  }

  test('save retains the carrier and resolve parses its content', () async {
    final composition = await resolveV3(includeDerivedMedia: true);

    expect(composition.documentText, 'Hello world. Listen carefully!');
    expect(
      composition.sentences.map((sentence) => sentence.text),
      ['Hello world.', 'Listen carefully!'],
    );
    expect(
      composition.anchors.map((anchor) => anchor.kind),
      ['block', 'sentence'],
    );
    expect(composition.alignments['anchor-1'], 150);
    expect(composition.derivedMediaPath, isNotNull);
    expect(
      await File(composition.derivedMediaPath!).readAsBytes(),
      [1, 2, 3, 4],
    );
  });

  test('an absent carrier resolves to null', () async {
    expect(
      await store.resolve(materialId: 'material-1', releaseId: 'release-1'),
      isNull,
    );
  });

  test('a carrier without release.json is rejected', () async {
    final broken = File('${root.path}/broken.zip')
      ..writeAsBytesSync(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('stray.txt', 3, 'abc'.codeUnits)),
        ),
      );
    await store.save(
      materialId: 'm',
      releaseId: 'r',
      packagePath: broken.path,
    );

    expect(
      () => store.resolve(materialId: 'm', releaseId: 'r'),
      throwsFormatException,
    );
  });

  test('a carrier without derived media exposes no audio path', () async {
    final composition = await resolveV3(includeDerivedMedia: false);
    expect(composition.derivedMediaPath, isNull);
  });

  test('sentence slicing is character-based for CJK text', () async {
    final composition = await resolveV3(
      includeDerivedMedia: false,
      text: '你好世界。认真听！',
      segments: const [
        {'id': 's1', 'index': 0, 'start_char': 0, 'end_char': 4},
        {'id': 's2', 'index': 1, 'start_char': 4, 'end_char': 8},
      ],
    );
    expect(
      composition.sentences.map((sentence) => sentence.text),
      ['你好世界', '。认真听'],
    );
  });
}

String _blobName(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

/// A minimal Content Package v3 carrier exercising every payload the store
/// parses.
List<int> _v3Content({
  required bool includeDerivedMedia,
  String text = 'Hello world. Listen carefully!',
  List<Map<String, dynamic>>? segments,
}) {
  final documentText = jsonEncode({
    'text': text,
    'segments': segments ??
        const [
          {'id': 's1', 'index': 0, 'start_char': 0, 'end_char': 12},
          {'id': 's2', 'index': 1, 'start_char': 13, 'end_char': 30},
        ],
  });
  final structuredReading = jsonEncode({
    'anchors': const [
      {
        'anchor_id': 'anchor-1',
        'kind': 'block',
        'start_offset': 0,
        'end_offset': 30,
      },
      {
        'anchor_id': 'anchor-2',
        'kind': 'sentence',
        'start_offset': 0,
        'end_offset': 12,
      },
    ],
  });
  final alignment = jsonEncode({
    'alignments': const [
      {'anchor_id': 'anchor-1', 'media_time_ms': 150},
    ],
  });
  final mediaBytes = [1, 2, 3, 4];

  final blobs = <String, List<int>>{
    _blobName(utf8.encode(documentText)): utf8.encode(documentText),
    _blobName(utf8.encode(structuredReading)): utf8.encode(structuredReading),
    _blobName(utf8.encode(alignment)): utf8.encode(alignment),
    _blobName(mediaBytes): mediaBytes,
  };
  final resources = [
    {
      'descriptor': {
        'kind': 'document_text',
        'payload_blob': {'digest': _blobName(utf8.encode(documentText))},
      },
    },
    {
      'descriptor': {
        'kind': 'structured_reading',
        'payload_blob': {'digest': _blobName(utf8.encode(structuredReading))},
      },
    },
    {
      'descriptor': {
        'kind': 'anchor_time_alignment',
        'payload_blob': {'digest': _blobName(utf8.encode(alignment))},
      },
    },
  ];
  final mediaRenditions = <Map<String, dynamic>>[];
  if (includeDerivedMedia) {
    mediaRenditions.add({
      'origin': 'derived',
      'rendition_id': 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'media_type': 'audio/wav',
      'media_blob': {'digest': _blobName(mediaBytes)},
    });
  }

  final release = {
    'release_schema_id': 'listen.content-package.release.v3',
    'version': 3,
    'material': {'material_id': 'material-1', 'material_revision_id': 'r1'},
    'edition': {'edition_id': 'edition:material-1'},
    'document_renditions': <Object>[],
    'media_renditions': mediaRenditions,
    'resources': resources,
  };

  final archive = Archive();
  archive.addFile(
    ArchiveFile('release.json', utf8.encode(jsonEncode(release)).length, utf8.encode(jsonEncode(release))),
  );
  for (final entry in blobs.entries) {
    final hex = entry.key.substring('sha256:'.length);
    final bytes = entry.value;
    archive.addFile(
      ArchiveFile('blobs/sha256/$hex', bytes.length, bytes),
    );
  }
  return ZipEncoder().encode(archive);
}

List<int> _packageBytes(List<int> zipBytes) => zipBytes;
