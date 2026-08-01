import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_session_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/speech_enhancement_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/data/repositories/media_session_repository.dart';
import 'package:llplayer_next/data/repositories/manual_review_repository.dart';
import 'package:llplayer_next/data/repositories/subtitle_analysis_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/external_tools.dart';
import 'package:llplayer_next/widgets/flows/manual_review_flow.dart';
import 'package:llplayer_next/widgets/flows/media_import_flows.dart';

/// The import and review flows, driven by failures that really happen.
///
/// These sites all read `'${l.text('statusX')}: $error'` and handed the
/// result to `playerController.setStatus`, so the status line printed either a
/// whole `HttpException` (with the sidecar's loopback URI) or an external
/// tool's own error text — including the executable's path.
///
/// `openOnlineMediaFlow`'s own `statusOnlineMediaFailed` site is **not**
/// asserted here, and it is worth saying why rather than implying coverage:
/// that flow opens a modal before it reaches the call that fails, and a widget
/// test cannot both drive a modal on the fake clock and let a real subprocess
/// finish in the same await. It changed the same way the two below did, and the
/// source gate holds it; it has no scenario of its own.
///
/// Nothing here is a hand-written failure string:
///
/// - the embedded-import flow points `ExternalTools` at `/usr/bin/false`, so
///   the real `_run` really starts a real process, it really exits 1, and the
///   real `ExternalToolError` really carries
///   `'/usr/bin/false exited with status 1.'`. Offline and deterministic,
///   unlike letting a real ffprobe or yt-dlp loose;
/// - the review flow fails a real request through the real transport, served
///   from `127.0.0.1:62645` — the address the field report used — so the
///   assertion covers `describeApiFailure` and the exception's own `toString`.
void main() {
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Transport and tool detail. A status line is not a place for any of it.
  const leaks = [
    'HttpException',
    'Exception',
    'correlation_id',
    'api-853',
    '127.0.0.1',
    '62645',
    'validation_error',
    'recording metadata must not be empty',
    'uri =',
    'retryable',
    '/v1/',
    '/usr/bin/false',
    'exited with status',
    'No such file or directory',
  ];

  void expectNoLeak(String text, {required String from}) {
    for (final leak in leaks) {
      expect(
        text,
        isNot(contains(leak)),
        reason:
            '"$leak" is diagnostics; $from is not a place to print it. '
            'It said:\n$text',
      );
    }
  }

  String enText(String key) => const AppLocalizations(Locale('en')).text(key);

  LocalApi api({
    ({int statusCode, String body})? Function(String method, String path)? fail,
    Map<String, String> ok = const {},
  }) => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async {
      final failure = fail?.call(method, path);
      if (failure != null) return failure;
      for (final entry in ok.entries) {
        if (path.contains(entry.key)) {
          return (statusCode: 200, body: entry.value);
        }
      }
      return (statusCode: 200, body: '{}');
    },
  );

  /// Pumps a host and hands back a real `BuildContext` with real
  /// localizations.
  ///
  /// The flows are started but *not* awaited under the fake clock: they touch
  /// real processes, so the pending future is handed to
  /// [WidgetTester.runAsync], which runs it in the real zone.
  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    return hostContext;
  }

  testWidgets('an embedded-subtitle probe that fails says so, without quoting '
      'ffprobe', (tester) async {
    final harness = _harness(api());
    harness.player.setMedia(
      id: 'media-1',
      path: '/tmp/a.mkv',
      title: 'a',
      fingerprint: 'fp',
    );

    final context = await host(tester);
    await tester.runAsync(
      () => importEmbeddedSubtitleFlow(
        context: context,
        playerController: harness.player,
        mediaSession: harness.mediaSession,
        tools: ExternalTools(ffprobePath: '/usr/bin/false'),
        backendAvailable: true,
        isMediaPath: (_) => true,
        failureMapper: describeApiFailure,
      ),
    );

    expectNoLeak(harness.player.status, from: 'the status line');
    expect(harness.player.status, enText('statusEmbeddedImportFailed'));
    expect(harness.player.statusIsError, isTrue);
    expect(harness.player.statusFailure?.raw, contains('/usr/bin/false'));
  });

  testWidgets('a manual review whose timeline will not load says so, not the '
      'exception', (tester) async {
    // The track and its word-timeline summary read fine; the timeline itself
    // 500s. That ordering matters: an assertion on the summary call alone
    // would stay green against the leaking code, because the flow returns
    // early with "no timeline" before it ever reaches the leaking catch.
    final harness = _harness(
      api(
        fail: (method, path) =>
            path.startsWith('/v1/word-timelines/') && !path.contains('/summary')
            ? (statusCode: 500, body: envelope)
            : null,
        ok: {'/word-timelines/summary': '[$_activeSummary]'},
      ),
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/tmp/a.mkv',
      title: 'a',
      fingerprint: 'fp',
    );
    harness.subtitle.setPrimaryTrack(
      const SubtitleTrack(id: 'track-1', cues: []),
    );

    final context = await host(tester);
    final flow = openManualReviewFlow(
      context: context,
      repository: LocalManualReviewRepository(harness.api),
      adapter: harness.adapter,
      playerController: harness.player,
      subtitleController: harness.subtitle,
      resourceActions: harness.resourceActions,
      mediaSession: harness.mediaSession,
    );
    await tester.pumpAndSettle();
    await flow;

    expectNoLeak(harness.player.status, from: 'the status line');
    expect(harness.player.status, enText('statusManualReviewFailed'));
    expect(harness.player.statusIsError, isTrue);
    expect(harness.player.statusFailure?.correlationId, 'api-853');
  });
}

/// One active word-timeline summary, so the review flow gets past its
/// "no timeline" guard and reaches the request that fails.
const _activeSummary =
    '{"id":"tl-1","track_id":"track-1","media_id":"media-1",'
    '"algorithm_id":"whisperx","algorithm_version":"1","created_by":"core",'
    '"status":"active","lifecycle_stage":"active","word_count":3,'
    '"provider_ids":[],"timing_sources":[],"can_activate":false,'
    '"can_archive":true,"can_delete":true}';

({
  LocalApi api,
  DesktopPlayerAdapter adapter,
  PlayerController player,
  SubtitleController subtitle,
  ResourceActionsCoordinator resourceActions,
  MediaSessionCoordinator mediaSession,
})
_harness(LocalApi service) {
  final adapter = DesktopPlayerAdapter();
  final player = PlayerController();
  final subtitle = SubtitleController();
  final learning = LearningController();
  final settings = SettingsController();
  final speech = SpeechEnhancementWorkflowController(
    repository: LocalSpeechEnhancementRepository(() => service),
  );
  final resourceActions =
      ResourceActionsCoordinator(
        player: player,
        subtitle: subtitle,
        speechEnhancement: speech,
        repository: LocalResourceRepository(() => service),
      )..bind(
        isMounted: () => true,
        text: (key) => const AppLocalizations(Locale('en')).text(key),
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
  final mediaSession =
      MediaSessionCoordinator(
        adapter: adapter,
        player: player,
        subtitle: subtitle,
        learning: learning,
        settings: settings,
        speechEnhancement: speech,
        resourceActions: resourceActions,
        repository: LocalMediaSessionRepository(() => service),
        subtitleAnalysis: LocalSubtitleAnalysisRepository(() => service),
      )..bind(
        isMounted: () => true,
        text: (key) => const AppLocalizations(Locale('en')).text(key),
        confirmLLTimelineMismatch:
            ({
              required String resourceFingerprint,
              required String currentFingerprint,
            }) async => true,
        onMediaSwitched: () {},
        reloadLearningEntries: () async {},
        loadPhraseCandidates: (_) async {},
        generatedPrimaryStatus: (_) => 'generated',
      );
  return (
    api: service,
    adapter: adapter,
    player: player,
    subtitle: subtitle,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
  );
}
