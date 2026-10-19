import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/services/composition_resolution.dart';

/// The adopted composition's learner content resolves from its exact payload
/// bytes through Core's composition facts: sentence structure from the
/// structured reading's anchors, alignment from the alignment payload, and
/// derived audio from the composition's derived media rendition.
void main() {
  test('resolves sentences, anchors, alignment, and derived audio', () {
    final composition = _composition(
      structuredReading: _structuredReadingPayload(),
      alignment: _alignmentPayload(),
      derivedMedia: true,
    );

    final resolved = resolveCompositionContent(
      composition: composition,
      structuredReadingPayload: utf8.encode(
        jsonEncode(_structuredReadingPayload()),
      ),
      alignmentPayload: utf8.encode(jsonEncode(_alignmentPayload())),
      derivedMediaPath: '/tmp/listen-composition-media/audio.wav',
    );

    expect(resolved, isNotNull);
    expect(resolved!.logicalText, 'Hello world. Listen carefully!');
    expect(
      resolved.sentences.map((sentence) => sentence.text),
      ['Hello world.', 'Listen carefully!'],
    );
    expect(
      resolved.anchors.map((anchor) => anchor.kind),
      ['block', 'sentence', 'sentence'],
    );
    expect(resolved.alignments['anchor-1'], 150);
    expect(resolved.derivedMediaPath, '/tmp/listen-composition-media/audio.wav');
  });

  test('sentence slicing is byte-based for CJK text', () {
    final payload = {
      'language': 'zh',
      'text': '你好世界。认真听！',
      'anchors': [
        {
          'anchor_id': 's1',
          'kind': 'sentence',
          'start_offset': 0,
          'end_offset': 15,
        },
        {
          'anchor_id': 's2',
          'kind': 'sentence',
          'start_offset': 15,
          'end_offset': 33,
        },
      ],
      'blocks': const <List<dynamic>>[],
      'spans': const <List<dynamic>>[],
      'document_mappings': const <List<dynamic>>[],
      'extensions': const <String, dynamic>{},
    };

    final resolved = resolveCompositionContent(
      composition: _composition(structuredReading: payload),
      structuredReadingPayload: utf8.encode(jsonEncode(payload)),
    );

    expect(resolved, isNotNull);
    expect(
      resolved!.sentences.map((sentence) => sentence.text),
      ['你好世界。', '认真听！'],
    );
  });

  test('a missing structured reading resolves to nothing', () {
    final resolved = resolveCompositionContent(
      composition: _composition(structuredReading: null),
      structuredReadingPayload: const [],
    );

    expect(resolved, isNull);
  });

  test('a malformed payload resolves to nothing, never a guess', () {
    final resolved = resolveCompositionContent(
      composition: _composition(structuredReading: <String, dynamic>{}),
      structuredReadingPayload: utf8.encode(jsonEncode(<String, dynamic>{})),
    );

    expect(resolved, isNull);
  });

  test('an absent alignment payload yields no alignments', () {
    final resolved = resolveCompositionContent(
      composition: _composition(structuredReading: _structuredReadingPayload()),
      structuredReadingPayload: utf8.encode(
        jsonEncode(_structuredReadingPayload()),
      ),
    );

    expect(resolved, isNotNull);
    expect(resolved!.alignments, isEmpty);
  });
}

AdoptedComposition _composition({
  required Map<String, dynamic>? structuredReading,
  Map<String, dynamic>? alignment,
  bool derivedMedia = false,
}) {
  final resources = <AdoptedCompositionResource>[
    if (structuredReading != null)
      _resource('sr-1', 'structured_reading'),
    if (alignment != null) _resource('align-1', 'anchor_time_alignment'),
  ];
  return AdoptedComposition(
    materialId: 'material-1',
    materialRevisionId: 'revision-1',
    releaseId: 'release-1',
    editionId: 'edition:material-1',
    title: 'Lesson',
    targetLanguage: 'en',
    supportLanguages: const [],
    adoptedAtMs: 10,
    resources: resources,
    renditions: [
      if (derivedMedia)
        const AdoptedCompositionRendition(
          renditionId: 'media-derived-1',
          kind: 'media',
          origin: 'derived',
          mediaType: 'audio/wav',
          language: 'en',
          digest: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          byteSize: 4,
          blobAvailable: true,
          binding: null,
          producerToolId: 'listen-gen',
        ),
    ],
  );
}

AdoptedCompositionResource _resource(String resourceId, String kind) =>
    AdoptedCompositionResource(
      resourceId: resourceId,
      kind: kind,
      schema: 'https://listen.dev/contracts/content-package/v3/payload/'
          'structured-reading.v1.schema.json',
      role: 'base',
      required: true,
      availability: 'available',
      contentLanguage: 'en',
      supportLanguages: const [],
      payloadDigest: 'a' * 64,
      payloadSizeBytes: 1,
      reviewStatus: 'machine_checked',
    );

Map<String, dynamic> _structuredReadingPayload() => {
  'language': 'en',
  'text': 'Hello world. Listen carefully!',
  'anchors': [
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
    {
      'anchor_id': 'anchor-3',
      'kind': 'sentence',
      'start_offset': 13,
      'end_offset': 30,
    },
  ],
  'blocks': const <List<dynamic>>[],
  'spans': const <List<dynamic>>[],
  'document_mappings': const <List<dynamic>>[],
  'extensions': const <String, dynamic>{},
};

Map<String, dynamic> _alignmentPayload() => {
  'anchor_resource_id': 'sha256:${'a' * 64}',
  'rendition_id': 'sha256:${'b' * 64}',
  'alignments': const <Map<String, dynamic>>[
    {'anchor_id': 'anchor-1', 'media_time_ms': 150},
  ],
  'extensions': const <String, dynamic>{},
};
