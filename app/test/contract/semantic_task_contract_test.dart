import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/semantic_task.dart';

/// Pins the Phase 3.11 semantic DTOs to the committed gold fixture — the
/// same file the Rust domain/persistence/HTTP contract tests consume, so a
/// shape drift breaks both sides of the wire loudly (ADR 0014).
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    // flutter test runs with cwd = apps/desktop.
    final file = File('../../testdata/semantic-task/gold-fixture-v1.json');
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('rubric parses with points, source snapshot, and provenance', () {
    final rubric = SemanticRubricView.fromJson(
      fixture['rubric'] as Map<String, dynamic>,
    );
    expect(rubric.id, 'rubric-quake-l1-retell');
    expect(rubric.purpose, 'l1_retelling');
    expect(rubric.version, 1);
    expect(rubric.responseLanguage, 'zh');
    expect(rubric.source.mediaId, 'media-cnn10-20260609');
    expect(rubric.source.trackId, isNull);
    expect(rubric.source.transcriptSnapshot, contains('7.8 magnitude'));
    expect(rubric.points, hasLength(5));
    expect(rubric.points.first.pointId, 'p1');
    expect(rubric.points.first.importance, 'required');
    expect(rubric.points[3].importance, 'optional');
    expect(rubric.points[3].acceptedParaphraseNotes, isNull);
    expect(rubric.provenance.kind, 'manual');
  });

  test('rubric source and points round-trip through toJson', () {
    final json = fixture['rubric'] as Map<String, dynamic>;
    final rubric = SemanticRubricView.fromJson(json);
    expect(rubric.source.toJson(), json['source']);
    expect(
      rubric.points.map((p) => p.toJson()).toList(),
      (json['points'] as List<dynamic>)
          .map(
            (p) => {
              'point_id': p['point_id'],
              'importance': p['importance'],
              'statement': p['statement'],
              'accepted_paraphrase_notes': p['accepted_paraphrase_notes'],
            },
          )
          .toList(),
    );
  });

  test('attempts parse conditions, responses, and status', () {
    final attempts = (fixture['attempts'] as List<dynamic>)
        .map((a) => SemanticAttemptView.fromJson(a as Map<String, dynamic>))
        .toList();
    expect(attempts, hasLength(3));
    final good = attempts.first;
    expect(good.kind, 'l1_retelling');
    expect(good.conditions.sourceTextVisible, isFalse);
    expect(good.conditions.audioPlayCount, 1);
    expect(good.responses.single.revision, 1);
    expect(good.responses.single.rawTranscript, isNull);
    expect(good.responses.single.source, 'typed');
    expect(good.responses.single.language, 'zh');
    expect(good.status, 'completed');
    expect(good.endedAtMs, isNotNull);
    expect(attempts.last.responses.single.rawTranscript, '');
  });

  test('judgments parse verdicts, spans, and the abstain arm', () {
    final judgments = (fixture['judgments'] as List<dynamic>)
        .map((j) => SemanticJudgmentView.fromJson(j as Map<String, dynamic>))
        .toList();
    expect(judgments, hasLength(3));

    final good = judgments[0];
    expect(good.isAbstain, isFalse);
    expect(good.points, hasLength(5));
    expect(good.verdictFor('p1'), 'covered');
    expect(good.verdictFor('p4'), 'missing');
    expect(good.verdictFor('p5'), 'partial');
    expect(good.points.first.supportingSpans.single.startChar, 0);
    expect(good.points.first.supportingSpans.single.endChar, 5);
    expect(good.evidenceClass, 'gold');
    expect(good.provenance.kind, 'fixture');

    final abstain = judgments[2];
    expect(abstain.isAbstain, isTrue);
    expect(abstain.points, isEmpty);
    expect(abstain.abstain!.reason, 'unreliable_transcript');
    expect(abstain.verdictFor('p1'), isNull);
  });

  test('adjudication parses the correction pair without mutating anything', () {
    final adjudication = JudgmentAdjudicationView.fromJson(
      (fixture['adjudications'] as List<dynamic>).single
          as Map<String, dynamic>,
    );
    expect(adjudication.judgmentId, 'judgment-b');
    expect(adjudication.pointId, 'p3');
    expect(adjudication.priorVerdict, 'partial');
    expect(adjudication.userVerdict, 'covered');
    expect(adjudication.note, isNotEmpty);
  });

  test(
    'writing feedback and dispositions keep provenance and revision link',
    () {
      final finding = WritingFeedbackFindingView.fromJson({
        'id': 'finding-1',
        'attempt_id': 'attempt-1',
        'response_revision': 1,
        'layer': 'grammar',
        'severity': 'suggestion',
        'source_span': {'start_char': 2, 'end_char': 4},
        'message': 'Check this phrase.',
        'suggested_replacement': 'a',
        'provenance': {'provider_id': 'harper'},
      });
      expect(finding.providerId, 'harper');
      expect(finding.sourceSpan!.endChar, 4);

      final disposition = WritingFindingDispositionView.fromJson({
        'id': 'disposition-1',
        'finding_id': 'finding-1',
        'decision': 'accepted',
        'resulting_attempt_id': 'attempt-2',
        'resulting_response_revision': 2,
      });
      expect(disposition.resultingAttemptId, 'attempt-2');
      expect(disposition.resultingResponseRevision, 2);
    },
  );
}
