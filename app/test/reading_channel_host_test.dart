import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/reading_channel_coordinator.dart';
import 'package:llplayer_next/controllers/reading_controller.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_actions_coordinator.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/channels/reading_channel.dart';
import 'package:llplayer_next/widgets/panels/listening_check_panel.dart';
import 'package:llplayer_next/widgets/panels/reading_diff_panel.dart';
import 'package:llplayer_next/widgets/panels/reading_task_studio.dart';
import 'package:llplayer_next/widgets/panels/reading_view.dart';
import 'package:llplayer_next/widgets/panels/reading_word_inspector.dart';

Cue _cue(int index, String text, {required int startMs, required int endMs}) =>
    Cue(
      id: 'cue-$index',
      index: index,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
      tokens: [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: text.split(' ').first,
          normalized: text.split(' ').first.toLowerCase(),
        ),
      ],
    );

SubtitleTrack _track() => SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  cues: [
    _cue(0, 'First paragraph here.', startMs: 0, endMs: 2000),
    _cue(1, 'Second paragraph text.', startMs: 30000, endMs: 32000),
  ],
);

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
    coordinator.bind(
      getApi: () => api,
      isMounted: () => true,
      openSlicePlayback: (_) async {},
      openWord: (_, _) async {},
    );
    reading.open(_track());
  }

  final api = _api();
  final subtitle = SubtitleController();
  final player = PlayerController();
  final reading = ReadingController();
  final readingTask = ReadingTaskController();
  final readingDiff = ReadingDiffController();
  final settings = SettingsController();
  final learning = LearningController();
  final workflow = LearningWorkflowController();

  late final vocabulary = VocabularyActionsCoordinator(
    workflow: workflow,
    learning: learning,
    subtitle: subtitle,
    settings: settings,
    player: player,
  );

  late final coordinator = ReadingChannelCoordinator(
    adapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
    settings: settings,
    reading: reading,
    readingTask: readingTask,
    readingDiff: readingDiff,
  );

  Widget get widget => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ReadingChannelHost(
        api: api,
        readingChannel: coordinator,
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
    ),
  );

  /// Task/diff loads are fired-and-forgotten by design; the caller pumps the
  /// fake clock past them so nothing lands on a disposed controller.
  void dispose() {
    coordinator.dispose();
    learning.dispose();
    subtitle.dispose();
    player.dispose();
    reading.dispose();
    readingTask.dispose();
    readingDiff.dispose();
    settings.dispose();
  }
}

void main() {
  testWidgets('reader is the resting surface of the reading channel', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.widget);
    expect(find.byType(ReadingView), findsOneWidget);
    expect(find.byType(ReadingTaskStudio), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    harness.dispose();
  });

  testWidgets('word inspector opens beside the reader', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.widget);
    expect(find.byType(ReadingWordInspector), findsNothing);
    await harness.coordinator.openWord(
      harness.subtitle.primaryTrack!.cues.first.tokens.first,
      harness.subtitle.primaryTrack!.cues.first,
    );
    await tester.pump();
    expect(find.byType(ReadingWordInspector), findsOneWidget);
    harness.coordinator.closeWordInspector();
    await tester.pump();
    expect(find.byType(ReadingWordInspector), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    harness.dispose();
  });

  testWidgets('diff card replaces the reader and yields to the retell panel', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.widget);
    await harness.coordinator.openDiff(harness.reading.state.paragraphs.first);
    await tester.pump();
    expect(find.byType(ReadingDiffPanel), findsOneWidget);
    expect(find.byType(ReadingView), findsNothing);

    // The card column was capped at 760 — twenty pixels off the reading
    // column's 780 for no reason anyone recorded, and the pair of outcome
    // cards below it insetted 18 rather than a card's 16.
    final caps = tester
        .widgetList<ConstrainedBox>(
          find.descendant(
            of: find.byType(ReadingDiffPanel),
            matching: find.byType(ConstrainedBox),
          ),
        )
        .map((box) => box.constraints.maxWidth);
    expect(caps, contains(ListenBreakpoints.contentColumnMax));
    expect(caps, isNot(contains(760.0)));
    // Both outcome cards, and nothing left at the old 18. (The other insets in
    // here belong to `Card` and `OutlinedButton` internals.)
    final cardInsets = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(Card),
            matching: find.byType(Padding),
          ),
        )
        .map((padding) => padding.padding)
        .toList();
    expect(
      cardInsets.where((inset) => inset == ListenPadding.card),
      hasLength(2),
    );
    expect(cardInsets, isNot(contains(const EdgeInsets.all(18))));

    final source = harness.coordinator.diffSource!;
    harness.coordinator.closeDiff();
    harness.coordinator.openListeningCheck(
      source,
      fallbackTemplatePoints: const [],
    );
    await tester.pump();
    expect(find.byType(ListeningCheckPanel), findsOneWidget);
    expect(find.byType(ReadingDiffPanel), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    harness.dispose();
  });

  testWidgets('task studio outranks every other reading surface', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.widget);
    final paragraph = harness.reading.state.paragraphs.first;
    await harness.coordinator.openDiff(paragraph);
    await harness.coordinator.openTask(paragraph, templatePoints: const []);
    await tester.pump();
    expect(find.byType(ReadingTaskStudio), findsOneWidget);
    expect(find.byType(ReadingDiffPanel), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    harness.dispose();
  });
}
