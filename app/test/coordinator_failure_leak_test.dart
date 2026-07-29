import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/hunting_actions_coordinator.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';

/// The status line, as the coordinator family fills it.
///
/// Every case here drives a *real* backend failure through the *real*
/// transport — `LocalApi` throws `HttpException(body, uri: …)` on a non-2xx,
/// and the fake is served from `127.0.0.1:62645`, the address the field
/// actually used — so the assertion covers `describeApiFailure` and the
/// exception's own `toString` (which is what appends `uri = …`), not just a
/// hand-built string.
///
/// That is the whole point. The lesson from #61's first round is that a
/// blocklist assertion run against the wrong scenario stays green while the
/// leak is wide open: a green error path is worse than no coverage. So each
/// test names the request it fails and the status line it produces.
void main() {
  /// The body the field actually reported, verbatim.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  /// Everything the exchange carried that a status line is not a place for.
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
  ];

  void expectNoLeak(String text, {required String from}) {
    for (final leak in leaks) {
      expect(
        text,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; $from is not a place to print it.',
      );
    }
  }

  /// Real English copy, not a `(key) => key` stub: the assertion has to run
  /// over the sentence a learner reads.
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

  ({
    ResourceActionsCoordinator resources,
    PlayerController player,
    SubtitleController subtitle,
  })
  wireResources(LocalApi service) {
    final player = PlayerController()
      ..setMedia(
        id: 'media-1',
        path: '/tmp/a.mp4',
        title: 'a',
        fingerprint: 'fp',
      );
    final subtitle = SubtitleController();
    final resources =
        ResourceActionsCoordinator(
          player: player,
          subtitle: subtitle,
          speechEnhancement: SpeechEnhancementWorkflowController(),
        )..bind(
          getApi: () => service,
          isMounted: () => true,
          text: enText,
          reloadSpeechEnhancements: (_) async {},
          activatePrimaryTrack: (_, {required nextStatus}) async {},
          reloadLearningEntries: () async {},
        );
    return (resources: resources, player: player, subtitle: subtitle);
  }

  test('the subtitle-resource list failing to load says so, and keeps the '
      'exception as detail rather than as prose', () async {
    // GET /v1/media/media-1/subtitles → 500 with the envelope.
    final w = wireResources(
      api(
        fail: (method, path) => path.endsWith('/subtitles')
            ? (statusCode: 500, body: envelope)
            : null,
      ),
    );

    await w.resources.loadSubtitleResources();

    expect(w.player.status, enText('statusSubtitleResourcesUnavailable'));
    expect(w.player.statusIsError, isTrue);
    expectNoLeak(w.player.status, from: 'the status line');
    // Not dropped on the floor either — the reference id a bug report needs
    // survives, off screen.
    expect(w.player.statusFailure?.correlationId, 'api-853');
    expect(w.player.statusFailure?.code, 'validation_error');
  });

  test('one capability loader failing leaves a sentence on the track, not '
      'three exceptions joined by semicolons', () async {
    // The track list loads; its word-timing, phone and chunk loaders all 404.
    final w = wireResources(
      api(
        fail: (method, path) => path.contains('/v1/subtitles/')
            ? (statusCode: 404, body: envelope)
            : null,
        ok: {'/subtitles': '[{"id":"track-1","sentences":[]}]'},
      ),
    );

    await w.resources.loadSubtitleResources();

    final capabilities = w.subtitle.subtitleResourceCapabilities['track-1'];
    expect(
      capabilities?.error,
      enText('statusTrackResourcesPartlyUnavailable'),
    );
    expectNoLeak(capabilities!.error!, from: 'the capability tooltip');
  });

  test(
    'archiving a subtitle resource that the backend rejects says so',
    () async {
      final w = wireResources(
        api(
          fail: (method, path) => path.contains('/archive')
              ? (statusCode: 409, body: envelope)
              : null,
        ),
      );

      await w.resources.archiveSubtitleResource(
        const SubtitleTrack(id: 'track-1', cues: []),
      );

      expect(w.player.status, enText('statusSubtitleArchiveFailed'));
      expectNoLeak(w.player.status, from: 'the status line');
      expect(w.player.statusFailure?.correlationId, 'api-853');
    },
  );

  test('a timeline lifecycle action that fails reports its own failure '
      'sentence, not the sentence plus the exception', () async {
    final w = wireResources(
      api(
        fail: (method, path) => path.contains('/chunk-timelines')
            ? (statusCode: 500, body: envelope)
            : null,
      ),
    );
    w.subtitle.setPrimaryTrack(const SubtitleTrack(id: 'track-1', cues: []));

    await w.resources.generateChunkTimeline();

    // `_runTimelineAction` used to build `'$failurePrefix: $error'`; the prefix
    // is now the whole message. (The prefixes are still hard-coded English —
    // that is #7's slice, not this one.)
    expect(w.player.status, 'ChunkTimeline generation failed');
    expectNoLeak(w.player.status, from: 'the status line');
    expect(w.player.statusFailure?.correlationId, 'api-853');
  });

  test('a corpus reindex that fails no longer substitutes the exception into '
      'its own {error} placeholder', () async {
    final player = PlayerController();
    final hunting = HuntingSessionController();
    final extensive = ExtensiveListeningController();
    addTearDown(hunting.dispose);
    addTearDown(extensive.dispose);
    final coordinator =
        HuntingActionsCoordinator(
          huntingSession: hunting,
          player: player,
          extensiveListening: extensive,
          subtitle: SubtitleController(),
        )..bind(
          getApi: () => api(
            fail: (method, path) => path.contains('reindex')
                ? (statusCode: 500, body: envelope)
                : null,
          ),
          isMounted: () => true,
          text: enText,
        );

    await coordinator.reindexHuntingCorpus();

    expect(player.status, enText('dictionaryReindexFailed'));
    expectNoLeak(player.status, from: 'the status line');
    expect(player.statusFailure?.correlationId, 'api-853');
  });
}
