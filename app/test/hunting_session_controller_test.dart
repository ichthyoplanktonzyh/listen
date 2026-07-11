import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('hunting session enforces total and per-target prompt budgets', () async {
    final answers = <Map<String, dynamic>>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        if (path ==
            '/v1/hunting/occurrences?media_id=media-1&track_id=track-1') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'indexed': true,
              'occurrences': [
                huntingOccurrence('o1', 't1', 2000),
                huntingOccurrence('o2', 't1', 5000),
                huntingOccurrence('o3', 't1', 8000),
                huntingOccurrence('o4', 't2', 11000),
                huntingOccurrence('o5', 't2', 14000),
                huntingOccurrence('o6', 't3', 17000),
              ],
            }),
          );
        }
        if (method == 'POST' && path == '/v1/hunting/checks') {
          final decoded = jsonDecode(body!) as Map<String, dynamic>;
          answers.add(decoded);
          return (
            statusCode: 200,
            body: jsonEncode({
              'answer': decoded['answer'],
              'event_id': 'event-${answers.length}',
              'observation_id': decoded['answer'] == 'not_noticed'
                  ? null
                  : 'observation-${answers.length}',
            }),
          );
        }
        throw StateError('unexpected $method $path');
      },
    );
    final controller = HuntingSessionController();
    addTearDown(controller.dispose);
    expect(
      await controller.start(
        api: api,
        sessionId: 'session-1',
        mediaId: 'media-1',
        trackId: 'track-1',
      ),
      isTrue,
    );

    for (final entry in [
      ('o1', 2000, 'recognized'),
      ('o2', 5000, 'not_recognized'),
      // o3 is the third occurrence of t1 and must be skipped by per-target cap.
      ('o4', 11000, 'not_noticed'),
      ('o5', 14000, 'recognized'),
      ('o6', 17000, 'recognized'),
    ]) {
      controller.updatePosition(Duration(milliseconds: entry.$2 - 1000));
      expect(controller.state.phase, 'priming', reason: entry.$1);
      controller.updatePosition(Duration(milliseconds: entry.$2 + 1000));
      expect(controller.state.phase, 'check', reason: entry.$1);
      expect(await controller.answer(api, entry.$3), isTrue);
    }

    expect(controller.state.promptedCount, 5);
    expect(controller.state.perTargetPromptCount['t1'], 2);
    expect(controller.state.recognizedCount, 3);
    expect(controller.state.notRecognizedCount, 1);
    expect(controller.state.notNoticedCount, 1);
    expect(answers[2]['answer'], 'not_noticed');
    expect(answers[2]['session_id'], 'session-1');
  });
}

Map<String, dynamic> huntingOccurrence(
  String occurrenceId,
  String targetId,
  int startMs,
) => {
  'target_id': targetId,
  'lexical_entry_id': 'lexical-$targetId',
  'target_snapshot': 'target $targetId',
  'occurrence': {
    'id': occurrenceId,
    'language': 'en',
    'kind': 'lexical',
    'normalized_key': 'target',
    'display_text': 'target',
    'media_id': 'media-1',
    'track_id': 'track-1',
    'sentence_id': 'sentence-$occurrenceId',
    'start_ms': startMs,
    'end_ms': startMs + 1000,
    'source_snapshot': 'A target appears here.',
  },
};
