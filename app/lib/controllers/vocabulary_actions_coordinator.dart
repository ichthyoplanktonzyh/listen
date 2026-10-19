import '../models/timeline.dart';
import 'learning_controller.dart';
import 'learning_workflow_controller.dart';
import 'player_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Owns the context-free vocabulary/learning-asset data actions: loading word
/// and phrase entries and phrase candidates, opening a word into the learning
/// panel, applying status/capability/content edits, recording the current
/// source, and per-occurrence heard/not-heard observation.
///
/// Extracted verbatim from `_PlayerScreenState` (main.dart decomposition).
/// Dialog- and navigation-based vocabulary entry points remain in the State
/// because they need a BuildContext; this coordinator stays context-free and
/// drives everything through the injected controllers and callbacks.
class VocabularyActionsCoordinator {
  VocabularyActionsCoordinator({
    required this.workflow,
    required this.learning,
    required this.subtitle,
    required this.settings,
    required this.player,
  });

  final LearningWorkflowController workflow;
  final LearningController learning;
  final SubtitleController subtitle;
  final SettingsController settings;
  final PlayerController player;

  late bool Function() isMounted;
  late String Function(String key) text;
  late Future<void> Function() refreshDiagnosis;

  void bind({
    required bool Function() isMounted,
    required String Function(String key) text,
    required Future<void> Function() refreshDiagnosis,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.refreshDiagnosis = refreshDiagnosis;
  }

  /// Unavailable State (CONTEXT.md): user-triggered vocabulary actions report
  /// the missing core instead of silently doing nothing. Background loads
  /// (word/phrase entries, phrase candidates) use the repository availability
  /// signal and stay silent.
  bool _requireRepository() {
    final available = workflow.repositoryAvailable;
    if (!available && isMounted()) {
      player.setStatus(text('statusConnectLocalCoreFirst'));
    }
    return available;
  }

  Future<void> loadPhraseCandidates(Cue? cue) async {
    await workflow.loadPhraseCandidates(
      cue: cue,
      learning: learning,
      isMounted: isMounted,
      currentCueId: () => subtitle.currentPrimaryCue?.id,
    );
  }

  Future<void> markFirstWord(String? wordStatus) async {
    if (!_requireRepository()) return;
    await workflow.markFirstWord(
      cue: subtitle.currentPrimaryCue,
      wordStatus: wordStatus,
      language: settings.resolveLearningLanguage(
        subtitle.primaryTrack?.language,
      ),
      learning: learning,
      isMounted: isMounted,
      sourceFor: _sourceFor,
    );
    await refreshDiagnosis();
  }

  Future<void> loadWordEntries() async {
    await workflow.loadWordEntries(
      track: subtitle.primaryTrack,
      language: settings.resolveLearningLanguage(
        subtitle.primaryTrack?.language,
      ),
      learning: learning,
      isMounted: isMounted,
    );
  }

  Future<void> loadPhraseEntries() async {
    await workflow.loadPhraseEntries(
      language: settings.resolveLearningLanguage(
        subtitle.primaryTrack?.language,
      ),
      learning: learning,
      isMounted: isMounted,
    );
  }

  Future<void> openWord(SubtitleToken token, Cue cue) async {
    if (!_requireRepository()) return;
    try {
      await workflow.openWord(
        token: token,
        cue: cue,
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusDictionaryUnavailable'),
          error: true,
          failure: workflow.failureDetail(error),
        );
      }
    }
  }

  Future<void> setSelectedWordStatus(String? selected) async {
    if (!_requireRepository()) return;
    try {
      final update = await workflow.setSelectedWordStatus(
        selected: selected,
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
      if (isMounted() && update != null) {
        player.setStatus(
          text(
            'statusGlobalWordStatusUpdated',
          ).replaceAll('{word}', update.tokenText),
        );
      }
      await refreshDiagnosis();
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusWordUpdateFailed'),
          error: true,
          failure: workflow.failureDetail(error),
        );
      }
    }
  }

  Future<void> setCapabilityOverride(
    String capability,
    String? conclusion,
  ) async {
    if (!_requireRepository()) return;
    try {
      await workflow.setCapabilityOverride(
        capability: capability,
        conclusion: conclusion,
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusCapabilityUpdateFailed'),
          error: true,
          failure: workflow.failureDetail(error),
        );
      }
    }
  }

  Future<void> saveSelectedLearningContent(
    String? definition,
    String? note,
  ) async {
    if (!_requireRepository()) return;
    await workflow.saveSelectedLearningContent(
      definition: definition,
      note: note,
      learning: learning,
      isMounted: isMounted,
    );
  }

  Future<void> recordCurrentSource() async {
    if (!_requireRepository()) return;
    try {
      await workflow.recordCurrentSource(
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusRecordSourceFailed'),
          error: true,
          failure: workflow.failureDetail(error),
        );
      }
    }
  }

  Future<void> observeSelected(bool heard) async {
    if (!_requireRepository()) return;
    final observed = await workflow.observeSelected(
      heard: heard,
      learning: learning,
      sourceFor: _sourceFor,
    );
    // A false here means no word is selected; the heard/not-heard buttons
    // only render with a selection, so the click stays silent.
    if (!observed) return;
    if (isMounted()) {
      player.setStatus(heard ? text('heard') : text('notHeard'));
    }
    await refreshDiagnosis();
  }

  Map<String, dynamic>? _sourceFor(SubtitleToken token, Cue cue) {
    if (player.mediaFingerprint == null) return null;
    return {
      'media_id': player.mediaId,
      'sentence_id': cue.id,
      'original_form': token.text,
      'sentence_text': cue.text,
      'media_title': player.mediaTitle ?? '',
      'media_fingerprint': player.mediaFingerprint,
      'start_ms': cue.start.inMilliseconds,
      'end_ms': cue.end.inMilliseconds,
      'token_start': token.index,
      'token_end': token.index,
    };
  }
}
