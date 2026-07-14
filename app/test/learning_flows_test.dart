import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
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
          api: _fakeApi((m, p, b) => (statusCode: 200, body: '{}')),
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
      return (statusCode: 200, body: '{}');
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
          api: api,
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

  testWidgets('learning-resources flow with a null api never navigates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) =>
            openLearningResourcesFlow(context: context, api: null),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget);
  });
}
