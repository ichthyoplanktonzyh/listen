import '../data/repositories/hunting_repository.dart';
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
  factory HuntingActionsCoordinator({
    required HuntingSessionController huntingSession,
    required PlayerController player,
    required ExtensiveListeningController extensiveListening,
    required SubtitleController subtitle,
    required HuntingRepository repository,
  }) => HuntingActionsCoordinator._(
    huntingSession: huntingSession,
    player: player,
    extensiveListening: extensiveListening,
    subtitle: subtitle,
    repository: repository,
  );

  HuntingActionsCoordinator._({
    required this.huntingSession,
    required this.player,
    required this.extensiveListening,
    required this.subtitle,
    required this._repository,
  });

  final HuntingSessionController huntingSession;
  final PlayerController player;
  final ExtensiveListeningController extensiveListening;
  final SubtitleController subtitle;
  final HuntingRepository _repository;

  late bool Function() isMounted;
  late String Function(String key) text;

  void bind({
    required bool Function() isMounted,
    required String Function(String key) text,
  }) {
    this.isMounted = isMounted;
    this.text = text;
  }

  Future<void> toggleHuntingMode() async {
    if (huntingSession.state.enabled) {
      huntingSession.stop();
      if (isMounted()) player.setStatus(text('huntingStopped'));
      return;
    }
    final mediaId = player.mediaId;
    if (!_repository.isAvailable ||
        !extensiveListening.repositoryAvailable ||
        mediaId == null) {
      // Unavailable State (CONTEXT.md): the toggle is user-triggered, so name
      // the cause and the recovery action instead of silently doing nothing.
      player.setStatus(text('statusOpenMediaAndCoreFirst'));
      return;
    }
    if (!extensiveListening.active) {
      final started = await extensiveListening.startSession(
        mediaId: mediaId,
        trackId: subtitle.primaryTrack?.id,
      );
      if (!started) return;
    }
    final session = extensiveListening.session;
    if (session == null) return;
    final loaded = await huntingSession.start(
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
    if (!_repository.isAvailable) {
      player.setStatus(text('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      final count = await _repository.reindexCorpus();
      await huntingSession.reload();
      if (isMounted()) {
        player.setStatus(
          text('dictionaryReindexDone').replaceAll('{count}', '$count'),
        );
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('dictionaryReindexFailed'),
          error: true,
          failure: huntingFailureDetail(error),
        );
      }
    }
  }

  Future<void> answerHuntingCheck(String answer) async {
    if (!_repository.isAvailable) {
      player.setStatus(text('statusConnectLocalCoreFirst'));
      return;
    }
    final saved = await huntingSession.answer(answer);
    if (saved && isMounted()) {
      player.setStatus(text('huntingAnswerSaved'));
    }
  }
}
