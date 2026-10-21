import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/data/repositories/practice_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/panels/intensive_practice_window.dart';

void main() {
  testWidgets('window shows progress, navigates by sentence, and closes', (
    tester,
  ) async {
    final api = _practiceApi();
    final controller = PracticeController(
      repository: LocalPracticeRepository(() => api),
    );
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'Would you listen?',
      tokens: [],
    );
    await controller.startSentenceDictation(
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

    // The floating window carries sentence progress in its meta row; there is
    // no mini player any more — playback lives in the keyboard-hint foot.
    expect(find.text('Sentence 1 of 3'), findsOneWidget);
    expect(find.text('Current sentence'), findsNothing);

    // Prev/next live in the foot's keyboard-hint strip.
    await tester.tap(find.byTooltip('Next sentence'));
    expect(navigated, 1);

    await tester.tap(find.byTooltip('Close'));
    expect(closed, isTrue);
    controller.dispose();
  });

  testWidgets('window keeps prompt visible while the next item is in flight', (
    tester,
  ) async {
    final gate = Completer<void>();
    var api = _practiceApi();
    final controller = PracticeController(
      repository: LocalPracticeRepository(() => api),
    );
    const cueOne = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'First sentence.',
      tokens: [],
    );
    const cueTwo = Cue(
      id: 'sentence-2',
      index: 1,
      start: Duration(milliseconds: 900),
      end: Duration(milliseconds: 1700),
      text: 'Second sentence.',
      tokens: [],
    );
    await controller.startSentenceDictation(
      cue: cueOne,
      mediaId: 'media-1',
      trackId: 'track-1',
      mediaTimeMs: (value) => value.inMilliseconds,
    );
    expect(controller.item, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              IntensivePracticeWindow(
                controller: controller,
                currentSentence: 2,
                totalSentences: 3,
                canGoPrevious: true,
                canGoNext: true,
                isPlaying: false,
                onReplay: () async {},
                onTogglePlayback: () async {},
                onNavigate: (_) async {},
                onSubmit: () async {},
                onSaveReview: () async {},
                onClose: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Listen, then type what you heard.'), findsOneWidget);

    // Navigate to the neighbouring sentence: the draft flips synchronously
    // while the new item is created asynchronously. The prompt must stay on
    // screen the whole time instead of falling back to the placeholder.
    api = _practiceApi(itemGate: gate.future);
    final pending = controller.startSentenceDictation(
      cue: cueTwo,
      mediaId: 'media-1',
      trackId: 'track-1',
      mediaTimeMs: (value) => value.inMilliseconds,
    );
    await tester.pump();
    expect(controller.item, isNull);
    expect(controller.draft, isNotNull);
    expect(
      find.text('Choose cloze or dictation for this sentence.'),
      findsNothing,
    );
    expect(find.text('Listen, then type what you heard.'), findsOneWidget);

    gate.complete();
    await pending;
    await tester.pump();
    expect(controller.item, isNotNull);
    expect(find.text('Listen, then type what you heard.'), findsOneWidget);
    controller.dispose();
  });
}

LocalApi _practiceApi({Future<void>? itemGate}) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    final decoded = body == null ? null : jsonDecode(body);
    if (path == '/v1/practice/items' && itemGate != null) await itemGate;
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
