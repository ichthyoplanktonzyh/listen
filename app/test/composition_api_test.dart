import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('adopted compositions decode media renditions and media bindings', () {
    final composition = decodeAdoptedComposition({
      'material_id': 'material-1',
      'material_revision_id': 'revision-1',
      'release_id': 'release-1',
      'edition_id': 'edition:material-1',
      'title': 'Lesson',
      'target_language': 'en',
      'support_languages': <String>[],
      'adopted_at_ms': 1,
      'resources': <Object>[],
      'renditions': [
        {
          'rendition_id': 'rendition-1',
          'kind': 'media',
          'origin': 'source',
          'media_type': 'audio/mpeg',
          'language': null,
          'digest': 'a' * 64,
          'byte_size': 120,
          'blob_available': false,
          'binding': {'type': 'media', 'media_id': 'media-1'},
          'producer_tool_id': null,
        },
      ],
    });

    final rendition = composition.renditions.single;
    expect(rendition.kind, 'media');
    expect(rendition.binding, isA<AdoptedCompositionMediaBinding>());
    expect(rendition.binding!.mediaId, 'media-1');
  });

  test('non-media rendition kinds and bindings are rejected', () {
    expect(
      () => decodeAdoptedCompositionRendition({'kind': 'document'}),
      throwsFormatException,
    );
    expect(
      () => decodeAdoptedCompositionBinding({
        'type': 'source_asset',
        'source_asset_id': 'source-1',
      }),
      throwsFormatException,
    );
  });

  test(
    'composition resource payload bytes remain available via Core',
    () async {
      String? seenPath;
      final expectedBytes = [
        123,
        34,
        116,
        101,
        120,
        116,
        34,
        58,
        34,
        120,
        34,
        125,
      ];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async => throw StateError(
          'composition resource payload must use byte transport',
        ),
        blobTransport: (method, path, body) async {
          expect(method, 'GET');
          expect(body, isNull);
          seenPath = path;
          return (statusCode: 200, bytes: expectedBytes);
        },
      );

      final payload = await api.readCompositionResourcePayload(
        'material/1',
        'resource/1',
      );

      expect(
        seenPath,
        '/v1/materials/material%2F1/composition/resources/resource%2F1/payload',
      );
      expect(payload, expectedBytes);
    },
  );
}
