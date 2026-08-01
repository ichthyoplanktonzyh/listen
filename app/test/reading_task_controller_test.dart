import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/data/repositories/reading_task_repository.dart';
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

Map<String, dynamic> _providerJson() => {
  'id': 'prov-1',
  'display_name': 'Test',
  'adapter_kind': 'openai_chat_completions',
  'base_url': 'http://x',
  'model_id': 'm',
  'has_credential': true,
  'timeout_ms': 30000,
  'max_retries': 0,
  'retention': 'unknown',
  'allowed_uses': ['semantic_judgment'],
  'capability': <String, dynamic>{},
  'created_at_ms': 1,
};

Map<String, dynamic> _llmJudgmentJson() => {
  'id': 'llm-judgment-1',
  'attempt_id': 'attempt-x',
  'response_revision': 1,
  'rubric_id': 'rubric-x',
  'rubric_version': 1,
  'rubric_source_sha256': 'h1',
  'response_transcript_sha256': 'h2',
  'points': [
    {'point_id': 'main-idea', 'verdict': 'covered'},
    {'point_id': 'detail', 'verdict': 'partial'},
  ],
  'abstain': null,
  'provenance': {'kind': 'llm', 'model_id': 'm'},
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 25,
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

ReadingTaskController _controller(_FakeBackend backend) =>
    ReadingTaskController(
      repository: LocalReadingTaskRepository(() => backend.api),
    );

void main() {
  test('openTask with no existing rubric enters template editing', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', null);
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
    expect(controller.state.phase, 'editing');
    expect(controller.state.draftPoints, hasLength(2));
    // Lookup carried the source identity, not a client-derived id.
    final (_, path, _) = backend.requests.firstWhere(
      (r) => r.$2.startsWith('/v1/semantic/rubrics/lookup'),
    );
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
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
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
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
    await controller.saveRubric();
    expect(controller.state.phase, 'answering');

    await controller.submitAnswer('地震发生在棉兰老岛。', audioPlayCount: 2);
    expect(controller.state.phase, 'assessing');

    controller.setVerdict('main-idea', 'covered');
    expect(controller.state.allPointsJudged, isFalse);
    controller.setVerdict('detail', 'missing');
    expect(controller.state.allPointsJudged, isTrue);
    await controller.submitSelfAssessment();
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
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
    await controller.submitAnswer('回答');
    controller.setVerdict('main-idea', 'partial');
    controller.setVerdict('detail', 'missing');
    await controller.submitSelfAssessment();

    await controller.adjudicate(pointId: 'main-idea', userVerdict: 'covered');
    expect(controller.state.adjudications, hasLength(1));
    final body = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/adjudications')
        .$3!;
    expect(body['prior_verdict'], 'partial');
    expect(body['user_verdict'], 'covered');

    // Same verdict as current: refused client-side, no request sent.
    final before = backend.requests.length;
    await controller.adjudicate(pointId: 'detail', userVerdict: 'missing');
    expect(backend.requests.length, before);
  });

  test('listening retell records hidden-text conditions and trigger', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
      ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', <dynamic>[])
      ..on('POST', '/v1/semantic/attempts', _attemptJson('复述内容'));
    final controller = _controller(backend);
    await controller.openTask(
      source: _source,
      templatePoints: _template,
      purpose: ReadingTaskController.listeningPurpose,
    );
    expect(controller.state.isListening, isTrue);
    // Lookup went to the listening purpose, not reading.
    expect(backend.requests.first.$2, contains('purpose=l1_retelling'));

    await controller.submitAnswer('复述内容', audioPlayCount: 3);
    final body = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/attempts')
        .$3!;
    expect(body['kind'], 'l1_retelling');
    expect(body['conditions']['source_text_visible'], isFalse);
    expect(body['conditions']['audio_play_count'], 3);
    expect(body['conditions']['l1_trigger'], 'user_requested');
  });

  test(
    'LLM assist: request judgment, correct it, stays honest heuristic',
    () async {
      final backend = _FakeBackend()
        ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
        ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', <dynamic>[])
        ..on('POST', '/v1/semantic/attempts', _attemptJson('地震发生在棉兰老岛。'))
        ..on('GET', '/v1/llm/providers', [_providerJson()])
        ..on('POST', '/v1/llm/providers/prov-1/judge', _llmJudgmentJson())
        ..on('POST', '/v1/semantic/adjudications', {
          'id': 'adj-ai',
          'judgment_id': 'llm-judgment-1',
          'point_id': 'detail',
          'prior_verdict': 'partial',
          'user_verdict': 'covered',
          'note': null,
          'occurred_at_ms': 40,
        });
      final controller = _controller(backend);
      await controller.openTask(source: _source, templatePoints: _template);
      await controller.submitAnswer('地震发生在棉兰老岛。', audioPlayCount: 2);
      // A judgment-capable provider was discovered, but nothing is judged yet.
      expect(controller.state.judgeProviderId, 'prov-1');
      expect(controller.state.llmJudgment, isNull);

      await controller.requestLlmJudgment();
      final judgment = controller.state.llmJudgment!;
      expect(judgment.id, 'llm-judgment-1');
      // Never gold: an unqualified provider verdict stays a heuristic proxy.
      expect(judgment.evidenceClass, 'heuristic_proxy');
      expect(judgment.provenance.kind, 'llm');
      expect(judgment.verdictFor('main-idea'), 'covered');

      // The judge request cites the stored attempt + revision, not client id.
      final judgeBody = backend.requests
          .firstWhere((r) => r.$2 == '/v1/llm/providers/prov-1/judge')
          .$3!;
      expect(judgeBody['attempt_id'], 'attempt-x');
      expect(judgeBody['response_revision'], 1);

      // Correcting the LLM verdict appends an adjudication citing the LLM row.
      await controller.adjudicateLlm(pointId: 'detail', userVerdict: 'covered');
      expect(controller.state.llmAdjudications, hasLength(1));
      final adjBody = backend.requests
          .firstWhere((r) => r.$2 == '/v1/semantic/adjudications')
          .$3!;
      expect(adjBody['judgment_id'], 'llm-judgment-1');
      expect(adjBody['prior_verdict'], 'partial');
      expect(adjBody['user_verdict'], 'covered');
    },
  );

  test(
    'AI rubric generation loads an editable draft saved as llm provenance',
    () async {
      final backend = _FakeBackend()
        ..on('GET', '/v1/semantic/rubrics/lookup', null)
        ..on('GET', '/v1/llm/providers', [
          {
            ..._providerJson(),
            'allowed_uses': ['rubric_generation'],
          },
        ])
        ..on('POST', '/v1/llm/providers/prov-1/rubric', {
          'points': [
            {
              'importance': 'required',
              'statement': 'AI 主旨',
              'accepted_paraphrase_notes': null,
            },
            {
              'importance': 'optional',
              'statement': 'AI 细节',
              'accepted_paraphrase_notes': null,
            },
          ],
          'model_id': 'deepseek-x',
          'prompt_version': 'rubric-gen/v1',
          'schema_version': 'semantic/v1',
        })
        ..on('POST', '/v1/semantic/rubrics', _rubricJson());
      final controller = _controller(backend);
      await controller.openTask(source: _source, templatePoints: _template);
      expect(controller.state.phase, 'editing');
      expect(controller.state.rubricProviderId, 'prov-1');

      await controller.generateRubric();
      // The draft is loaded into the editable template (client-assigned ids),
      // not auto-saved.
      expect(controller.state.phase, 'editing');
      expect(controller.state.draftPoints.map((p) => p.statement).toList(), [
        'AI 主旨',
        'AI 细节',
      ]);
      expect(controller.state.draftPoints.first.pointId, 'p1');

      // Saving the reviewed draft records honest llm provenance with the model.
      await controller.saveRubric();
      final body = backend.requests
          .firstWhere((r) => r.$2 == '/v1/semantic/rubrics')
          .$3!;
      expect(body['provenance']['kind'], 'llm');
      expect(body['provenance']['model_id'], 'deepseek-x');
    },
  );

  test('LLM assist stays hidden without a judgment-capable provider', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', _rubricJson())
      ..on('GET', '/v1/semantic/rubrics/rubric-x/attempts', <dynamic>[])
      ..on('POST', '/v1/semantic/attempts', _attemptJson('回答'))
      ..on('GET', '/v1/llm/providers', [
        {
          ..._providerJson(),
          'allowed_uses': ['rubric_generation'],
        },
      ]);
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
    await controller.submitAnswer('回答');
    expect(controller.state.judgeProviderId, isNull);
  });

  test('backend failure surfaces an error without fake progress', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', null)
      ..on('POST', '/v1/semantic/rubrics', 500);
    final controller = _controller(backend);
    await controller.openTask(source: _source, templatePoints: _template);
    await controller.saveRubric();
    expect(controller.state.phase, 'editing');
    expect(controller.state.error, isNotNull);
    expect(controller.state.judgment, isNull);
  });

  test('repository converts transport errors into typed failures', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/semantic/rubrics/lookup', 500);
    final repository = LocalReadingTaskRepository(() => backend.api);

    await expectLater(
      repository.lookupRubric(
        mediaId: _source.mediaId,
        startMs: _source.startMs,
        endMs: _source.endMs,
        purpose: ReadingTaskController.readingPurpose,
        responseLanguage: _source.responseLanguage,
        transcriptSnapshot: _source.transcriptSnapshot,
      ),
      throwsA(isA<ReadingTaskRepositoryFailure>()),
    );
  });
}
