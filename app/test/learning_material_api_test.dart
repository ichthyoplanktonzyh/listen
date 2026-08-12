import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/api_service.dart';

/// The learning-material API surface (Core contract 4.0): exact routes,
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

  test('parses source assets and typed renditions with nullable fields',
      () async {
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
              sourceAssets: [
                {
                  'id': 'source-1',
                  'media_type': 'text/plain',
                  'byte_length': 11,
                  'sha256_digest': 'a' * 64,
                  'binding': {'type': 'managed', 'reference': null},
                  'availability': {'state': 'available', 'reason': null},
                  'created_at_ms': 1,
                },
              ],
              documentRenditions: [
                {
                  'id': 'document-1',
                  'origin': 'source',
                  'media_type': 'text/plain',
                  'language': null,
                  'text': 'Hello world',
                  'text_sha256': 'a' * 64,
                  'text_byte_size': 11,
                  'source_asset_id': 'source-1',
                },
              ],
              mediaRenditions: [
                {
                  'id': 'media-1',
                  'origin': 'source',
                  'kind': 'audio',
                  'media_type': 'audio/mpeg',
                  'fingerprint': 'fp',
                  'availability': 'archived',
                  'media_id': 'media-1',
                  'media_sha256': null,
                  'media_byte_size': null,
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
    final source = revision.sourceAssets.single;
    expect(source.id, 'source-1');
    expect(source.mediaType, 'text/plain');
    expect(source.binding.type, SourceAssetBindingType.managed);
    expect(source.binding.reference, isNull);
    expect(source.availability.isAvailable, isTrue);
    final document = revision.documentRenditions.single;
    expect(document.text, 'Hello world');
    expect(document.language, isNull);
    expect(document.textSha256, hasLength(64));
    expect(document.textByteSize, 11);
    expect(document.sourceAssetId, 'source-1');
    final media = revision.mediaRenditions.single;
    expect(media.mediaId, 'media-1');
    expect(media.kind, MediaRenditionKind.audio);
    expect(media.availability, MediaRenditionAvailability.archived);
  });

  test('decodes Temporary Material as nullable membership evidence', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        final details = _details(
          retainedAtMs: null,
          shape: 'audio',
          sourceAssets: const [],
          documentRenditions: const [],
          mediaRenditions: [
            {
              'id': 'media-1',
              'origin': 'source',
              'kind': 'video',
              'media_type': 'video/mp4',
              'fingerprint': 'fp',
              'availability': 'missing',
              'media_id': 'media-1',
              'media_sha256': null,
              'media_byte_size': null,
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
    final rendition = details.currentRevision.mediaRenditions.single;
    expect(rendition.kind, MediaRenditionKind.video);
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

  test('create transmits source assets and typed renditions on /v1/materials',
      () async {
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
        sourceAssets: [
          SourceAssetInput(
            mediaType: 'text/plain',
            byteLength: 5,
            sha256Digest: 'b' * 64,
            binding: const SourceAssetBinding(
              type: SourceAssetBindingType.managed,
            ),
          ),
        ],
        documentRenditions: [
          DocumentRenditionInput(
            mediaType: 'text/plain',
            text: 'Hello',
            language: 'en',
            sourceAssetIndex: 0,
          ),
        ],
        mediaRenditions: const [MediaRenditionInput(mediaId: 'media-1')],
      ),
    );

    expect(request!['title'], 'A podcast episode');
    final sourceAssets = request!['source_assets'] as List<dynamic>;
    expect(sourceAssets, hasLength(1));
    expect(sourceAssets[0], {
      'media_type': 'text/plain',
      'byte_length': 5,
      'sha256_digest': 'b' * 64,
      'binding': {'type': 'managed', 'reference': null},
    });
    final documentRenditions =
        request!['document_renditions'] as List<dynamic>;
    expect(documentRenditions, hasLength(1));
    expect(documentRenditions[0], {
      'media_type': 'text/plain',
      'language': 'en',
      'text': 'Hello',
      'source_asset_index': 0,
    });
    expect(request!['media_renditions'], [
      {'media_id': 'media-1'},
    ]);
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

  test('append revision posts typed inputs to the encoded material route',
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
        sourceAssets: [
          SourceAssetInput(
            mediaType: 'text/plain',
            byteLength: 4,
            sha256Digest: 'c' * 64,
            binding: const SourceAssetBinding(
              type: SourceAssetBindingType.managed,
            ),
          ),
        ],
        documentRenditions: [
          DocumentRenditionInput(
            mediaType: 'text/plain',
            text: 'More',
            sourceAssetIndex: 0,
          ),
        ],
        mediaRenditions: const [],
      ),
    );

    expect(seenMethod, 'POST');
    expect(seenPath, '/v1/materials/material%2F1/revisions');
    expect(request!['title'], 'Revised');
    expect(
      (request!['source_assets'] as List<dynamic>).single['sha256_digest'],
      'c' * 64,
    );
    expect(
      (request!['document_renditions'] as List<dynamic>).single['text'],
      'More',
    );
  });

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
            'source_assets': [
              {
                'id': 'source-1',
                'media_type': 'text/plain',
                'byte_length': 11,
                'sha256_digest': 'b' * 64,
                'binding': {'type': 'managed', 'reference': null},
                'availability': {'state': 'available', 'reason': null},
                'created_at_ms': 1,
              },
            ],
            'document_renditions': [
              {
                'id': 'document-1',
                'origin': 'source',
                'media_type': 'text/plain',
                'language': null,
                'text': 'Hello world',
                'text_sha256': 'b' * 64,
                'text_byte_size': 11,
                'source_asset_id': 'source-1',
              },
            ],
            'media_renditions': <Map<String, dynamic>>[],
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

  test('retain and unretain use the material library-membership routes',
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
  });

  test('source asset availability posts typed facts to the encoded route',
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
        return (
          statusCode: 200,
          body: jsonEncode(_details()['current_revision'] as Map),
        );
      },
    );

    final revision = await api.updateSourceAssetAvailability(
      'material/1',
      'source/2',
      const SourceAssetAvailability(
        state: SourceAssetAvailabilityState.unavailable,
        reason: SourceAssetUnavailableReason.fileMissing,
      ),
    );

    expect(seenMethod, 'PUT');
    expect(seenPath, '/v1/materials/material%2F1/source-assets/source%2F2'
        '/availability');
    expect(request, {
      'availability': {'state': 'unavailable', 'reason': 'file_missing'},
    });
    expect(revision.id, 'revision-1');
  });

  test('list capabilities decodes the five-state projection', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'GET');
        expect(path, '/v1/materials/material-1/capabilities');
        return (
          statusCode: 200,
          body: jsonEncode([
            {
              'capability': 'read',
              'status': 'available',
              'latest_attempt': null,
            },
            {
              'capability': 'listen',
              'status': 'failed_attempt',
              'latest_attempt': {
                'attempt_id': 'attempt-1',
                'material_id': 'material-1',
                'capability': 'listen',
                'status': 'failed',
                'started_at_ms': 1,
                'finished_at_ms': 2,
                'failure_reason': 'provider failed',
                'producer_tool_id': null,
                'producer_tool_version': null,
              },
            },
          ]),
        );
      },
    );

    final projections = await api.listMaterialCapabilities('material-1');

    expect(projections, hasLength(2));
    final read = projections[0];
    expect(read.capability, MaterialCapability.read);
    expect(read.status, MaterialCapabilityStatus.available);
    expect(read.latestAttempt, isNull);
    final listen = projections[1];
    expect(listen.capability, MaterialCapability.listen);
    expect(listen.status, MaterialCapabilityStatus.failedAttempt);
    expect(listen.latestAttempt!.attemptId, 'attempt-1');
    expect(listen.latestAttempt!.failureReason, 'provider failed');
  });

  test('decode rejects an unknown binding type honestly', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        final details = _details(
          sourceAssets: [
            {
              'id': 'source-1',
              'media_type': 'text/plain',
              'byte_length': 1,
              'sha256_digest': 'b' * 64,
              'binding': {'type': 'surprise', 'reference': null},
              'availability': {'state': 'available', 'reason': null},
              'created_at_ms': 1,
            },
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
  List<Map<String, dynamic>>? sourceAssets,
  List<Map<String, dynamic>>? documentRenditions,
  List<Map<String, dynamic>>? mediaRenditions,
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
    'source_assets':
        sourceAssets ??
        [
          {
            'id': 'source-1',
            'media_type': 'text/plain',
            'byte_length': 11,
            'sha256_digest': 'a' * 64,
            'binding': {'type': 'managed', 'reference': null},
            'availability': {'state': 'available', 'reason': null},
            'created_at_ms': 1,
          },
        ],
    'document_renditions':
        documentRenditions ??
        [
          {
            'id': 'document-1',
            'origin': 'source',
            'media_type': 'text/plain',
            'language': 'en',
            'text': 'Hello world',
            'text_sha256': 'a' * 64,
            'text_byte_size': 11,
            'source_asset_id': 'source-1',
          },
        ],
    'media_renditions':
        mediaRenditions ??
        [
          {
            'id': 'media-1',
            'origin': 'source',
            'kind': 'audio',
            'media_type': 'audio/mpeg',
            'fingerprint': 'fp',
            'availability': 'available',
            'media_id': 'media-1',
            'media_sha256': null,
            'media_byte_size': null,
          },
        ],
    'created_at_ms': 1,
  },
  'shape': shape,
};

CreateLearningMaterialInput _createInput() => CreateLearningMaterialInput(
  title: 'A podcast episode',
  sourceAssets: [
    SourceAssetInput(
      mediaType: 'text/plain',
      byteLength: 5,
      sha256Digest: 'b' * 64,
      binding: const SourceAssetBinding(
        type: SourceAssetBindingType.managed,
      ),
    ),
  ],
  documentRenditions: [
    DocumentRenditionInput(
      mediaType: 'text/plain',
      text: 'Hello',
      sourceAssetIndex: 0,
    ),
  ],
  mediaRenditions: const [],
);
