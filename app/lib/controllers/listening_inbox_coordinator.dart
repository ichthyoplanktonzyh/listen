import '../models/listening.dart';
import '../services/api_service.dart';
import 'extensive_listening_controller.dart';
import 'playback_actions_coordinator.dart';
import 'player_controller.dart';
import 'subtitle_controller.dart';

/// Owns Listening Inbox capture/refresh/replay/process actions. Extracted
/// verbatim from `_PlayerScreenState` (main.dart decomposition); context-free,
/// driving everything through the injected controllers and callbacks so it
/// stays testable in isolation.
class ListeningInboxCoordinator {
  ListeningInboxCoordinator({
    required this.extensiveListening,
    required this.player,
    required this.subtitle,
    required this.playbackActions,
  });

  final ExtensiveListeningController extensiveListening;
  final PlayerController player;
  final SubtitleController subtitle;
  final PlaybackActionsCoordinator playbackActions;

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  late int Function(Duration subtitleTime) mediaTimeMs;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required int Function(Duration subtitleTime) mediaTimeMs,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.mediaTimeMs = mediaTimeMs;
  }

  Future<void> captureListeningInbox() async {
    final cue = subtitle.currentPrimaryCue;
    final captured = await extensiveListening.captureCurrentCue(
      api: getApi(),
      cue: cue,
      previousCue: subtitle.primaryCursor.previous(cue),
      nextCue: subtitle.primaryCursor.next(cue),
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id,
      mediaTimeMs: mediaTimeMs,
    );
    if (captured && isMounted()) {
      player.setStatus('Marked in Listening Inbox');
    }
  }

  Future<void> refreshListeningInbox() async {
    await extensiveListening.refreshInbox(getApi());
  }

  Future<void> replayListeningInboxItem(ListeningInboxItem item) async {
    final start = item.playbackStartMs;
    final end = item.playbackEndMs;
    if (start == null || end == null) {
      player.setStatus('No playable range for this Inbox item');
      return;
    }
    await playbackActions.loopRange(
      start,
      end,
      'Looping Listening Inbox item',
      labelKey: 'loopInbox',
    );
  }

  Future<void> processListeningInboxItem(
    ListeningInboxItem item,
    String resolution,
  ) async {
    final processed = await extensiveListening.processItem(
      getApi(),
      item,
      resolution,
    );
    if (processed == null || !isMounted()) return;
    switch (resolution) {
      case 'review_item':
        player.setStatus('Listening Inbox item saved to review');
      case 'micro_intensive':
        await replayListeningInboxItem(processed);
        if (isMounted()) {
          player.setStatus('Micro intensive item created');
        }
      case 'favorite':
        player.setStatus('Segment saved as favorite');
      case 'dismissed':
        player.setStatus('Listening Inbox item archived');
      default:
        player.setStatus('Listening Inbox item processed');
    }
  }
}
