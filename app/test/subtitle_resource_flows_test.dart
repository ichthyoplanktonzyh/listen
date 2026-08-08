import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/screens/subtitle_resources_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/flows/subtitle_resource_flows.dart';

const _track = SubtitleTrack(id: 'track-1', cues: []);

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

ResourceActionsCoordinator _resourceActions(LocalApi? Function() getApi) =>
    ResourceActionsCoordinator(
      player: PlayerController(),
      subtitle: SubtitleController(),
      speechEnhancement: SpeechEnhancementWorkflowController(),
      repository: LocalResourceRepository(getApi),
    )..bind(
      isMounted: () => true,
      reloadSpeechEnhancements: (_) async {},
      activatePrimaryTrack: (_, {required nextStatus}) async {},
      reloadLearningEntries: () async {},
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
  testWidgets('resources without current media hide package journey', (
    tester,
  ) async {
    final player = PlayerController();
    expect(player.mediaId, isNull);
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SubtitleResourcesScreen(
          playerController: player,
          subtitleController: SubtitleController(),
          onImportSubtitle: () async {},
          onImportLLTimeline: () async {},
          onRefreshResources: () async {},
          onActivateSubtitle: (_) async {},
          onArchiveSubtitle: (_) async {},
          onRestoreSubtitle: (_) async {},
          onDeleteSubtitle: (_) async {},
          onExportSubtitle: (_) async {},
          onLanguageChanged: (_, _) async {},
          availableLanguages: const [],
          onExportLLTimeline: (_) async {},
          onActivateWordTimeline: (_) async {},
          onManualReviewTimeline: () async {},
          onActivatePhoneTimeline: (_) async {},
          onArchivePhoneTimeline: (_) async {},
          onDeletePhoneTimeline: (_) async {},
          onGenerateChunkTimeline: () async {},
          onActivateChunkTimeline: (_) async {},
          onArchiveChunkTimeline: (_) async {},
          onDeleteChunkTimeline: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('open-content-packages')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete flow cancel leaves the resource untouched', (
    tester,
  ) async {
    final calls = <String>[];
    final api = _fakeApi((method, path, body) {
      calls.add('$method $path');
      return (statusCode: 200, body: '{}');
    });
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => deleteSubtitleResourceFlow(
          context: context,
          resourceActions: _resourceActions(() => api),
          track: _track,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
  });

  testWidgets('delete flow confirm issues the DELETE request', (tester) async {
    final calls = <String>[];
    final api = _fakeApi((method, path, body) {
      calls.add('$method $path');
      return (statusCode: 200, body: method == 'GET' ? '[]' : '{}');
    });
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => deleteSubtitleResourceFlow(
          context: context,
          resourceActions: _resourceActions(() => api),
          track: _track,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete resource'));
    await tester.pumpAndSettle();

    expect(calls, contains('DELETE /v1/subtitles/track-1'));
  });

  testWidgets('export flow with a null api reports the missing core', (
    tester,
  ) async {
    final player = PlayerController();
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => exportSubtitleResourceFlow(
          context: context,
          playerController: player,
          resourceActions: _resourceActions(() => null),
          track: _track,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Honest refusal (CONTEXT.md Unavailable State): no dialog, but the row
    // action reports why instead of dying silently.
    expect(find.byType(SimpleDialog), findsNothing);
    expect(player.status, 'Connect the local core first');
  });

  testWidgets('export flow offers both formats and honors dismissal', (
    tester,
  ) async {
    final calls = <String>[];
    final api = _fakeApi((method, path, body) {
      calls.add('$method $path');
      return (statusCode: 200, body: '{}');
    });
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) => exportSubtitleResourceFlow(
          context: context,
          playerController: PlayerController(),
          resourceActions: _resourceActions(() => api),
          track: _track,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('.srt'), findsOneWidget);
    expect(find.text('.lltimeline.json'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('cold-start flow without a factory reports missing core', (
    tester,
  ) async {
    final player = PlayerController();
    await tester.pumpWidget(
      _Harness(
        onPressed: (context) async => openColdStartMarkingFlow(
          context: context,
          createViewModel: null,
          playerController: player,
          subtitleController: SubtitleController(),
          resourceActions: _resourceActions(() => null),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(player.status, 'Connect the local core first');
  });
}
