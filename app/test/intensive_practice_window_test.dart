import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/panels/intensive_practice_window.dart';

void main() {
  testWidgets('window can hide its player, navigate, and close', (
    tester,
  ) async {
    final controller = PracticeController();
    final api = _practiceApi();
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'Would you listen?',
      tokens: [],
    );
    await controller.startSentenceDictation(
      api: api,
      cue: cue,
      mediaId: 'media-1',
      trackId: 'track-1',
      mediaTimeMs: (value) => value.inMilliseconds,
    );

    var navigated = 0;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              IntensivePracticeWindow(
                controller: controller,
                currentSentence: 1,
                totalSentences: 3,
                canGoPrevious: false,
                canGoNext: true,
                isPlaying: false,
                onReplay: () async {},
                onTogglePlayback: () async {},
                onNavigate: (delta) async => navigated = delta,
                onSubmit: () async {},
                onSaveReview: () async {},
                onClose: () async => closed = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Current sentence'), findsOneWidget);
    expect(find.text('Sentence 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide player'));
    await tester.pump();
    expect(find.text('Current sentence'), findsNothing);
    expect(find.text('Sentence 1 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Show player'));
    await tester.pump();
    await tester.tap(find.byTooltip('Next sentence'));
    expect(navigated, 1);

    await tester.tap(find.byTooltip('Close'));
    expect(closed, isTrue);
    controller.dispose();
  });
}

LocalApi _practiceApi() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    final decoded = body == null ? null : jsonDecode(body);
    if (path == '/v1/practice/sessions') {
      return (
        statusCode: 200,
        body:
            '{"id":"session-1","mode":"intensive","media_id":"media-1","track_id":"track-1","source":"current_sentence_practice","started_at_ms":1,"ended_at_ms":null}',
      );
    }
    if (path == '/v1/practice/items') {
      final input = decoded as Map<String, dynamic>;
      return (
        statusCode: 200,
        body: jsonEncode({
          'id': 'item-1',
          'session_id': input['session_id'],
          'kind': input['kind'],
          'target': input['target'],
          'prompt_snapshot': input['prompt_snapshot'],
          'expected_answer': {'text': input['expected_text']},
          'anchors': input['anchors'],
          'created_at_ms': 2,
        }),
      );
    }
    return (statusCode: 404, body: 'unexpected $method $path');
  },
);
