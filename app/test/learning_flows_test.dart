import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/practice_actions_coordinator.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/lexical_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/flows/learning_flows.dart';

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

class _Harness extends StatelessWidget {
  const _Harness({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) => MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => onPressed(context),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('correct-lemma flow without a selected token is a no-op', (
    tester,
  ) async {
    final learning = LearningController();
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => correctCurrentLemmaFlow(
          context: context,
          lexicalRepository: LexicalRepository(
            _fakeApi((m, p, b) => (statusCode: 200, body: '{}')),
          ),
          playerController: PlayerController(),
          subtitleController: SubtitleController(),
          settingsController: SettingsController(),
          learningController: learning,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('correct-lemma flow saves the corrected form', (tester) async {
    final calls = <String>[];
    final api = _fakeApi((method, path, body) {
      calls.add('$method $path $body');
      return (
        statusCode: 200,
        body:
            '{"original":"ran","normalized":"run","provider":"user",'
            '"version":"v1","user_corrected":true}',
      );
    });
    final learning = LearningController()
      ..setSelectedToken(
        const SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'ran',
          normalized: 'ran',
        ),
      );
    final player = PlayerController();
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => correctCurrentLemmaFlow(
          context: context,
          lexicalRepository: LexicalRepository(api),
          playerController: player,
          subtitleController: SubtitleController(),
          settingsController: SettingsController(),
          learningController: learning,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'run');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single, contains('POST /v1/lexical-normalization/correct'));
    expect(calls.single, contains('"original":"ran"'));
    expect(calls.single, contains('"corrected":"run"'));
  });

  testWidgets(
    'learning-resources flow with a null api reports the missing core',
    (tester) async {
      final player = PlayerController();
      await tester.pumpWidget(
        _Harness(
          onPressed: (context) => openLearningResourcesFlow(
            context: context,
            repository: null,
            playerController: player,
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Honest refusal (CONTEXT.md Unavailable State): no navigation, but the
      // click reports why instead of dying silently.
      expect(find.text('go'), findsOneWidget);
      expect(player.status, 'Connect the local core first');
    },
  );

  testWidgets('vocabulary flow with a null api reports the missing core', (
    tester,
  ) async {
    final player = PlayerController();
    final subtitle = SubtitleController();
    final adapter = DesktopPlayerAdapter();
    final recordingAdapter = DesktopPlayerAdapter();
    addTearDown(adapter.dispose);
    addTearDown(recordingAdapter.dispose);
    final playback = PlaybackActionsCoordinator(
      adapter: adapter,
      player: player,
      subtitle: subtitle,
    )..bind(isMounted: () => true, reloadLearningEntries: () async {});
    final practice = PracticeController();
    final slicePlayer = SlicePlayerController();
    addTearDown(practice.dispose);
    addTearDown(slicePlayer.dispose);
    final practiceActions =
        PracticeActionsCoordinator(
          practice: practice,
          player: player,
          subtitle: subtitle,
          learning: LearningController(),
          slicePlayer: slicePlayer,
          playbackActions: playback,
          settings: SettingsController(),
          adapter: adapter,
          recordingAdapter: recordingAdapter,
        )..bind(
          isMounted: () => true,
          refreshDiagnosis: () async {},
          seekCue: (_) async {},
        );
    final hunting = HuntingController();
    final auxiliaryAudio = AuxiliaryAudioController();
    addTearDown(hunting.dispose);
    addTearDown(auxiliaryAudio.dispose);

    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => showVocabularyFlow(
          context: context,
          lexicalRepository: null,
          semanticSearchRepository: null,
          playerController: player,
          settingsController: SettingsController(),
          subtitleController: subtitle,
          playbackActions: playback,
          practiceActions: practiceActions,
          huntingController: hunting,
          auxiliaryAudio: auxiliaryAudio,
          pauseBackgroundPlayback: () async {},
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // The dead "vocabulary button" report: with the core disconnected the
    // click must surface the cause, not swallow the tap (refs #24/#45).
    expect(find.text('go'), findsOneWidget);
    expect(player.status, 'Connect the local core first');
  });

  testWidgets('review-queue flow with a null api reports the missing core', (
    tester,
  ) async {
    final player = PlayerController();

    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => openReviewQueueFlow(
          context: context,
          repository: null,
          playerController: player,
          pauseBackgroundPlayback: () async {},
          startReviewShadowing: (_) async {},
          startDelayedRetelling: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget);
    expect(player.status, 'Connect the local core first');
  });
}
