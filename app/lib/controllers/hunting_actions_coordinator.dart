import '../services/api_service.dart';
import 'extensive_listening_controller.dart';
import 'hunting_session_controller.dart';
import 'player_controller.dart';
import 'subtitle_controller.dart';

/// Owns the session-level hunting-mode actions: toggling hunting on/off,
/// rebuilding the personal corpus index, and recording a hunting check answer.
/// Extracted verbatim from `_PlayerScreenState` (main.dart decomposition);
/// context-free, driving everything through the injected controllers and
/// callbacks so it stays testable in isolation.
class HuntingActionsCoordinator {
  HuntingActionsCoordinator({
    required this.huntingSession,
    required this.player,
    required this.extensiveListening,
    required this.subtitle,
  });

  final HuntingSessionController huntingSession;
  final PlayerController player;
  final ExtensiveListeningController extensiveListening;
  final SubtitleController subtitle;

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  late String Function(String key) text;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required String Function(String key) text,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.text = text;
  }

  Future<void> toggleHuntingMode() async {
    if (huntingSession.state.enabled) {
      huntingSession.stop();
      if (isMounted()) player.setStatus(text('huntingStopped'));
      return;
    }
    final service = getApi();
    final mediaId = player.mediaId;
    if (service == null || mediaId == null) return;
    if (!extensiveListening.active) {
      final started = await extensiveListening.startSession(
        api: service,
        mediaId: mediaId,
        trackId: subtitle.primaryTrack?.id,
      );
      if (!started) return;
    }
    final session = extensiveListening.session;
    if (session == null) return;
    final loaded = await huntingSession.start(
      api: service,
      sessionId: session.id,
      mediaId: mediaId,
      trackId: subtitle.primaryTrack?.id,
    );
    if (!isMounted() || !loaded) return;
    final state = huntingSession.state;
    player.setStatus(
      !state.indexed
          ? text('huntingIndexNeeded')
          : text(
              'huntingStarted',
            ).replaceAll('{count}', '${state.occurrences.length}'),
    );
  }

  Future<void> reindexHuntingCorpus() async {
    final service = getApi();
    if (service == null) return;
    try {
      final count = await service.reindexCorpus();
      await huntingSession.reload(service);
      if (isMounted()) {
        player.setStatus(
          text('dictionaryReindexDone').replaceAll('{count}', '$count'),
        );
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('dictionaryReindexFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> answerHuntingCheck(String answer) async {
    final service = getApi();
    if (service == null) return;
    final saved = await huntingSession.answer(service, answer);
    if (saved && isMounted()) {
      player.setStatus(text('huntingAnswerSaved'));
    }
  }
}
