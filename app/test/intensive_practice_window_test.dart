import 'dart:async';
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
                onStartRecording: () async {},
                onStopRecording: () async {},
                onCancelRecording: () async {},
                onOpenMicrophoneSettings: () async {},
                onPlayReference: () async {},
                onPlayRecording: () async {},
                onPlayAba: () async {},
                onDeleteRecording: () async {},
                onShadowingRateChanged: (_) async {},
                onShadowingStepChanged: (_) async {},
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

  testWidgets(
    'shadowing panel exposes speed, expansion, and recording controls',
    (tester) async {
      final controller = PracticeController();
      const cue = Cue(
        id: 'sentence-shadow',
        index: 0,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 1500),
        text: 'One two three.',
        tokens: [],
      );
      const chunks = [
        DisplayChunk(
          index: 0,
          tokenStart: 0,
          tokenEnd: 0,
          text: 'One',
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 500),
        ),
        DisplayChunk(
          index: 1,
          tokenStart: 1,
          tokenEnd: 1,
          text: 'two',
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 900),
        ),
        DisplayChunk(
          index: 2,
          tokenStart: 2,
          tokenEnd: 2,
          text: 'three',
          start: Duration(milliseconds: 900),
          end: Duration(milliseconds: 1500),
        ),
      ];
      await controller.startShadowing(
        api: _practiceApi(),
        cue: cue,
        chunk: chunks.first,
        chunks: chunks,
        mediaId: 'media-1',
        trackId: 'track-1',
        mediaTimeMs: (value) => value.inMilliseconds,
      );
      var originalPlays = 0;
      var recordStarts = 0;
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
                  totalSentences: 1,
                  canGoPrevious: false,
                  canGoNext: false,
                  isPlaying: false,
                  onReplay: () async {},
                  onTogglePlayback: () async {},
                  onNavigate: (_) async {},
                  onSubmit: () async {},
                  onSaveReview: () async {},
                  onStartRecording: () async => recordStarts++,
                  onStopRecording: () async {},
                  onCancelRecording: () async {},
                  onOpenMicrophoneSettings: () async {},
                  onPlayReference: () async => originalPlays++,
                  onPlayRecording: () async {},
                  onPlayAba: () async {},
                  onDeleteRecording: () async {},
                  onShadowingRateChanged: (_) async {},
                  onShadowingStepChanged: (_) async {},
                  onClose: () async {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Shadowing'), findsOneWidget);
      expect(find.text('0.9×'), findsOneWidget);
      expect(find.text('1 + 2'), findsOneWidget);
      expect(find.text('Objective comparison · no score'), findsNothing);
      await tester.tap(find.text('Play original'));
      await tester.tap(find.text('Start recording'));
      expect(originalPlays, 1);
      expect(recordStarts, 1);
      controller.dispose();
    },
  );

  testWidgets('window keeps prompt visible while the next item is in flight', (
    tester,
  ) async {
    final gate = Completer<void>();
    final controller = PracticeController();
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
      api: _practiceApi(),
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
                onStartRecording: () async {},
                onStopRecording: () async {},
                onCancelRecording: () async {},
                onOpenMicrophoneSettings: () async {},
                onPlayReference: () async {},
                onPlayRecording: () async {},
                onPlayAba: () async {},
                onDeleteRecording: () async {},
                onShadowingRateChanged: (_) async {},
                onShadowingStepChanged: (_) async {},
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
    final pending = controller.startSentenceDictation(
      api: _practiceApi(itemGate: gate.future),
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

  testWidgets('cross-media shadowing hides primary sentence navigation', (
    tester,
  ) async {
    final controller = PracticeController();
    await controller.startExternalShadowing(
      api: _practiceApi(),
      mediaPath: '/tmp/source.mp4',
      mediaId: 'source-media',
      trackId: 'source-track',
      sentenceId: 'source-sentence',
      promptText: 'Only this source sentence.',
      startMs: 100,
      endMs: 900,
    );
    var toggled = false;
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              IntensivePracticeWindow(
                controller: controller,
                currentSentence: 9,
                totalSentences: 20,
                canGoPrevious: true,
                canGoNext: true,
                showSentenceNavigation: false,
                isPlaying: false,
                onReplay: () async {},
                onTogglePlayback: () async => toggled = true,
                onNavigate: (_) async => navigated = true,
                onSubmit: () async {},
                onSaveReview: () async {},
                onStartRecording: () async {},
                onStopRecording: () async {},
                onCancelRecording: () async {},
                onOpenMicrophoneSettings: () async {},
                onPlayReference: () async {},
                onPlayRecording: () async {},
                onPlayAba: () async {},
                onDeleteRecording: () async {},
                onShadowingRateChanged: (_) async {},
                onShadowingStepChanged: (_) async {},
                onClose: () async {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byTooltip('Previous sentence'), findsNothing);
    expect(find.byTooltip('Next sentence'), findsNothing);
    expect(find.text('Sentence 9 of 20'), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(toggled, isTrue);
    expect(navigated, isFalse);
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
