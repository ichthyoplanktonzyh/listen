import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/capability_request_encoder.dart';

/// Capability generation declares exact locally available source renditions.
void main() {
  test('encodes media rendition identity and verified byte facts', () {
    final rendition = MediaRendition(
      id: 'a' * 64,
      origin: RenditionOrigin.source,
      kind: MediaRenditionKind.audio,
      mediaType: 'audio/mpeg',
      fingerprint: 'fp-1',
      availability: MediaRenditionAvailability.available,
      mediaId: 'media-1',
      mediaSha256: null,
      mediaByteSize: null,
    );
    final request = CapabilityRequestEncoder.encode(
      materialId: 'material-1',
      materialRevisionId: 'revision-1',
      materialTitle: 'Lesson',
      editionId: 'edition:material-1',
      editionTitle: 'Lesson',
      targetLanguage: 'en',
      supportLanguages: const [],
      requestedCapability: 'read',
      createdAtMs: 1,
      attemptId: 'attempt-1',
      mediaRenditions: [rendition],
      mediaFilePath: (_) => '/media/episode.mp3',
      mediaBlobFacts: {
        rendition.id: MediaBlobFacts(sha256Hex: 'b' * 64, sizeBytes: 28),
      },
    );

    final entry =
        (request['available_renditions'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(request['requested_capability'], 'read');
    expect(entry['kind'], 'media');
    expect(entry['rendition_id'], 'sha256:${'a' * 64}');
    expect(entry['media_kind'], 'audio');
    expect(entry['media_id'], 'media-1');
    expect(entry['fingerprint'], 'fp-1');
    expect(entry['media_type'], 'audio/mpeg');
    expect(entry['blob'], {
      'digest': 'sha256:${'b' * 64}',
      'size_bytes': 28,
      'path': '/media/episode.mp3',
    });
    expect(request.containsKey('available_resources'), isFalse);
  });

  test('an empty media input declares no renditions', () {
    final request = CapabilityRequestEncoder.encode(
      materialId: 'material-1',
      materialRevisionId: 'revision-1',
      materialTitle: 'Lesson',
      editionId: 'edition:material-1',
      editionTitle: 'Lesson',
      targetLanguage: 'en',
      supportLanguages: const [],
      requestedCapability: 'read',
      createdAtMs: 1,
      attemptId: 'attempt-1',
    );

    expect(request['available_renditions'], isEmpty);
  });

  test('encodes a document using Core raw source-asset identity', () {
    final rendition = DocumentRendition(
      id: 'a' * 64,
      origin: RenditionOrigin.source,
      mediaType: 'text/plain',
      language: 'en',
      digest: 'b' * 64,
      byteSize: 18,
      sourceAssetId: 'c' * 64,
    );
    final request = CapabilityRequestEncoder.encode(
      materialId: 'material-document',
      materialRevisionId: 'revision-document',
      materialTitle: 'Article',
      editionId: 'edition:material-document',
      editionTitle: 'Article',
      targetLanguage: 'en',
      supportLanguages: const [],
      requestedCapability: 'listen',
      createdAtMs: 1,
      documentRenditions: [rendition],
      documentFilePath: (_) => '/managed/c',
    );

    final entry =
        (request['available_renditions'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(entry['kind'], 'document');
    expect(entry['rendition_id'], 'sha256:${'a' * 64}');
    expect(entry['source_asset_id'], 'c' * 64);
    expect(entry['media_type'], 'text/plain');
    expect(entry['language'], 'en');
    expect(entry['blob'], {
      'digest': 'sha256:${'b' * 64}',
      'size_bytes': 18,
      'path': '/managed/c',
    });
  });
}
