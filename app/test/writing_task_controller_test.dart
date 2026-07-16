import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';

const _source = WritingTaskSource(
  anchorCueId: 'cue-1',
  mediaId: 'media-1',
  trackId: 'track-1',
  startMs: 1000,
  endMs: 9000,
  sourceLanguage: 'en',
  responseLanguage: 'en',
  transcriptSnapshot: 'A storm delayed the ferry until Tuesday.',
);

const _points = [
  RubricPointView(
    pointId: 'task_fulfillment',
    importance: 'required',
    statement: 'Complete the task.',
  ),
];

Map<String, dynamic> _rubric() => {
  'id': 'rubric-writing',
  'purpose': 'summary',
  'source': {
    'media_id': 'media-1',
    'track_id': 'track-1',
    'start_ms': 1000,
    'end_ms': 9000,
    'language': 'en',
    'transcript_snapshot': _source.transcriptSnapshot,
  },
  'response_language': 'en',
  'points': [for (final point in _points) point.toJson()],
  'version': 1,
  'provenance': {'kind': 'manual'},
  'created_at_ms': 1,
};

Map<String, dynamic> _attempt(
  String id,
  List<String> revisions, {
  String kind = 'summary',
}) => {
  'id': id,
  'kind': kind,
  'rubric_id': 'rubric-writing',
  'rubric_version': 1,
  'conditions': {
    'source_text_visible': true,
    'audio_play_count': null,
    'notes_allowed': true,
    'prompt_snapshot': 'Summarize this passage.',
  },
  'responses': [
    for (var index = 0; index < revisions.length; index++)
      {
        'revision': index + 1,
        'raw_transcript': null,
        'transcript': revisions[index],
        'source': 'typed',
        'language': 'en',
        'recorded_at_ms': 10 + index,
      },
  ],
  'status': 'completed',
  'started_at_ms': 5,
  'ended_at_ms': 12,
};

Map<String, dynamic> _finding() => {
  'id': 'finding-1',
  'attempt_id': 'attempt-original',
  'response_revision': 1,
  'response_transcript_sha256': 'hash',
  'layer': 'grammar',
  'severity': 'suggestion',
  'source_span': {'start_char': 8, 'end_char': 10},
  'message': 'Use “a” here.',
  'suggested_replacement': 'a',
  'provenance': {
    'generator': 'local_rule',
    'provider_id': 'harper',
    'provider_version': '0.40.0',
    'ruleset_version': 'curated-american',
    'evidence_class': 'heuristic_proxy',
  },
  'created_at_ms': 20,
};

Map<String, dynamic> _providerJson({
  List<String> allowedUses = const ['semantic_judgment'],
}) => {
  'id': 'prov-1',
  'display_name': 'Test',
  'adapter_kind': 'openai_chat_completions',
  'base_url': 'http://x',
  'model_id': 'm',
  'has_credential': true,
  'timeout_ms': 30000,
  'max_retries': 0,
  'retention': 'unknown',
  'allowed_uses': allowedUses,
  'capability': <String, dynamic>{},
  'created_at_ms': 1,
};

Map<String, dynamic> _llmJudgment(String attemptId, int revision) => {
  'id': 'llm-judgment-$revision',
  'attempt_id': attemptId,
  'response_revision': revision,
  'rubric_id': 'rubric-writing',
  'rubric_version': 1,
  'rubric_source_sha256': 'h1',
  'response_transcript_sha256': 'h2',
  'points': [
    {'point_id': 'task_fulfillment', 'verdict': 'partial'},
  ],
  'abstain': null,
  'provenance': {'kind': 'llm', 'model_id': 'm'},
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 25,
};

class _Backend {
  final requests = <(String, String, Map<String, dynamic>?)>[];
  var attemptPosts = 0;
  Map<String, dynamic>? draft;
  List<Map<String, dynamic>> providers = [];

  LocalApi get api => LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      final decoded = body == null
          ? null
          : jsonDecode(body) as Map<String, dynamic>;
      requests.add((method, path, decoded));
      final Object? response;
      if (method == 'GET' && path.startsWith('/v1/semantic/rubrics/lookup')) {
        response = _rubric();
      } else if (method == 'GET' &&
          path == '/v1/semantic/rubrics/rubric-writing/attempts') {
        response = <dynamic>[];
      } else if (path == '/v1/semantic/writing-drafts/rubric-writing') {
        if (method == 'GET') {
          response = draft;
        } else if (method == 'PUT') {
          draft = {
            'rubric_id': 'rubric-writing',
            'prompt_snapshot': decoded!['prompt_snapshot'],
            'transcript': decoded['transcript'],
            'updated_at_ms': 9,
          };
          response = draft;
        } else if (method == 'DELETE') {
          draft = null;
          response = null;
        } else {
          throw StateError('Unexpected draft method: $method');
        }
      } else if (method == 'POST' && path == '/v1/semantic/attempts') {
        attemptPosts++;
        final revisions = (decoded!['responses'] as List<dynamic>)
            .map((item) => item['transcript'] as String)
            .toList();
        response = _attempt(
          attemptPosts == 1 ? 'attempt-original' : 'attempt-revised',
          revisions,
        );
      } else if (method == 'POST' &&
          path ==
              '/v1/semantic/attempts/attempt-original/writing-findings/local') {
        response = [_finding()];
      } else if (method == 'POST' &&
          path == '/v1/semantic/writing-findings/finding-1/dispositions') {
        response = {
          'id': 'disposition-1',
          'finding_id': 'finding-1',
          'decision': decoded!['decision'],
          'resulting_attempt_id': decoded['resulting_attempt_id'],
          'resulting_response_revision': decoded['resulting_response_revision'],
          'note': null,
          'occurred_at_ms': 30,
        };
      } else if (method == 'GET' && path == '/v1/llm/providers') {
        response = providers;
      } else if (method == 'POST' && path == '/v1/llm/providers/prov-1/judge') {
        response = _llmJudgment(
          decoded!['attempt_id'] as String,
          decoded['response_revision'] as int,
        );
      } else if (method == 'POST' && path == '/v1/semantic/adjudications') {
        response = {
          'id': 'adjudication-1',
          'judgment_id': decoded!['judgment_id'],
          'point_id': decoded['point_id'],
          'prior_verdict': decoded['prior_verdict'],
          'user_verdict': decoded['user_verdict'],
          'note': decoded['note'],
          'occurred_at_ms': 40,
        };
      } else if (method == 'POST' && path == '/v1/semantic/judgments') {
        response = {
          'id': 'judgment-1',
          'attempt_id': 'attempt-revised',
          'response_revision': 2,
          'rubric_id': 'rubric-writing',
          'rubric_version': 1,
          'rubric_source_sha256': 'source-hash',
          'response_transcript_sha256': 'response-hash',
          'points': decoded!['points'],
          'abstain': null,
          'provenance': decoded['provenance'],
          'evidence_class': decoded['evidence_class'],
          'created_at_ms': 31,
        };
      } else {
        throw StateError('Unexpected request: $method $path');
      }
      return (statusCode: 200, body: jsonEncode(response));
    },
  );
}

void main() {
  test(
    'requested feedback never mutates text and acceptance cites new attempt',
    () async {
      final backend = _Backend();
      final controller = WritingTaskController();
      await controller.openTask(
        backend.api,
        source: _source,
        kind: WritingTaskController.summaryKind,
        promptSnapshot: 'Summarize this passage.',
        fixedRubricPoints: _points,
      );
      expect(controller.state.phase, 'drafting');

      controller.updateDraft('This is an useful summary.');
      await controller.submitDraft(backend.api);
      expect(controller.state.phase, 'submitted');
      await controller.requestLocalFeedback(backend.api);
      expect(controller.state.phase, 'revising');
      expect(controller.state.revisionDraft, 'This is an useful summary.');
      expect(controller.state.findings.single.providerId, 'harper');

      controller.decide('finding-1', 'accepted');
      controller.setSelfVerdict('task_fulfillment', 'covered');
      // Accepting a suggestion records intent only; text remains learner-owned.
      expect(controller.state.revisionDraft, 'This is an useful summary.');
      controller.updateRevision('This is a useful summary.');
      await controller.submitRevision(backend.api);
      expect(controller.state.phase, 'done');
      expect(controller.state.selfAssessment?.evidenceClass, 'self_assessment');

      final attempts = backend.requests
          .where((request) => request.$2 == '/v1/semantic/attempts')
          .toList();
      expect(attempts, hasLength(2));
      final revisedResponses = attempts.last.$3!['responses'] as List<dynamic>;
      expect(revisedResponses.map((item) => item['transcript']), [
        'This is an useful summary.',
        'This is a useful summary.',
      ]);
      final disposition = backend.requests
          .singleWhere((request) => request.$2.endsWith('/dispositions'))
          .$3!;
      expect(disposition['resulting_attempt_id'], 'attempt-revised');
      expect(disposition['resulting_response_revision'], 2);
    },
  );

  test('LLM assist judges the latest revision and resets across attempts',
      () async {
    final backend = _Backend()..providers = [_providerJson()];
    final controller = WritingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      kind: WritingTaskController.summaryKind,
      promptSnapshot: 'Summarize this passage.',
      fixedRubricPoints: _points,
    );
    controller.updateDraft('First version.');
    await controller.submitDraft(backend.api);
    // A judgment-capable provider was discovered, but nothing is judged yet.
    expect(controller.state.judgeProviderId, 'prov-1');
    expect(controller.state.llmJudgment, isNull);

    await controller.requestLlmJudgment(backend.api);
    final judgment = controller.state.llmJudgment!;
    // Never gold: the content/organization verdict stays a heuristic proxy,
    // separate from Harper findings and from the learner meaning check.
    expect(judgment.evidenceClass, 'heuristic_proxy');
    expect(judgment.provenance.kind, 'llm');
    var judgeBodies = backend.requests
        .where((r) => r.$2 == '/v1/llm/providers/prov-1/judge')
        .toList();
    expect(judgeBodies.single.$3!['attempt_id'], 'attempt-original');
    expect(judgeBodies.single.$3!['response_revision'], 1);

    // Correcting the LLM verdict appends an adjudication citing the LLM row.
    await controller.adjudicateLlm(
      backend.api,
      pointId: 'task_fulfillment',
      userVerdict: 'covered',
    );
    final adjBody = backend.requests
        .firstWhere((r) => r.$2 == '/v1/semantic/adjudications')
        .$3!;
    expect(adjBody['judgment_id'], 'llm-judgment-1');
    expect(adjBody['prior_verdict'], 'partial');
    expect(adjBody['user_verdict'], 'covered');

    // The revised attempt gets a fresh request; the old judgment (which cited
    // revision 1 of the initial attempt) never carries over.
    controller.startRevisionWithoutFeedback();
    controller.updateRevision('Second version.');
    await controller.submitRevision(backend.api);
    expect(controller.state.phase, 'done');
    expect(controller.state.llmJudgment, isNull);
    expect(controller.state.llmAdjudications, isEmpty);

    await controller.requestLlmJudgment(backend.api);
    judgeBodies = backend.requests
        .where((r) => r.$2 == '/v1/llm/providers/prov-1/judge')
        .toList();
    expect(judgeBodies.last.$3!['attempt_id'], 'attempt-revised');
    expect(judgeBodies.last.$3!['response_revision'], 2);
  });

  test('LLM assist stays hidden without a judgment-capable provider',
      () async {
    final backend = _Backend()
      ..providers = [
        _providerJson(allowedUses: ['rubric_generation']),
      ];
    final controller = WritingTaskController();
    await controller.openTask(
      backend.api,
      source: _source,
      kind: WritingTaskController.summaryKind,
      promptSnapshot: 'Summarize this passage.',
      fixedRubricPoints: _points,
    );
    controller.updateDraft('First version.');
    await controller.submitDraft(backend.api);
    expect(controller.state.judgeProviderId, isNull);
    await controller.requestLlmJudgment(backend.api);
    expect(controller.state.llmJudgment, isNull);
    expect(backend.requests.where((r) => r.$2.endsWith('/judge')), isEmpty);
  });

  test('autosaved draft survives a new controller instance', () async {
    final backend = _Backend();
    Future<void> open(WritingTaskController controller) => controller.openTask(
      backend.api,
      source: _source,
      kind: WritingTaskController.summaryKind,
      promptSnapshot: 'Summarize this passage.',
      fixedRubricPoints: _points,
    );
    final first = WritingTaskController();
    await open(first);
    first.updateDraft('unfinished learner text');
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(backend.draft?['transcript'], 'unfinished learner text');

    final restored = WritingTaskController();
    await open(restored);
    expect(restored.state.draft, 'unfinished learner text');
  });
}
