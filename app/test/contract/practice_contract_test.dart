import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/listening.dart';
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

  test('listening inbox fixture parses typed contract shape', () {
    final item = ListeningInboxItem.fromJson({
      'id': 'inbox-1',
      'session_id': 'session-1',
      'media_id': 'media-1',
      'track_id': 'track-1',
      'target': {
        'kind': 'sentence',
        'id': 'sentence-1',
        'sentence_id': 'sentence-1',
        'chunk_id': null,
        'start_ms': 100,
        'end_ms': 900,
      },
      'anchors': [
        {
          'kind': 'sentence',
          'id': 'sentence-1',
          'label': 'would have',
          'lexical_entry_id': null,
          'sentence_id': 'sentence-1',
          'token_start': 0,
          'token_end': 1,
          'start_ms': 100,
          'end_ms': 900,
        },
      ],
      'label': 'would have',
      'subtitle_snapshot': 'would have',
      'context_before': null,
      'context_after': 'gone',
      'captured_at_ms': 10,
      'expires_at_ms': 20,
      'status': 'active',
      'resolution': null,
      'review_item_ids': [],
      'practice_item_id': null,
      'updated_at_ms': 10,
    });

    expect(item.id, 'inbox-1');
    expect(item.status, 'active');
    expect(item.playbackStartMs, 100);
    expect(item.playbackEndMs, 900);
  });
}
