import '../models/timeline.dart';
import '../services/api_service.dart';
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

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  late String Function(String key) text;
  late Future<void> Function() refreshDiagnosis;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required String Function(String key) text,
    required Future<void> Function() refreshDiagnosis,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.text = text;
    this.refreshDiagnosis = refreshDiagnosis;
  }

  /// Unavailable State (CONTEXT.md): user-triggered vocabulary actions report
  /// the missing core instead of silently doing nothing. Background loads
  /// (word/phrase entries, phrase candidates) keep passing [getApi] straight
  /// through and stay silent.
  LocalApi? _requireApi() {
    final api = getApi();
    if (api == null && isMounted()) {
      player.setStatus(text('statusConnectLocalCoreFirst'));
    }
    return api;
  }

  Future<void> loadPhraseCandidates(Cue? cue) async {
    await workflow.loadPhraseCandidates(
      api: getApi(),
      cue: cue,
      learning: learning,
      isMounted: isMounted,
      currentCueId: () => subtitle.currentPrimaryCue?.id,
    );
  }

  Future<void> markFirstWord(String? wordStatus) async {
    final api = _requireApi();
    if (api == null) return;
    await workflow.markFirstWord(
      api: api,
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
      api: getApi(),
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
      api: getApi(),
      language: settings.resolveLearningLanguage(
        subtitle.primaryTrack?.language,
      ),
      learning: learning,
      isMounted: isMounted,
    );
  }

  Future<void> openWord(SubtitleToken token, Cue cue) async {
    final api = _requireApi();
    if (api == null) return;
    try {
      await workflow.openWord(
        api: api,
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
      if (isMounted()) player.setStatus('${text('statusDictionaryUnavailable')}: $error', error: true);
    }
  }

  Future<void> setSelectedWordStatus(String? selected) async {
    final api = _requireApi();
    if (api == null) return;
    try {
      final update = await workflow.setSelectedWordStatus(
        api: api,
        selected: selected,
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
      if (isMounted() && update != null) {
        player.setStatus(text('statusGlobalWordStatusUpdated').replaceAll('{word}', update.tokenText));
      }
      await refreshDiagnosis();
    } catch (error) {
      if (isMounted()) player.setStatus('${text('statusWordUpdateFailed')}: $error', error: true);
    }
  }

  Future<void> setCapabilityOverride(
    String capability,
    String? conclusion,
  ) async {
    final api = _requireApi();
    if (api == null) return;
    try {
      await workflow.setCapabilityOverride(
        api: api,
        capability: capability,
        conclusion: conclusion,
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
    } catch (error) {
      if (isMounted()) {
        player.setStatus('${text('statusCapabilityUpdateFailed')}: $error', error: true);
      }
    }
  }

  Future<void> saveSelectedLearningContent(
    String? definition,
    String? note,
  ) async {
    final api = _requireApi();
    if (api == null) return;
    await workflow.saveSelectedLearningContent(
      api: api,
      definition: definition,
      note: note,
      learning: learning,
      isMounted: isMounted,
    );
  }

  Future<void> recordCurrentSource() async {
    final api = _requireApi();
    if (api == null) return;
    try {
      await workflow.recordCurrentSource(
        api: api,
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
        learning: learning,
        isMounted: isMounted,
        sourceFor: _sourceFor,
      );
    } catch (error) {
      if (isMounted()) {
        player.setStatus('${text('statusRecordSourceFailed')}: $error', error: true);
      }
    }
  }

  Future<void> observeSelected(bool heard) async {
    final api = _requireApi();
    if (api == null) return;
    final observed = await workflow.observeSelected(
      api: api,
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
