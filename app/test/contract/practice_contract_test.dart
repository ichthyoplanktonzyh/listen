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

  test('shadowing recording and comparison keep objective typed fields', () {
    final input = CreateRecordingAsset(
      filePath: '/tmp/mine.wav',
      durationMs: 880,
      target: const PracticeTarget(
        kind: 'chunk',
        id: 'chunk-1',
        sentenceId: 'sentence-1',
        chunkId: 'chunk-1',
        startMs: 100,
        endMs: 900,
      ),
      sourceSegment: const PlayableSegment(
        mediaId: 'media-1',
        startMs: 100,
        endMs: 900,
        label: 'chunk 1',
        subtitleSnapshot: 'follow this',
        availability: 'available',
      ),
      language: 'en',
      audio: const RecordingAudioMetadata(
        container: 'wav',
        codec: 'pcm_s16le',
        sampleRateHz: 16000,
        channels: 1,
        sampleFormat: 's16',
        byteLength: 28000,
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      recorderVersion: 'macos-avfoundation-pcm16-v1',
    );
    expect(input.toJson()['audio'], containsPair('sample_rate_hz', 16000));

    final comparison = ShadowingComparison.fromJson({
      'attempt_id': 'attempt-1',
      'reference_segment': input.sourceSegment.toJson(),
      'recording_id': 'recording-1',
      'duration_delta_ms': 80,
      'pause_alignment': {
        'reference_pauses': [
          {'start_ms': 300, 'end_ms': 450},
        ],
        'recording_pauses': [
          {'start_ms': 340, 'end_ms': 500},
        ],
        'mean_absolute_offset_ms': 45,
      },
      'reference_waveform': {
        'duration_ms': 800,
        'bucket_ms': 100,
        'peaks': [0.2, 0.8],
        'rms': [0.1, 0.5],
      },
      'recording_waveform': {
        'duration_ms': 880,
        'bucket_ms': 110,
        'peaks': [0.3, 0.7],
        'rms': [0.2, 0.4],
      },
    });
    expect(comparison.durationDeltaMs, 80);
    expect(comparison.meanAbsolutePauseOffsetMs, 45);
    expect(comparison.referencePauses.single.startMs, 300);
    expect(comparison.recordingWaveform.peaks, [0.3, 0.7]);
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

  test('hunting target and candidate fixtures parse typed contract shapes', () {
    final target = HuntingTarget.fromJson({
      'id': 'target-1',
      'lexical_entry_id': 'lexical-1',
      'source_kind': 'review_candidate',
      'source_id': 'candidate-1',
      'target_snapshot': 'would have',
      'status': 'active',
      'created_at_ms': 10,
      'updated_at_ms': 20,
    });
    final candidate = HuntingCandidate.fromJson({
      'id': 'candidate-1',
      'lexical_entry_id': 'lexical-1',
      'review_item_id': 'review-1',
      'sentence_id': null,
      'media_id': null,
      'track_id': null,
      'target_snapshot': 'would have',
      'prompt_snapshot': 'I would have gone.',
      'failure_count': 2,
      'status': 'active',
      'created_at_ms': 10,
      'last_failed_at_ms': 20,
    });

    expect(target.sourceKind, 'review_candidate');
    expect(target.sourceId, candidate.id);
    expect(candidate.failureCount, 2);
  });

  test('hunting occurrence query and check result parse typed shapes', () {
    final result = HuntingOccurrenceQueryResult.fromJson({
      'indexed': true,
      'occurrences': [
        {
          'target_id': 'target-1',
          'lexical_entry_id': 'lexical-1',
          'target_snapshot': 'would have',
          'occurrence': {
            'id': 'occurrence-1',
            'language': 'en',
            'kind': 'phrase',
            'normalized_key': 'i would have gone',
            'display_text': 'I would have gone.',
            'media_id': 'media-1',
            'track_id': 'track-1',
            'sentence_id': 'sentence-1',
            'start_ms': 100,
            'end_ms': 900,
            'source_snapshot': 'I would have gone.',
          },
        },
      ],
    });
    final check = HuntingCheckResult.fromJson({
      'answer': 'not_noticed',
      'event_id': 'event-1',
      'observation_id': null,
    });

    expect(result.indexed, isTrue);
    expect(result.occurrences.single.occurrence.sentenceId, 'sentence-1');
    expect(check.answer, 'not_noticed');
    expect(check.observationId, isNull);
  });
}
