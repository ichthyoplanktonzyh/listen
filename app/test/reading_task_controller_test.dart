import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';

const _source = ReadingTaskSource(
  anchorCueId: 'cue-1',
  mediaId: 'media-1',
  trackId: 'track-1',
  startMs: 1000,
  endMs: 9000,
  sourceLanguage: 'en',
  responseLanguage: 'zh',
  transcriptSnapshot: 'A quake struck Mindanao on Monday morning.',
);

const _template = [
  RubricPointView(
    pointId: 'main-idea',
    importance: 'required',
    statement: '主旨',
  ),
  RubricPointView(pointId: 'detail', importance: 'optional', statement: '细节'),
];

Map<String, dynamic> _rubricJson({int version = 1}) => {
  'id': 'rubric-x',
  'purpose': 'reading_comprehension',
  'source': {
    'media_id': 'media-1',
    'track_id': 'track-1',
    'start_ms': 1000,
    'end_ms': 9000,
    'language': 'en',
    'transcript_snapshot': _source.transcriptSnapshot,
  },
  'response_language': 'zh',
  'points': [
    {
      'point_id': 'main-idea',
      'importance': 'required',
      'statement': '主旨',
      'accepted_paraphrase_notes': null,
    },
    {
      'point_id': 'detail',
      'importance': 'optional',
      'statement': '细节',
      'accepted_paraphrase_notes': null,
    },
  ],
  'version': version,
  'provenance': {'kind': 'manual'},
  'revision': null,
  'created_at_ms': 5,
};

Map<String, dynamic> _attemptJson(String transcript) => {
  'id': 'attempt-x',
  'kind': 'reading_comprehension',
  'rubric_id': 'rubric-x',
  'rubric_version': 1,
  'conditions': {
    'source_text_visible': true,
    'audio_play_count': 2,
    'notes_allowed': false,
  },
  'responses': [
    {
      'revision': 1,
      'transcript': transcript,
      'source': 'typed',
      'language': 'zh',
      'recorded_at_ms': 10,
    },
  ],
  'status': 'completed',
  'started_at_ms': 5,
  'ended_at_ms': 10,
};

/// Records every request and replays canned responses per (method, path
/// prefix). Bodies are captured for payload assertions.
class _FakeBackend {
  final requests = <(String, String, Map<String, dynamic>?)>[];
  final responses = <(String, String, Object?)>[];

  void on(String method, String pathPrefix, Object? response) {
    responses.add((method, pathPrefix, response));
  }

  LocalApi get api => LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      requests.add((
        method,
        path,
        body == null ? null : jsonDecode(body) as Map<String, dynamic>,
      ));
      for (final (m, prefix, response) in responses) {
        if (m == method && path.startsWith(prefix)) {
          if (response is int) return (statusCode: response, body: '');
          return (statusCode: 200, body: jsonEncode(response));
        }
      }
      return (statusCode: 404, body: '{"code":"not_found"}');
    },
  );
}

void main() {
  test('openTask with no existing rubric enters template editing', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', null);
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
    );
    expect(controller.state.phase, 'editing');
    expect(controller.state.draftPoints, hasLength(2));
    // Lookup carried the source identity, not a client-derived id.
    final (_, path, _) = backend.requests.single;
    expect(path, contains('purpose=reading_comprehension'));
    expect(path, contains('start_ms=1000'));
    expect(path, isNot(contains('rubric-x')));
  });

  test('openTask reuses an existing rubric and counts past attempts', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
      ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', [
        _attemptJson('旧回答'),
      ]);
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
    );
    expect(controller.state.phase, 'answering');
    expect(controller.state.rubric!.id, 'rubric-x');
    expect(controller.state.pastAttemptCount, 1);
  });

  test('full flow: save rubric, answer, self-assess with span rules', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', null)
      ..on('POST', '/v1/semantic/rubrics', _rubricJson())
      ..on('POST', '/v1/semantic/attempts', _attemptJson('地震发生在棉兰老岛。'))
      ..on('POST', '/v1/semantic/judgments', {
        'id': 'judgment-x',
        'attempt_id': 'attempt-x',
        'response_revision': 1,
        'rubric_id': 'rubric-x',
        'rubric_version': 1,
        'rubric_source_sha256': 'h1',
        'response_transcript_sha256': 'h2',
        'points': [
          {'point_id': 'main-idea', 'verdict': 'covered'},
          {'point_id': 'detail', 'verdict': 'missing'},
        ],
        'abstain': null,
        'provenance': {'kind': 'manual'},
        'evidence_class': 'self_assessment',
        'created_at_ms': 20,
      });
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
    );
    await controller.saveRubric(backend.api);
    expect(controller.state.phase, 'answering');

    await controller.submitAnswer(
      backend.api,
      '地震发生在棉兰老岛。',
      audioPlayCount: 2,
    );
    expect(controller.state.phase, 'assessing');

    controller.setVerdict('main-idea', 'covered');
    expect(controller.state.allPointsJudged, isFalse);
    controller.setVerdict('detail', 'missing');
    expect(controller.state.allPointsJudged, isTrue);
    await controller.submitSelfAssessment(backend.api);
    expect(controller.state.phase, 'done');
    expect(controller.state.judgment!.id, 'judgment-x');

    // Attempt payload: honest reading conditions.
    final attemptBody = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/attempts')
        .$3!;
    expect(attemptBody['conditions']['source_text_visible'], isTrue);
    expect(attemptBody['conditions']['audio_play_count'], 2);
    expect(attemptBody['kind'], 'reading_comprehension');

    // Judgment payload: covered cites the whole response in Unicode scalar
    // counts (9 chars for this answer), missing cites nothing, and the
    // evidence class is self_assessment, never gold.
    final judgmentBody = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/judgments')
        .$3!;
    final points = judgmentBody['points'] as List<dynamic>;
    expect(points[0]['verdict'], 'covered');
    expect(points[0]['supporting_spans'], [
      {'start_char': 0, 'end_char': '地震发生在棉兰老岛。'.runes.length},
    ]);
    expect(points[1]['supporting_spans'], isEmpty);
    expect(judgmentBody['evidence_class'], 'self_assessment');
    expect(judgmentBody['provenance']['kind'], 'manual');
  });

  test('adjudication appends a correction and never rewrites', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
      ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', <dynamic>[])
      ..on('POST', '/v1/semantic/attempts', _attemptJson('回答'))
      ..on('POST', '/v1/semantic/judgments', {
        'id': 'judgment-x',
        'attempt_id': 'attempt-x',
        'response_revision': 1,
        'rubric_id': 'rubric-x',
        'rubric_version': 1,
        'rubric_source_sha256': 'h1',
        'response_transcript_sha256': 'h2',
        'points': [
          {'point_id': 'main-idea', 'verdict': 'partial'},
          {'point_id': 'detail', 'verdict': 'missing'},
        ],
        'abstain': null,
        'provenance': {'kind': 'manual'},
        'evidence_class': 'self_assessment',
        'created_at_ms': 20,
      })
      ..on('POST', '/v1/semantic/adjudications', {
        'id': 'adj-x',
        'judgment_id': 'judgment-x',
        'point_id': 'main-idea',
        'prior_verdict': 'partial',
        'user_verdict': 'covered',
        'note': null,
        'occurred_at_ms': 30,
      });
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
    );
    await controller.submitAnswer(backend.api, '回答');
    controller.setVerdict('main-idea', 'partial');
    controller.setVerdict('detail', 'missing');
    await controller.submitSelfAssessment(backend.api);

    await controller.adjudicate(
      backend.api,
      pointId: 'main-idea',
      userVerdict: 'covered',
    );
    expect(controller.state.adjudications, hasLength(1));
    final body = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/adjudications')
        .$3!;
    expect(body['prior_verdict'], 'partial');
    expect(body['user_verdict'], 'covered');

    // Same verdict as current: refused client-side, no request sent.
    final before = backend.requests.length;
    await controller.adjudicate(
      backend.api,
      pointId: 'detail',
      userVerdict: 'missing',
    );
    expect(backend.requests.length, before);
  });

  test('listening retell records hidden-text conditions and trigger', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
      ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', <dynamic>[])
      ..on('POST', '/v1/semantic/attempts', _attemptJson('复述内容'));
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
      purpose: ReadingTaskController.listeningPurpose,
    );
    expect(controller.state.isListening, isTrue);
    // Lookup went to the listening purpose, not reading.
    expect(backend.requests.first.$2, contains('purpose=l1_retelling'));

    await controller.submitAnswer(backend.api, '复述内容', audioPlayCount: 3);
    final body = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/attempts')
        .$3!;
    expect(body['kind'], 'l1_retelling');
    expect(body['conditions']['source_text_visible'], isFalse);
    expect(body['conditions']['audio_play_count'], 3);
    expect(body['conditions']['l1_trigger'], 'user_requested');
  });

  test('backend failure surfaces an error without fake progress', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', null)
      ..on('POST', '/v1/semantic/rubrics', 500);
    final controller = ReadingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      templatePoints: _template,
    );
    await controller.saveRubric(backend.api);
    expect(controller.state.phase, 'editing');
    expect(controller.state.error, isNotNull);
    expect(controller.state.judgment, isNull);
  });
}
