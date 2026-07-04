import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('practice controller creates cloze item and submits attempt', () async {
    final requests = <({String method, String path, Object? body})>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        final decoded = body == null ? null : jsonDecode(body);
        requests.add((method: method, path: path, body: decoded));
        if (path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"intensive","media_id":"media-1","track_id":"track-1","source":"current_sentence_practice","started_at_ms":1,"ended_at_ms":null}',
          );
        }
        if (path == '/v1/practice/items') {
          final value = decoded as Map<String, dynamic>;
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'item-1',
              'session_id': value['session_id'],
              'kind': value['kind'],
              'target': value['target'],
              'prompt_snapshot': value['prompt_snapshot'],
              'expected_answer': {'text': value['expected_text']},
              'anchors': value['anchors'],
              'created_at_ms': 2,
            }),
          );
        }
        if (path == '/v1/practice/attempts') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'attempt-1',
              'item_id': 'item-1',
              'submitted_at_ms': 3,
              'input': {'text': 'hard'},
              'result': 'incorrect',
              'score': 0.0,
              'evaluation': {
                'summary': '0/1 tokens matched',
                'token_results': [
                  {'expected': 'heard', 'actual': 'hard', 'result': 'mismatch'},
                ],
                'extra': {},
              },
              'generated_observation_ids': ['obs-1'],
              'generated_review_item_ids': [],
            }),
          );
        }
        if (path == '/v1/review/items') {
          final value = decoded as Map<String, dynamic>;
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'review-1',
              'source': value['source'],
              'anchors': value['anchors'],
              'prompt_snapshot': value['prompt_snapshot'],
              'status': 'active',
              'created_at_ms': 4,
              'updated_at_ms': 4,
            }),
          );
        }
        if (path == '/v1/practice/sessions/session-1/summary') {
          return (
            statusCode: 200,
            body: jsonEncode(_summaryJson(stuckCount: 0)),
          );
        }
        return (statusCode: 404, body: 'unexpected $method $path');
      },
    );
    final controller = PracticeController();
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'I heard it',
      tokens: [
        SubtitleToken(index: 0, kind: 'word', text: 'I ', normalized: 'i'),
        SubtitleToken(
          index: 1,
          kind: 'word',
          text: 'heard ',
          normalized: 'heard',
        ),
        SubtitleToken(index: 2, kind: 'word', text: 'it', normalized: 'it'),
      ],
    );

    await controller.startCloze(
      api: api,
      cue: cue,
      mediaId: 'media-1',
      trackId: 'track-1',
      wordTimings: const [
        WordTiming(
          sentenceId: 'sentence-1',
          tokenIndex: 1,
          start: Duration(milliseconds: 240),
          end: Duration(milliseconds: 430),
          source: 'forced_aligned',
          provider: 'fixture',
        ),
      ],
      wordEntries: const {
        'heard': LexicalEntry(
          id: 'lexical-heard',
          normalizedForm: 'heard',
          displayForm: 'heard',
          kind: 'word',
          status: 'known_recognized',
          language: 'en',
        ),
      },
      mediaTimeMs: (value) => value.inMilliseconds + 10,
    );

    expect(controller.item?.kind, 'cloze');
    expect(controller.draft?.promptText, 'I ____it');
    expect(controller.draft?.expectedText, 'heard');
    expect(controller.draft?.playbackStartMs, 250);
    expect(
      controller.item?.anchors.any((a) => a.lexicalEntryId == 'lexical-heard'),
      true,
    );

    controller.setAnswer('hard');
    await controller.submit(api);

    expect(controller.attempt?.result, 'incorrect');
    expect(controller.attempt?.generatedObservationIds, ['obs-1']);

    await controller.saveCurrentFailureToReview(api);

    expect(controller.attempt?.generatedReviewItemIds, ['review-1']);
    expect(controller.summary?.stuckCount, 0);
    expect(controller.error, isNull);
    final itemRequest = requests.firstWhere(
      (r) => r.path == '/v1/practice/items',
    );
    expect(
      (itemRequest.body as Map<String, dynamic>)['expected_text'],
      'heard',
    );
  });

  test('practice controller marks current sentence as a stuck point', () async {
    final requests = <({String method, String path, Object? body})>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        final decoded = body == null ? null : jsonDecode(body);
        requests.add((method: method, path: path, body: decoded));
        if (path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"intensive","media_id":"media-1","track_id":"track-1","source":"current_sentence_practice","started_at_ms":1,"ended_at_ms":null}',
          );
        }
        if (path == '/v1/practice/stuck-points/mark') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'event-1',
              'occurred_at_ms': 2,
              'kind': 'stuck_point_marked',
              'subject': {'kind': 'sentence', 'id': 'sentence-1'},
              'payload': decoded,
              'session_id': 'session-1',
            }),
          );
        }
        if (path == '/v1/practice/sessions/session-1/summary') {
          return (
            statusCode: 200,
            body: jsonEncode(_summaryJson(stuckCount: 1, openCount: 1)),
          );
        }
        return (statusCode: 404, body: 'unexpected $method $path');
      },
    );
    final controller = PracticeController();
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'would have',
      tokens: [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'would ',
          normalized: 'would',
        ),
        SubtitleToken(index: 1, kind: 'word', text: 'have', normalized: 'have'),
      ],
    );

    final marked = await controller.markCurrentStuckPoint(
      api: api,
      cue: cue,
      chunk: null,
      mediaId: 'media-1',
      trackId: 'track-1',
      mediaTimeMs: (value) => value.inMilliseconds,
      diagnosis: const Diagnosis(
        hints: [
          DiagnosisHint(kind: 'recognition_barrier', reasons: ['weak_form']),
        ],
      ),
    );

    expect(marked, true);
    expect(controller.summary?.stuckCount, 1);
    expect(controller.summary?.openCount, 1);
    final markRequest = requests.firstWhere(
      (r) => r.path == '/v1/practice/stuck-points/mark',
    );
    final body = markRequest.body as Map<String, dynamic>;
    expect(body['session_id'], 'session-1');
    expect(body['target']['kind'], 'sentence');
    expect(body['diagnosis_hints'][0]['reasons'], ['weak_form']);
  });
}

Map<String, dynamic> _summaryJson({
  required int stuckCount,
  int openCount = 0,
}) => {
  'session': {
    'id': 'session-1',
    'mode': 'intensive',
    'media_id': 'media-1',
    'track_id': 'track-1',
    'source': 'current_sentence_practice',
    'started_at_ms': 1,
    'ended_at_ms': null,
  },
  'stuck_points': [],
  'stuck_count': stuckCount,
  'resolved_count': 0,
  'active_verified_count': 0,
  'review_count': 0,
  'unexplained_count': 0,
  'skipped_count': 0,
  'closed_count': 0,
  'open_count': openCount,
  'attribution_counts': [],
  'familiar_material_marked': false,
};
