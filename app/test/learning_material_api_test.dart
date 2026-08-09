import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/api_service.dart';

/// The learning-material API surface (Core contract 3.2): exact routes,
/// encoded id path segments, honest tri-state retain transmission, and the
/// pure-model boundary (no location, no wire coupling in lib/models).
void main() {
  test('learning material models stay pure and location-free', () {
    final source = File('lib/models/learning_material.dart').readAsStringSync();

    expect(
      source,
      isNot(contains('path')),
      reason: 'no file location may exist in the material domain models',
    );
    expect(
      source,
      isNot(RegExp(r'\b(?:fromJson|toJson)\b')),
      reason: 'JSON decode/encode belongs in services/api/materials.dart only',
    );
  });

  test('parses text and media rendition assets with nullable fields', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'GET');
        expect(path, '/v1/materials/material-1');
        return (
          statusCode: 200,
          body: jsonEncode(
            _details(
              assets: [
                {
                  'asset_type': 'document_text',
                  'id': 'asset-text-1',
                  'text': 'Hello world',
                  'sha256_digest':
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'byte_size': 11,
                  'language': null,
                },
                {
                  'asset_type': 'media_rendition',
                  'id': 'asset-media-1',
                  'media_id': 'media-1',
                  'media_kind': 'audio',
                  'fingerprint': 'fp',
                  'availability': 'archived',
                },
              ],
            ),
          ),
        );
      },
    );

    final details = await api.readLearningMaterial('material-1');

    expect(details.material.id, 'material-1');
    expect(details.material.retainedAtMs, 42);
    expect(details.material.currentRevisionId, 'revision-1');
    expect(details.shape, MaterialShape.mixed);
    final revision = details.currentRevision;
    expect(revision.id, 'revision-1');
    expect(revision.materialId, 'material-1');
    expect(revision.title, 'A podcast episode');
    final textAsset = revision.assets.first;
    expect(textAsset, isA<DocumentTextMaterialAsset>());
    expect((textAsset as DocumentTextMaterialAsset).text, 'Hello world');
    expect(textAsset.language, isNull);
    expect(textAsset.sha256Digest, hasLength(64));
    expect(textAsset.byteSize, 11);
    final mediaAsset = revision.assets.last;
    expect(mediaAsset, isA<MediaRenditionMaterialAsset>());
    expect((mediaAsset as MediaRenditionMaterialAsset).mediaId, 'media-1');
    expect(mediaAsset.mediaKind, MediaRenditionKind.audio);
    expect(mediaAsset.availability, MediaRenditionAvailability.archived);
  });

  test('decodes Temporary Material as nullable membership evidence', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        final details = _details(
          retainedAtMs: null,
          shape: 'audio',
          assets: [
            {
              'asset_type': 'media_rendition',
              'id': 'asset-media-1',
              'media_id': 'media-1',
              'media_kind': 'video',
              'fingerprint': 'fp',
              'availability': 'missing',
            },
          ],
        );
        return (statusCode: 200, body: jsonEncode(details));
      },
    );

    final details = await api.resolveMaterialForMedia('media-1');

    expect(details.material.retainedAtMs, isNull);
    expect(details.material.isRetained, isFalse);
    expect(details.isRetained, isFalse);
    expect(details.shape, MaterialShape.audio);
    final rendition =
        details.currentRevision.assets.single as MediaRenditionMaterialAsset;
    expect(rendition.mediaKind, MediaRenditionKind.video);
    expect(rendition.availability, MediaRenditionAvailability.missing);
  });

  test('list returns retained materials through /v1/materials', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'GET');
        expect(path, '/v1/materials');
        expect(body, isNull);
        return (statusCode: 200, body: jsonEncode([_details()]));
      },
    );

    final materials = await api.listLearningMaterials();

    expect(materials, hasLength(1));
    expect(materials.single.material.id, 'material-1');
  });

  test('read encodes the material id path segment', () async {
    String? seenPath;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        seenPath = path;
        return (statusCode: 200, body: jsonEncode(_details()));
      },
    );

    await api.readLearningMaterial('material/1');

    expect(seenPath, '/v1/materials/material%2F1');
  });

  test('create transmits title and typed assets on /v1/materials', () async {
    Map<String, dynamic>? request;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'POST');
        expect(path, '/v1/materials');
        request = jsonDecode(body!) as Map<String, dynamic>;
        return (statusCode: 200, body: jsonEncode(_details()));
      },
    );

    final details = await api.createLearningMaterial(
      CreateLearningMaterialInput(
        title: 'A podcast episode',
        assets: const [
          DocumentTextMaterialAssetInput(text: 'Hello', language: 'en'),
          MediaRenditionMaterialAssetInput(mediaId: 'media-1'),
        ],
      ),
    );

    expect(request!['title'], 'A podcast episode');
    final assets = request!['assets'] as List<dynamic>;
    expect(assets, hasLength(2));
    expect(assets[0], {
      'asset_type': 'document_text',
      'text': 'Hello',
      'language': 'en',
    });
    expect(assets[1], {'asset_type': 'media_rendition', 'media_id': 'media-1'});
    expect(details.material.id, 'material-1');
  });

  test('create retain: explicit null/false/true are transmitted honestly, '
      'omission stays omission', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        bodies.add(jsonDecode(body!) as Map<String, dynamic>);
        return (statusCode: 200, body: jsonEncode(_details()));
      },
    );

    await api.createLearningMaterial(
      _createInput(),
      retain: const MaterialRetainExplicit(false),
    );
    await api.createLearningMaterial(
      _createInput(),
      retain: const MaterialRetainExplicit(null),
    );
    await api.createLearningMaterial(_createInput());
    await api.createLearningMaterial(
      _createInput(),
      retain: const MaterialRetainExplicit(true),
    );

    expect(bodies[0]['retain'], isFalse);
    expect(bodies[1].containsKey('retain'), isTrue);
    expect(bodies[1]['retain'], isNull);
    expect(bodies[2].containsKey('retain'), isFalse);
    expect(bodies[3]['retain'], isTrue);
  });

  test(
    'append revision posts typed assets to the encoded material route',
    () async {
      String? seenMethod;
      String? seenPath;
      Map<String, dynamic>? request;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          seenMethod = method;
          seenPath = path;
          request = jsonDecode(body!) as Map<String, dynamic>;
          return (statusCode: 200, body: jsonEncode(_details()));
        },
      );

      await api.appendMaterialRevision(
        'material/1',
        AppendMaterialRevisionInput(
          title: 'Revised',
          assets: const [DocumentTextMaterialAssetInput(text: 'More')],
        ),
      );

      expect(seenMethod, 'POST');
      expect(seenPath, '/v1/materials/material%2F1/revisions');
      expect(request!['title'], 'Revised');
      expect((request!['assets'] as List<dynamic>).single['text'], 'More');
    },
  );

  test('read revision encodes both id path segments', () async {
    String? seenPath;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        seenPath = path;
        return (
          statusCode: 200,
          body: jsonEncode({
            'id': 'revision/2',
            'material_id': 'material-1',
            'title': 'A podcast episode',
            'assets': [
              {
                'asset_type': 'document_text',
                'id': 'asset-text-1',
                'text': 'Hello world',
                'sha256_digest':
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'byte_size': 11,
                'language': null,
              },
            ],
            'created_at_ms': 1,
          }),
        );
      },
    );

    final revision = await api.readMaterialRevision('material/1', 'revision/2');

    expect(seenPath, '/v1/materials/material%2F1/revisions/revision%2F2');
    expect(revision.id, 'revision/2');
    expect(revision.title, 'A podcast episode');
  });

  test(
    'retain and unretain use the material library-membership routes',
    () async {
      final seen = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          seen.add('$method $path');
          return (statusCode: 200, body: jsonEncode(_details()));
        },
      );

      final retained = await api.retainLearningMaterial('material/1');
      final unretained = await api.unretainLearningMaterial('material/1');

      expect(seen, [
        'PUT /v1/materials/material%2F1/library-membership',
        'DELETE /v1/materials/material%2F1/library-membership',
      ]);
      expect(retained.material.retainedAtMs, 42);
      expect(unretained.material.retainedAtMs, 42);
    },
  );

  test('resolve binds a media id to its material route', () async {
    String? seenPath;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'GET');
        seenPath = path;
        return (statusCode: 200, body: jsonEncode(_details()));
      },
    );

    final details = await api.resolveMaterialForMedia('media/3');

    expect(seenPath, '/v1/media/media%2F3/material');
    expect(details.material.id, 'material-1');
  });

  test('decode rejects an unknown asset_type honestly', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        final details = _details(
          assets: [
            {'asset_type': 'surprise', 'id': 'asset-1'},
          ],
        );
        return (statusCode: 200, body: jsonEncode(details));
      },
    );

    await expectLater(
      api.readLearningMaterial('material-1'),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, dynamic> _details({
  int? retainedAtMs = 42,
  String shape = 'mixed',
  List<Map<String, dynamic>>? assets,
}) => {
  'material': {
    'id': 'material-1',
    'current_revision_id': 'revision-1',
    'retained_at_ms': retainedAtMs,
    'created_at_ms': 1,
    'updated_at_ms': 2,
  },
  'current_revision': {
    'id': 'revision-1',
    'material_id': 'material-1',
    'title': 'A podcast episode',
    'assets':
        assets ??
        [
          {
            'asset_type': 'document_text',
            'id': 'asset-text-1',
            'text': 'Hello world',
            'sha256_digest':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'byte_size': 11,
            'language': 'en',
          },
        ],
    'created_at_ms': 1,
  },
  'shape': shape,
};

CreateLearningMaterialInput _createInput() => CreateLearningMaterialInput(
  title: 'A podcast episode',
  assets: const [DocumentTextMaterialAssetInput(text: 'Hello')],
);
