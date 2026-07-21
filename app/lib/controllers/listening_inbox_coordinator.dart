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
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    String Function(String key)? text,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.text = text;
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
      mediaTimeMs: playbackActions.mediaTimeMs,
    );
    if (captured && isMounted()) {
      player.setStatus(_t('statusInboxMarked'));
    }
  }

  Future<void> refreshListeningInbox() async {
    await extensiveListening.refreshInbox(getApi());
  }

  Future<void> replayListeningInboxItem(ListeningInboxItem item) async {
    final start = item.playbackStartMs;
    final end = item.playbackEndMs;
    if (start == null || end == null) {
      player.setStatus(_t('statusInboxNoPlayableRange'), error: true);
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
        player.setStatus(_t('statusInboxSavedToReview'));
      case 'micro_intensive':
        await replayListeningInboxItem(processed);
        if (isMounted()) {
          player.setStatus(_t('statusInboxMicroItemCreated'));
        }
      case 'favorite':
        player.setStatus(_t('statusInboxSavedFavorite'));
      case 'dismissed':
        player.setStatus(_t('statusInboxArchived'));
      default:
        player.setStatus(_t('statusInboxProcessed'));
    }
  }
}
