import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Core 5.1 material API behavior: exact routes, typed rendition payloads,
/// honest retain transmission, and the pure-model boundary.
void main() {
  test('learning material models stay pure and location-free', () {
    final source = File('lib/models/learning_material.dart').readAsStringSync();

    expect(
      source,
      isNot(
        RegExp(
          r'^\s*(?:final|late\s+final)\s+(?:String|Uri)\s+\w*(?:path|file|uri)\s*;',
          multiLine: true,
          caseSensitive: false,
        ),
      ),
      reason: 'material DTOs must not expose filesystem locations',
    );
    expect(source, isNot(RegExp(r'\b(?:fromJson|toJson)\b')));
  });

  test(
    'decodes media renditions with empty document component lists',
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
      expect(details.shape, MaterialShape.audio);
      final revision = details.currentRevision;
      expect(revision.title, 'A podcast episode');
      expect(revision.mediaRenditions, hasLength(1));
      final media = revision.mediaRenditions.single;
      expect(media.mediaId, 'media-1');
      expect(media.kind, MediaRenditionKind.audio);
      expect(media.availability, MediaRenditionAvailability.archived);
    },
  );

  test('resolves temporary media as nullable library membership', () async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(path, '/v1/media/media-1/material');
        return (
          statusCode: 200,
          body: jsonEncode(
            _details(
              retainedAtMs: null,
              shape: 'video',
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
            ),
          ),
        );
      },
    );

    final details = await api.resolveMaterialForMedia('media-1');

    expect(details.material.isRetained, isFalse);
    expect(details.shape, MaterialShape.video);
    expect(
      details.currentRevision.mediaRenditions.single.availability,
      MediaRenditionAvailability.missing,
    );
  });

  test(
    'list and read use the materials routes and encode path segments',
    () async {
      final seen = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          seen.add('$method $path');
          return (
            statusCode: 200,
            body: jsonEncode(
              method == 'GET' && path == '/v1/materials'
                  ? [_details()]
                  : _details(),
            ),
          );
        },
      );

      expect(await api.listLearningMaterials(), hasLength(1));
      await api.readLearningMaterial('material/1');

      expect(seen, ['GET /v1/materials', 'GET /v1/materials/material%2F1']);
    },
  );

  test(
    'create sends media renditions and empty document component lists',
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
          mediaRenditions: const [MediaRenditionInput(mediaId: 'media-1')],
        ),
      );

      expect(request!['title'], 'A podcast episode');
      expect(request!['source_assets'], isEmpty);
      expect(request!['document_renditions'], isEmpty);
      expect(request!['media_renditions'], [
        {'media_id': 'media-1'},
      ]);
      expect(details.material.id, 'material-1');
    },
  );

  test(
    'create retain preserves explicit null, false, true, and omission',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          bodies.add(jsonDecode(body!) as Map<String, dynamic>);
          return (statusCode: 200, body: jsonEncode(_details()));
        },
      );
      final input = CreateLearningMaterialInput(
        title: 'Episode',
        mediaRenditions: const [MediaRenditionInput(mediaId: 'media-1')],
      );

      await api.createLearningMaterial(
        input,
        retain: const MaterialRetainExplicit(false),
      );
      await api.createLearningMaterial(
        input,
        retain: const MaterialRetainExplicit(null),
      );
      await api.createLearningMaterial(input);
      await api.createLearningMaterial(
        input,
        retain: const MaterialRetainExplicit(true),
      );

      expect(bodies[0]['retain'], isFalse);
      expect(bodies[1].containsKey('retain'), isTrue);
      expect(bodies[1]['retain'], isNull);
      expect(bodies[2].containsKey('retain'), isFalse);
      expect(bodies[3]['retain'], isTrue);
    },
  );

  test('append revision posts media inputs and empty document lists', () async {
    String? seenPath;
    Map<String, dynamic>? request;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'POST');
        seenPath = path;
        request = jsonDecode(body!) as Map<String, dynamic>;
        return (statusCode: 200, body: jsonEncode(_details()));
      },
    );

    await api.appendMaterialRevision(
      'material/1',
      AppendMaterialRevisionInput(
        title: 'Revised',
        mediaRenditions: const [MediaRenditionInput(mediaId: 'media-2')],
      ),
    );

    expect(seenPath, '/v1/materials/material%2F1/revisions');
    expect(request!['title'], 'Revised');
    expect(request!['source_assets'], isEmpty);
    expect(request!['document_renditions'], isEmpty);
    expect(request!['media_renditions'], [
      {'media_id': 'media-2'},
    ]);
  });

  test(
    'revision reads encode both material and revision path segments',
    () async {
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
              'source_assets': <Map<String, dynamic>>[],
              'document_renditions': <Map<String, dynamic>>[],
              'media_renditions': <Map<String, dynamic>>[],
              'created_at_ms': 1,
            }),
          );
        },
      );

      final revision = await api.readMaterialRevision(
        'material/1',
        'revision/2',
      );

      expect(seenPath, '/v1/materials/material%2F1/revisions/revision%2F2');
      expect(revision.id, 'revision/2');
      expect(revision.mediaRenditions, isEmpty);
    },
  );

  test('retain and unretain use the library-membership routes', () async {
    final seen = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        seen.add('$method $path');
        return (
          statusCode: 200,
          body: jsonEncode(_details(retainedAtMs: method == 'PUT' ? 42 : null)),
        );
      },
    );

    final retained = await api.retainLearningMaterial('material/1');
    final unretained = await api.unretainLearningMaterial('material/1');

    expect(seen, [
      'PUT /v1/materials/material%2F1/library-membership',
      'DELETE /v1/materials/material%2F1/library-membership',
    ]);
    expect(retained.material.retainedAtMs, 42);
    expect(unretained.material.retainedAtMs, isNull);
  });

  test(
    'capability projection keeps media transcription and listening facts',
    () async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
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
      expect(projections.first.capability, MaterialCapability.read);
      expect(projections.first.status, MaterialCapabilityStatus.available);
      final listen = projections.last;
      expect(listen.capability, MaterialCapability.listen);
      expect(listen.latestAttempt!.attemptId, 'attempt-1');
      expect(listen.latestAttempt!.failureReason, 'provider failed');
    },
  );
}

Map<String, dynamic> _details({
  int? retainedAtMs = 42,
  String shape = 'audio',
  List<Map<String, dynamic>> mediaRenditions = const [],
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
    'source_assets': <Map<String, dynamic>>[],
    'document_renditions': <Map<String, dynamic>>[],
    'media_renditions': mediaRenditions,
    'created_at_ms': 1,
  },
  'shape': shape,
};
