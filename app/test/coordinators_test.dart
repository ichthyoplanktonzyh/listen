import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/playback_actions_coordinator.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';

void main() {
  group('PlaybackActionsCoordinator', () {
    PlaybackActionsCoordinator build({
      PlayerController? player,
      SubtitleController? subtitle,
    }) {
      final coordinator = PlaybackActionsCoordinator(
        adapter: DesktopPlayerAdapter(),
        player: player ?? PlayerController(),
        subtitle: subtitle ?? SubtitleController(),
      );
      coordinator.bind(
        getApi: () => null,
        isMounted: () => true,
        reloadLearningEntries: () async {},
      );
      return coordinator;
    }

    test('mediaTime shifts by primary offset and clamps at zero', () {
      final subtitle = SubtitleController();
      final coordinator = build(subtitle: subtitle);
      subtitle.setPrimarySubtitleOffset(const Duration(milliseconds: 250));
      expect(
        coordinator.mediaTime(const Duration(seconds: 1)),
        const Duration(milliseconds: 1250),
      );
      subtitle.setPrimarySubtitleOffset(const Duration(seconds: -2));
      expect(coordinator.mediaTime(const Duration(seconds: 1)), Duration.zero);
    });

    test('mediaTimeMs mirrors mediaTime in milliseconds', () {
      final subtitle = SubtitleController();
      final coordinator = build(subtitle: subtitle);
      subtitle.setPrimarySubtitleOffset(const Duration(milliseconds: 250));
      expect(coordinator.mediaTimeMs(const Duration(seconds: 1)), 1250);
    });

    test('practice-chunk helpers return empty without a current cue', () {
      final coordinator = build();
      expect(coordinator.currentPracticeChunk(), isNull);
      expect(coordinator.currentPracticeChunks(), isEmpty);
    });

    test('loopRange ignores empty or inverted ranges', () async {
      final player = PlayerController();
      final coordinator = build(player: player);
      await coordinator.loopRange(500, 500, 'noop');
      await coordinator.loopRange(900, 100, 'noop');
      expect(player.sourceLoopStart, isNull);
      expect(player.sourceLoopEnd, isNull);
    });

    test(
      'chunk navigation returns null without a current cue or partition',
      () {
        final subtitle = SubtitleController();
        final coordinator = build(subtitle: subtitle);
        expect(coordinator.currentChunkRef(), isNull);
        final cue = Cue(
          id: 'cue-1',
          index: 0,
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'hello',
          tokens: const [],
        );
        expect(coordinator.chunkRefAt(cue, 0), isNull);
      },
    );

    test('occurrence resolution reports an unavailable core', () async {
      final player = PlayerController();
      final coordinator = build(player: player);
      final result = await coordinator.resolveOccurrenceMedia({
        'media_fingerprint_snapshot': 'other',
        'start_ms_snapshot': 0,
        'end_ms_snapshot': 100,
      });
      expect(result, isA<UnresolvedOccurrenceMedia>());
      expect(
        (result as UnresolvedOccurrenceMedia).failure,
        OccurrenceMediaResolutionFailure.coreUnavailable,
      );
    });
  });

  group('ResourceActionsCoordinator', () {
    test('loadSubtitleResources without an api clears resources', () async {
      final subtitle = SubtitleController();
      final player = PlayerController();
      final coordinator = ResourceActionsCoordinator(
        player: player,
        subtitle: subtitle,
        speechEnhancement: SpeechEnhancementWorkflowController(),
      );
      coordinator.bind(
        getApi: () => null,
        isMounted: () => true,
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
      await coordinator.loadSubtitleResources();
      expect(subtitle.subtitleResources, isEmpty);
      expect(subtitle.subtitleResourceCapabilities, isEmpty);
      // The user-triggered refresh path (updateStatus: true) reports the
      // unavailable state instead of silently clearing the panel.
      expect(player.status, 'statusOpenMediaAndCoreFirst');

      player.setStatus('');
      await coordinator.loadSubtitleResources(updateStatus: false);
      // Internal reloads stay silent by design.
      expect(player.status, '');
    });

    test('row actions without an api report the missing core', () async {
      final player = PlayerController();
      final coordinator = ResourceActionsCoordinator(
        player: player,
        subtitle: SubtitleController(),
        speechEnhancement: SpeechEnhancementWorkflowController(),
      );
      coordinator.bind(
        getApi: () => null,
        isMounted: () => true,
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
      final track = SubtitleTrack(
        id: 'track-1',
        mediaId: 'media-1',
        source: 'import',
        cues: const [],
      );
      await coordinator.archiveSubtitleResource(track);
      expect(player.status, 'statusConnectLocalCoreFirst');
    });

    test(
      'activateSubtitleResource routes through the primary-track hook',
      () async {
        SubtitleTrack? activated;
        String? statusUsed;
        final coordinator = ResourceActionsCoordinator(
          player: PlayerController(),
          subtitle: SubtitleController(),
          speechEnhancement: SpeechEnhancementWorkflowController(),
        );
        coordinator.bind(
          getApi: () => null,
          isMounted: () => true,
          reloadSpeechEnhancements: (_) async {},
          activatePrimaryTrack: (track, {required nextStatus}) async {
            activated = track;
            statusUsed = nextStatus;
          },
          reloadLearningEntries: () async {},
        );
        final track = SubtitleTrack(
          id: 'track-1',
          mediaId: 'media-1',
          source: 'import',
          cues: const [],
        );
        await coordinator.activateSubtitleResource(track);
        expect(activated?.id, 'track-1');
        expect(statusUsed, 'Activated subtitle resource');
      },
    );
  });
}
