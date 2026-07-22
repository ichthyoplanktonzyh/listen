import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/personal_expression.dart';
import 'package:llplayer_next/services/api_service.dart';

const _assetJson = {
  'id': 'pattern-1',
  'language': 'en',
  'source': {
    'kind': 'reading',
    'text': 'I ended up fixing it.',
    'title': 'Real media',
    'media_id': 'media-1',
    'media_fingerprint': 'source-fp',
    'track_id': 'track-1',
    'sentence_id': 'sentence-1',
    'semantic_attempt_id': null,
    'start_ms': 10,
    'end_ms': 20,
    'candidate_ref': null,
  },
  'current_version': {
    'id': 'version-1',
    'pattern_id': 'pattern-1',
    'version': 1,
    'name': 'Ended up',
    'pattern_text': 'I ended up {result}.',
    'slots': [
      {
        'name': 'result',
        'prompt': null,
        'example_value': null,
        'required': true,
      },
    ],
    'note': null,
    'system_construction_id': null,
    'created_at_ms': 1,
  },
  'created_at_ms': 1,
  'updated_at_ms': 1,
};

void main() {
  test(
    'explicit create preserves snapshot and optional construction ref',
    () async {
      String? requestBody;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          expect(method, 'POST');
          expect(path, '/v1/personal-expression/patterns');
          requestBody = body;
          return (statusCode: 201, body: jsonEncode(_assetJson));
        },
      );
      final pattern = await api.createSentencePattern(
        language: 'en',
        source: const PersonalExpressionSourceView(
          kind: 'semantic_candidate',
          text: 'I ended up fixing it.',
          candidateRef: 'embedding-hit-1',
        ),
        name: 'Ended up',
        patternText: 'I ended up {result}.',
        slots: const [SentencePatternSlotView(name: 'result')],
      );
      final encoded = jsonDecode(requestBody!) as Map<String, dynamic>;
      expect(encoded['source']['candidate_ref'], 'embedding-hit-1');
      expect(encoded['system_construction_id'], isNull);
      expect(pattern.source.text, 'I ended up fixing it.');
      expect(pattern.currentVersion.slots.single.name, 'result');
    },
  );

  test(
    'speaking and writing use records keep their channel payloads separate',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          final value = jsonDecode(body!) as Map<String, dynamic>;
          bodies.add(value);
          return (
            statusCode: 201,
            body: jsonEncode({
              'id': 'attempt-${bodies.length}',
              'pattern_id': 'pattern-1',
              ...value,
              'completed_at_ms': bodies.length,
            }),
          );
        },
      );
      await api.recordPersonalExpressionAttempt(
        patternId: 'pattern-1',
        patternVersionId: 'version-1',
        channel: 'writing',
        assistance: 'template_visible',
        responseText: 'I ended up shipping it.',
        selfAssessment: 'expressed',
      );
      await api.recordPersonalExpressionAttempt(
        patternId: 'pattern-1',
        patternVersionId: 'version-1',
        channel: 'speaking',
        assistance: 'no_text',
        responseText: 'I ended up shipping it.',
        rawTranscript: 'raw words',
        recordingAssetId: 'recording-1',
        selfAssessment: 'partly_expressed',
      );
      expect(bodies[0]['recording_asset_id'], isNull);
      expect(bodies[1]['recording_asset_id'], 'recording-1');
      expect(bodies.map((body) => body['channel']), ['writing', 'speaking']);
    },
  );
}
