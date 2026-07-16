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

class _Backend {
  final requests = <(String, String, Map<String, dynamic>?)>[];
  var attemptPosts = 0;
  Map<String, dynamic>? draft;

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
