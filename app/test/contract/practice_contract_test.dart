import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/practice.dart';

void main() {
  test('practice attempt fixture parses typed contract shape', () {
    final attempt = PracticeAttempt.fromJson({
      'id': 'attempt-1',
      'item_id': 'item-1',
      'submitted_at_ms': 10,
      'input': {'text': 'hello'},
      'result': 'partial',
      'score': 0.5,
      'evaluation': {
        'summary': '1/2 tokens matched',
        'token_results': [
          {'expected': 'hello', 'actual': 'hello', 'result': 'correct'},
          {'expected': 'world', 'actual': null, 'result': 'missing'},
        ],
        'extra': {'expected_token_count': 2},
      },
      'generated_observation_ids': ['obs-1'],
      'generated_review_item_ids': ['review-1'],
    });

    expect(attempt.id, 'attempt-1');
    expect(attempt.result, 'partial');
    expect(attempt.evaluation.tokenResults.last.result, 'missing');
    expect(attempt.generatedObservationIds, ['obs-1']);
    expect(attempt.generatedReviewItemIds, ['review-1']);
  });

  test('practice item request serializes OpenAPI field names', () {
    final input = CreatePracticeItem(
      sessionId: 'session-1',
      kind: 'dictation',
      target: const PracticeTarget(
        kind: 'sentence',
        id: 'sentence-1',
        sentenceId: 'sentence-1',
        startMs: 100,
        endMs: 900,
      ),
      promptSnapshot: 'hello world',
      expectedText: 'hello world',
      anchors: const [
        PracticeAnchor(
          kind: 'sentence',
          id: 'sentence-1',
          label: 'hello world',
          sentenceId: 'sentence-1',
          tokenStart: 0,
          tokenEnd: 1,
          startMs: 100,
          endMs: 900,
        ),
      ],
    );

    expect(input.toJson(), {
      'session_id': 'session-1',
      'kind': 'dictation',
      'target': {
        'kind': 'sentence',
        'id': 'sentence-1',
        'sentence_id': 'sentence-1',
        'chunk_id': null,
        'start_ms': 100,
        'end_ms': 900,
      },
      'prompt_snapshot': 'hello world',
      'expected_text': 'hello world',
      'anchors': [
        {
          'kind': 'sentence',
          'id': 'sentence-1',
          'label': 'hello world',
          'lexical_entry_id': null,
          'sentence_id': 'sentence-1',
          'token_start': 0,
          'token_end': 1,
          'start_ms': 100,
          'end_ms': 900,
        },
      ],
    });
  });

  test('practice session summary fixture parses typed contract shape', () {
    final summary = PracticeSessionSummary.fromJson({
      'session': {
        'id': 'session-1',
        'mode': 'intensive',
        'media_id': 'media-1',
        'track_id': 'track-1',
        'source': 'current_sentence_practice',
        'started_at_ms': 1,
        'ended_at_ms': null,
      },
      'stuck_points': [
        {
          'target_key': 'sentence:sentence-1',
          'status': 'unexplained',
          'target': {
            'kind': 'sentence',
            'id': 'sentence-1',
            'sentence_id': 'sentence-1',
            'chunk_id': null,
            'start_ms': 100,
            'end_ms': 900,
          },
          'anchors': [],
          'label': 'would have',
          'marked_at_ms': 2,
          'updated_at_ms': 3,
          'playback_start_ms': 100,
          'playback_end_ms': 900,
          'practice_attempt_ids': [],
          'review_item_ids': [],
          'diagnosis_hints': [
            {
              'kind': 'recognition_barrier',
              'reasons': ['weak_form'],
            },
          ],
        },
      ],
      'stuck_count': 1,
      'resolved_count': 0,
      'active_verified_count': 0,
      'review_count': 0,
      'unexplained_count': 1,
      'skipped_count': 0,
      'closed_count': 0,
      'open_count': 1,
      'attribution_counts': [
        {'kind': 'recognition_barrier', 'reason': 'weak_form', 'count': 1},
      ],
      'familiar_material_marked': false,
    });

    expect(summary.stuckCount, 1);
    expect(summary.stuckPoints.single.status, 'unexplained');
    expect(summary.stuckPoints.single.diagnosisHints.single.reasons, [
      'weak_form',
    ]);
    expect(summary.attributionCounts.single.reason, 'weak_form');
  });
}
