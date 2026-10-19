import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/data/repositories/reading_task_repository.dart';
import 'package:llplayer_next/models/reading_diff.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';

const _points = [
  RubricPointView(pointId: 'p1', importance: 'required', statement: 'A'),
  RubricPointView(pointId: 'p2', importance: 'required', statement: 'B'),
  RubricPointView(pointId: 'p3', importance: 'optional', statement: 'C'),
];

SemanticJudgmentView _judgment(Map<String, String> verdicts) =>
    SemanticJudgmentView(
      id: 'j1',
      attemptId: 'a1',
      responseRevision: 1,
      rubricId: 'r1',
      rubricVersion: 1,
      rubricSourceSha256: 'h',
      points: [
        for (final entry in verdicts.entries)
          PointJudgmentView(
            pointId: entry.key,
            verdict: entry.value,
            supportingSpans: const [],
          ),
      ],
      provenance: const SemanticProvenanceView(kind: 'manual'),
      evidenceClass: 'self_assessment',
      createdAtMs: 10,
    );

void main() {
  group('sideOutcome', () {
    test('all required covered is yes regardless of optional points', () {
      final judgment = _judgment({
        'p1': 'covered',
        'p2': 'covered',
        'p3': 'missing',
      });
      expect(sideOutcome(_points, judgment, const []), SideOutcome.yes);
    });

    test('all required missing is no', () {
      final judgment = _judgment({'p1': 'missing', 'p2': 'missing'});
      expect(sideOutcome(_points, judgment, const []), SideOutcome.no);
    });

    test('mixed missing and partial without any covered is no', () {
      final judgment = _judgment({'p1': 'missing', 'p2': 'partial'});
      expect(sideOutcome(_points, judgment, const []), SideOutcome.no);
    });

    test('some covered with some missing is partial', () {
      final judgment = _judgment({'p1': 'covered', 'p2': 'missing'});
      expect(sideOutcome(_points, judgment, const []), SideOutcome.partial);
    });

    test('no judgment or abstain is unassessed, never a failure', () {
      expect(sideOutcome(_points, null, const []), SideOutcome.unassessed);
      final abstain = SemanticJudgmentView(
        id: 'j2',
        attemptId: 'a1',
        responseRevision: 1,
        rubricId: 'r1',
        rubricVersion: 1,
        rubricSourceSha256: 'h',
        points: const [],
        abstain: const JudgmentAbstainView(reason: 'unreliable_transcript'),
        provenance: const SemanticProvenanceView(kind: 'manual'),
        evidenceClass: 'self_assessment',
        createdAtMs: 11,
      );
      expect(sideOutcome(_points, abstain, const []), SideOutcome.unassessed);
    });

    test('latest adjudication overrides the original verdict', () {
      final judgment = _judgment({'p1': 'missing', 'p2': 'covered'});
      const corrections = [
        JudgmentAdjudicationView(
          id: 'adj1',
          judgmentId: 'j1',
          pointId: 'p1',
          priorVerdict: 'missing',
          userVerdict: 'covered',
          occurredAtMs: 20,
        ),
      ];
      expect(sideOutcome(_points, judgment, corrections), SideOutcome.yes);
    });
  });

  group('diffExplanationKey', () {
    test('maps the four quadrants and unknown honestly', () {
      expect(
        diffExplanationKey(SideOutcome.yes, SideOutcome.yes),
        'diffBothYes',
      );
      expect(
        diffExplanationKey(SideOutcome.yes, SideOutcome.no),
        'diffReadYesListenNo',
      );
      expect(
        diffExplanationKey(SideOutcome.no, SideOutcome.yes),
        'diffReadNoListenYes',
      );
      expect(diffExplanationKey(SideOutcome.no, SideOutcome.no), 'diffBothNo');
      expect(
        diffExplanationKey(SideOutcome.yes, SideOutcome.unassessed),
        'diffUnknown',
      );
      expect(
        diffExplanationKey(SideOutcome.partial, SideOutcome.partial),
        'diffMixed',
      );
    });
  });

  group('ReadingDiffController', () {
    const source = ReadingTaskSource(
      anchorCueId: 'cue-1',
      mediaId: 'media-1',
      trackId: 'track-1',
      startMs: 1000,
      endMs: 9000,
      sourceLanguage: 'en',
      responseLanguage: 'zh',
      transcriptSnapshot: 'snapshot',
    );

    LocalApi fakeApi({bool withListenSide = false}) => LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path.startsWith('/v1/semantic/rubrics/lookup')) {
          final isRead = path.contains('purpose=reading_comprehension');
          if (!isRead && !withListenSide) {
            return (statusCode: 200, body: 'null');
          }
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': isRead ? 'rubric-read' : 'rubric-listen',
              'purpose': isRead ? 'reading_comprehension' : 'l1_retelling',
              'source': {
                'media_id': 'media-1',
                'track_id': 'track-1',
                'start_ms': 1000,
                'end_ms': 9000,
                'language': 'en',
                'transcript_snapshot': 'snapshot',
              },
              'response_language': 'zh',
              'points': [
                {
                  'point_id': 'p1',
                  'importance': 'required',
                  'statement': 'A',
                  'accepted_paraphrase_notes': null,
                },
              ],
              'version': 1,
              'provenance': {'kind': 'manual'},
              'revision': null,
              'created_at_ms': 5,
            }),
          );
        }
        if (path == '/v1/semantic/rubrics/rubric-read/attempts') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'id': 'attempt-read',
                'kind': 'reading_comprehension',
                'rubric_id': 'rubric-read',
                'rubric_version': 1,
                'conditions': {
                  'source_text_visible': true,
                  'audio_play_count': 0,
                  'notes_allowed': false,
                },
                'responses': [
                  {
                    'revision': 1,
                    'transcript': 'ans',
                    'source': 'typed',
                    'language': 'zh',
                    'recorded_at_ms': 10,
                  },
                ],
                'status': 'completed',
                'started_at_ms': 5,
                'ended_at_ms': 10,
              },
            ]),
          );
        }
        if (path == '/v1/semantic/attempts/attempt-read/judgments') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'id': 'judgment-read',
                'attempt_id': 'attempt-read',
                'response_revision': 1,
                'rubric_id': 'rubric-read',
                'rubric_version': 1,
                'rubric_source_sha256': 'h1',
                'response_transcript_sha256': 'h2',
                'points': [
                  {'point_id': 'p1', 'verdict': 'covered'},
                ],
                'abstain': null,
                'provenance': {'kind': 'manual'},
                'evidence_class': 'self_assessment',
                'created_at_ms': 20,
              },
            ]),
          );
        }
        if (path == '/v1/semantic/judgments/judgment-read/adjudications') {
          return (statusCode: 200, body: '[]');
        }
        if (path.startsWith('/v1/semantic/rubrics/rubric-listen/attempts')) {
          return (statusCode: 200, body: '[]');
        }
        return (statusCode: 404, body: '{"code":"not_found"}');
      },
    );

    test(
      'read side reduces to yes, absent listen side stays unassessed',
      () async {
        final api = fakeApi();
        final controller = ReadingDiffController(
          repository: LocalReadingTaskRepository(() => api),
        );
        await controller.loadDiff(source);
        expect(controller.state.read.outcome, SideOutcome.yes);
        expect(controller.state.listen.outcome, SideOutcome.unassessed);
        expect(controller.state.explanationKey, 'diffUnknown');
      },
    );

    test('listen rubric without judgments is still unassessed', () async {
      final api = fakeApi(withListenSide: true);
      final controller = ReadingDiffController(
        repository: LocalReadingTaskRepository(() => api),
      );
      await controller.loadDiff(source);
      expect(controller.state.listen.rubric, isNotNull);
      expect(controller.state.listen.outcome, SideOutcome.unassessed);
    });
  });
}
