import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/screens/review_queue_screen.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  for (final scenario
      in <
        ({String kind, String cue, String answer, String target, String action})
      >[
        (
          kind: 'word_recognition',
          cue: '',
          answer: 'would',
          target: 'would',
          action: '显示听到的词',
        ),
        (
          kind: 'chunk_cloze',
          cue: 'I ____ gone',
          answer: 'I would have gone',
          target: 'would have',
          action: '对照答案',
        ),
        (
          kind: 'phrase_presence',
          cue: 'would have',
          answer: 'I would have gone',
          target: 'would have',
          action: '出现',
        ),
        (
          kind: 'source_sentence_recall',
          cue: '',
          answer: 'I would have gone',
          target: '',
          action: '显示原句',
        ),
      ]) {
    testWidgets('${scenario.kind} exposes its distinct review interaction', (
      tester,
    ) async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          if (path != '/v1/review/items?limit=20') {
            throw StateError('unexpected $method $path');
          }
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'item': {
                  'id': 'review-${scenario.kind}',
                  'source': {
                    'kind': 'sentence',
                    'id': 'sentence-1',
                    'practice_attempt_id': null,
                    'lexical_entry_id': null,
                    'media_id': null,
                    'track_id': null,
                  },
                  'anchors': const [],
                  'prompt_snapshot': scenario.answer,
                  'status': 'active',
                  'created_at_ms': 1,
                  'updated_at_ms': 1,
                },
                'schedule': {
                  'item_id': 'review-${scenario.kind}',
                  'algorithm': 'listen_review_v1_heuristic_proxy',
                  'due_at_ms': 1,
                  'stability': null,
                  'difficulty': null,
                  'interval_days': null,
                  'lapse_count': 0,
                },
                'card': {
                  'kind': scenario.kind,
                  'cue': scenario.cue.isEmpty ? null : scenario.cue,
                  'answer': scenario.answer,
                  'target': scenario.target.isEmpty ? null : scenario.target,
                },
              },
            ]),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewQueueScreen(
            api: api,
            onPlayRange: (startMs, endMs) async {},
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (scenario.kind == 'chunk_cloze') {
        expect(find.text(scenario.cue), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'would have');
      } else if (scenario.kind == 'phrase_presence') {
        expect(find.text(scenario.target), findsOneWidget);
      }

      await tester.tap(find.text(scenario.action));
      await tester.pumpAndSettle();

      expect(find.text(scenario.answer), findsOneWidget);
      expect(find.text('没听出'), findsOneWidget);
      expect(find.text('模糊'), findsOneWidget);
      expect(find.text('听出了'), findsOneWidget);
    });
  }

  testWidgets(
    'delayed retelling enters speaking instead of revealing an answer',
    (tester) async {
      var launched = false;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path ==
              '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
            return (statusCode: 200, body: '[]');
          }
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'item': {
                  'id': 'review-speaking-1',
                  'source': {
                    'kind': 'speaking_attempt',
                    'id': 'attempt-1',
                    'practice_attempt_id': null,
                    'lexical_entry_id': null,
                    'media_id': 'media-1',
                    'track_id': 'track-1',
                  },
                  'anchors': [
                    {
                      'kind': 'sentence',
                      'id': 'cue-1',
                      'label': 'en',
                      'lexical_entry_id': null,
                      'sentence_id': 'cue-1',
                      'token_start': null,
                      'token_end': null,
                      'start_ms': 1000,
                      'end_ms': 12000,
                    },
                  ],
                  'prompt_snapshot': 'The ferry leaves on Tuesday.',
                  'status': 'active',
                  'created_at_ms': 1,
                  'updated_at_ms': 1,
                },
                'schedule': {
                  'item_id': 'review-speaking-1',
                  'algorithm': 'listen_review_v1_heuristic_proxy',
                  'due_at_ms': 1,
                  'stability': null,
                  'difficulty': null,
                  'interval_days': null,
                  'lapse_count': 0,
                },
                'card': {
                  'kind': 'delayed_retelling',
                  'cue': null,
                  'answer': 'The ferry leaves on Tuesday.',
                  'target': null,
                },
              },
            ]),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewQueueScreen(
            api: api,
            onPlayRange: (startMs, endMs) async {},
            onStartShadowing: (_) async {},
            onStartDelayedRetelling: (_) async => launched = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('开始延迟复述'), findsOneWidget);
      expect(find.text('显示原句'), findsNothing);
      await tester.tap(find.text('开始延迟复述'));
      await tester.pumpAndSettle();
      expect(launched, isTrue);
    },
  );

  testWidgets('finished queue shows a non-blocking upgrade suggestion', (
    tester,
  ) async {
    final requests = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        requests.add('$method $path');
        if (path == '/v1/review/items?limit=20') {
          return (statusCode: 200, body: '[]');
        }
        if (path ==
            '/v1/review/upgrade-suggestions?status=pending&limit=100&offset=0') {
          return (statusCode: 200, body: jsonEncode([upgradeSuggestionJson]));
        }
        if (path == '/v1/review/upgrade-suggestions/suggestion-1/reject') {
          return (
            statusCode: 200,
            body: jsonEncode({...upgradeSuggestionJson, 'status': 'rejected'}),
          );
        }
        throw StateError('unexpected $method $path');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewQueueScreen(
          api: api,
          onPlayRange: (startMs, endMs) async {},
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('heard in 5 contexts'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(
      requests.last,
      'POST /v1/review/upgrade-suggestions/suggestion-1/reject',
    );
    expect(find.textContaining('heard in 5 contexts'), findsNothing);
  });
}

const upgradeSuggestionJson = <String, dynamic>{
  'id': 'suggestion-1',
  'lexical_entry_id': 'lexical-1',
  'lexical_display_form': 'would have',
  'previous_status': 'known_not_recognized',
  'suggested_status': 'known_recognized',
  'status': 'pending',
  'evidence_context_count': 5,
  'evidence_ids': ['evidence-1'],
  'threshold': 5,
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 1,
  'resolved_at_ms': null,
  'cooldown_until_ms': null,
};
