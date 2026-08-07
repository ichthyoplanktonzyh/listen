import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/widgets/panels/sentence_analysis_window.dart';

const _sentence = 'Hundreds of hungry pelicans are flocking.';

Cue _cue() => const Cue(
  id: 'cue-1',
  index: 0,
  start: Duration.zero,
  end: Duration(seconds: 2),
  text: _sentence,
  tokens: [],
);

({Widget widget, LearningController learning, int Function() diagnosisCalls, int Function() closes})
_harness({bool withCurrentCue = true}) {
  final subtitle = SubtitleController();
  if (withCurrentCue) {
    final cue = _cue();
    subtitle
      ..setPrimaryTrack(
        SubtitleTrack(id: 'track-1', cues: [cue], source: 'fixture'),
      )
      ..setCurrentPrimaryCue(cue);
  }
  final learning = LearningController();
  final player = PlayerController();
  final playback = PlaybackActionsCoordinator(
    adapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
  );
  var diagnosisCalls = 0;
  var closes = 0;

  final widget = MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            SentenceAnalysisWindow(
              subtitleController: subtitle,
              learningController: learning,
              settingsController: SettingsController(),
              playbackActions: playback,
              onRequestDiagnosis: () async {
                diagnosisCalls += 1;
              },
              onClose: () => closes += 1,
            ),
          ],
        ),
      ),
    ),
  );

  return (
    widget: widget,
    learning: learning,
    diagnosisCalls: () => diagnosisCalls,
    closes: () => closes,
  );
}

void main() {
  testWidgets('opens on the text layer and marks grammar/collocation unavailable', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // The current sentence heads the text layer, and the layers that need an
    // AI contract we do not have say so plainly instead of faking a result.
    expect(find.text(_sentence), findsOneWidget);
    expect(find.byKey(const Key('analysis-text-unavailable')), findsOneWidget);
    // The voice layer's diagnosis card is not built until the reader asks for
    // it, so nothing was fetched by merely opening the window.
    expect(h.diagnosisCalls(), 0);
  });

  testWidgets('switching to the voice layer fetches the diagnosis and shows pending', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('语音'));
    await tester.pumpAndSettle();

    expect(h.diagnosisCalls(), 1);
    expect(
      find.byKey(const Key('transcript-analysis-pending')),
      findsOneWidget,
    );
  });

  testWidgets('the close button asks the host to close', (tester) async {
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('analysis-window-close')));
    expect(h.closes(), 1);
  });
}
