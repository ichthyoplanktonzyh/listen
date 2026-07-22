import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/content_channel_coordinator.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/reading_channel_coordinator.dart';
import 'package:llplayer_next/controllers/reading_controller.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/speaking_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speaking_channel_coordinator.dart';
import 'package:llplayer_next/controllers/speaking_task_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_actions_coordinator.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/controllers/writing_channel_coordinator.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/content_channel.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/channels/reading_channel.dart';
import 'package:llplayer_next/widgets/channels/speaking_channel.dart';
import 'package:llplayer_next/widgets/channels/writing_channel.dart';
import 'package:llplayer_next/widgets/layout/content_channel_switcher.dart';
import 'package:llplayer_next/widgets/layout/media_workbench.dart';

Cue _cue(int index, String text, {required int startMs, required int endMs}) =>
    Cue(
      id: 'cue-$index',
      index: index,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
      tokens: [
        for (final (position, word) in text.split(' ').indexed)
          SubtitleToken(
            index: position,
            kind: 'word',
            text: word,
            normalized: word.toLowerCase().replaceAll(RegExp('[^a-z]'), ''),
          ),
      ],
    );

/// One paragraph spanning 20 seconds — inside the 10–60s window the speaking
/// channel requires, and enough sentences for paragraph derivation.
SubtitleTrack _track() => SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  cues: [
    _cue(0, 'A quake struck the island.', startMs: 0, endMs: 4000),
    _cue(1, 'Rescue teams arrived by noon.', startMs: 4500, endMs: 9000),
    _cue(2, 'Power was restored that night.', startMs: 9500, endMs: 14000),
    _cue(3, 'The mayor promised an inquiry.', startMs: 14500, endMs: 20000),
  ],
);

/// Answers the handful of endpoints the four channels touch while opening.
/// Everything else 404s, which every channel treats as "no saved state".
LocalApi _api() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async {
    if (method == 'GET' && path.startsWith('/v1/learner/profile')) {
      return (statusCode: 200, body: jsonEncode({'l1_language': 'zh'}));
    }
    return (statusCode: 404, body: '{"code":"not_found"}');
  },
);

class _Harness {
  _Harness() {
    subtitle.setPrimaryTrack(_track());
    readingChannel.bind(
      getApi: () => api,
      isMounted: () => true,
      openSlicePlayback: (_) async {},
      openWord: (_, _) async {},
    );
    writingChannel.bind(
      getApi: () => api,
      isMounted: () => true,
      openSlicePlayback: (_) async {},
      closeOtherChannels: () async {
        speakingChannel.closeL1Check();
        if (speakingActions.isOpen) await speakingActions.close(api);
        await readingChannel.close();
      },
    );
    speakingChannel.bind(
      getApi: () => api,
      isMounted: () => true,
      askPersonalExpressionAssessment: () async => null,
      onReturnToReview: () {},
      onReturnToPersonalExpression: () {},
    );
    channels.bind(
      getApi: () => api,
      speakingAvailable: () => true,
      openSpeaking: (service) async {
        speakingEntryEvents.add('open-speaking-choice');
        await speakingActions.openRetelling(
          service,
          fixedRubricPoints: const [],
          closeReading: readingChannel.close,
        );
      },
      openWriting: () => writingChannel.openTask(
        writingChannel.kind,
        promptSnapshot: 'prompt',
        fixedRubricPoints: const [],
      ),
    );
  }

  final api = _api();
  final adapter = DesktopPlayerAdapter();
  final subtitle = SubtitleController();
  final player = PlayerController();
  final settings = SettingsController();
  final learning = LearningController();
  final workflow = LearningWorkflowController();
  final slicePlayer = SlicePlayerController();
  final auxiliaryAudio = AuxiliaryAudioController();
  final reading = ReadingController();
  final readingTask = ReadingTaskController();
  final readingDiff = ReadingDiffController();
  final speakingTask = SpeakingTaskController();
  final writingTask = WritingTaskController();
  final List<String> speakingEntryEvents = [];

  late final vocabulary = VocabularyActionsCoordinator(
    workflow: workflow,
    learning: learning,
    subtitle: subtitle,
    settings: settings,
    player: player,
  );

  late final readingChannel = ReadingChannelCoordinator(
    adapter: adapter,
    player: player,
    subtitle: subtitle,
    settings: settings,
    reading: reading,
    readingTask: readingTask,
    readingDiff: readingDiff,
  );

  late final speakingActions = SpeakingActionsCoordinator(
    task: speakingTask,
    player: player,
    subtitle: subtitle,
    settings: settings,
    slicePlayer: slicePlayer,
    adapter: adapter,
    recordingAdapter: DesktopPlayerAdapter(),
    stopAuxiliaryAudio: () async {
      speakingEntryEvents.add('audio-focus');
    },
  );

  late final speakingChannel = SpeakingChannelCoordinator(
    actions: speakingActions,
    task: speakingTask,
    readingTask: readingTask,
    learning: learning,
    player: player,
  );

  late final writingChannel = WritingChannelCoordinator(
    adapter: adapter,
    recordingAdapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
    settings: settings,
    slicePlayer: slicePlayer,
    auxiliaryAudio: auxiliaryAudio,
    task: writingTask,
  );

  late final channels = ContentChannelCoordinator(
    reading: readingChannel,
    speaking: speakingChannel,
    speakingActions: speakingActions,
    writing: writingChannel,
  );

  /// Mirrors the composition root's wiring: one `ListenableBuilder` on the
  /// selection handle, `selectedChannel`/`immersiveStage` both derived from
  /// the coordinator.
  Widget get widget => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ListenableBuilder(
        listenable: channels.selection,
        builder: (context, _) => MediaWorkbench(
          mediaTitle: 'clip.mp4',
          playerStage: const ColoredBox(color: Colors.black),
          learningPanel: const ColoredBox(color: Colors.white),
          mediaFraction: 0.42,
          onMediaFractionChanged: (_) {},
          selectedChannel: channels.selected,
          channelAvailability: const {
            ContentChannel.listening: ContentChannelAvailability.available(),
            ContentChannel.reading: ContentChannelAvailability.available(),
            ContentChannel.speaking: ContentChannelAvailability.available(),
            ContentChannel.writing: ContentChannelAvailability.available(),
          },
          onChannelSelected: (channel) => channels.select(channel),
          immersiveStage: switch (channels.selected) {
            ContentChannel.writing => WritingChannelHost(
              api: api,
              writingChannel: writingChannel,
              writingTaskController: writingTask,
            ),
            ContentChannel.speaking => SpeakingChannelHost(
              api: api,
              speakingChannel: speakingChannel,
              speakingActions: speakingActions,
              speakingTaskController: speakingTask,
              readingTaskController: readingTask,
            ),
            ContentChannel.reading => ReadingChannelHost(
              api: api,
              readingChannel: readingChannel,
              readingController: reading,
              readingTaskController: readingTask,
              readingDiffController: readingDiff,
              learningController: learning,
              settingsController: settings,
              subtitleController: subtitle,
              playerController: player,
              vocabularyActions: vocabulary,
              onSaveSentencePattern: (_) async {},
              onOpenSlicePlayback: (_) async {},
              onRecordReadingMark: (_) async {},
              onOpenListeningDictionary: (_) async {},
              onPlayPronunciationAudio: (_) {},
              onCorrectLemma: () {},
            ),
            ContentChannel.listening => null,
          },
        ),
      ),
    ),
  );

  void dispose() {
    readingChannel.dispose();
    writingChannel.dispose();
    speakingChannel.dispose();
    speakingActions.dispose();
    subtitle.dispose();
    player.dispose();
    settings.dispose();
    learning.dispose();
    slicePlayer.dispose();
    auxiliaryAudio.dispose();
    reading.dispose();
    readingTask.dispose();
    readingDiff.dispose();
    speakingTask.dispose();
    writingTask.dispose();
  }
}

Future<void> _tapChannel(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('content-channel-$name')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the four channels hand the stage over one at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = _Harness();
    await tester.pumpWidget(harness.widget);

    // Listening is the resting state: nothing owns the immersive stage.
    expect(harness.channels.selected, ContentChannel.listening);
    expect(find.byType(ReadingChannelHost), findsNothing);

    await _tapChannel(tester, 'reading');
    expect(harness.channels.selected, ContentChannel.reading);
    expect(find.byType(ReadingChannelHost), findsOneWidget);

    await _tapChannel(tester, 'writing');
    expect(harness.channels.selected, ContentChannel.writing);
    expect(find.byType(WritingChannelHost), findsOneWidget);
    // Reading was torn down on the way in, not left open underneath.
    expect(harness.readingChannel.isOpen, isFalse);
    expect(find.byType(ReadingChannelHost), findsNothing);

    await _tapChannel(tester, 'speaking');
    expect(
      harness.speakingEntryEvents.take(2),
      ['audio-focus', 'open-speaking-choice'],
      reason: 'entering Speak must stop playback before opening its chooser',
    );
    expect(harness.channels.selected, ContentChannel.speaking);
    expect(find.byType(SpeakingChannelHost), findsOneWidget);
    expect(harness.writingChannel.isOpen, isFalse);

    await _tapChannel(tester, 'listening');
    expect(harness.channels.selected, ContentChannel.listening);
    expect(harness.speakingActions.isOpen, isFalse);
    expect(find.byType(SpeakingChannelHost), findsNothing);
    expect(find.byType(ReadingChannelHost), findsNothing);
    expect(find.byType(WritingChannelHost), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    harness.dispose();
  });
}
