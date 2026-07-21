import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/hunting_controller.dart';
import '../../controllers/auxiliary_audio_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/practice_actions_coordinator.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../learning_assets_ui.dart';
import '../../models/practice.dart';
import '../../models/personal_expression.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../screens/review_queue_screen.dart';
import '../../screens/personal_expression_screen.dart';
import '../../screens/vocabulary_screen.dart';
import '../../services/api_service.dart';
import '../../utils/word_list_parser.dart';
import '../coach/coach_dashboard_screen.dart';

/// Dialog- and navigation-driven vocabulary/learning flows extracted from the
/// composition root: learning assets/resources, phrase candidates, lemma
/// correction, the vocabulary/review/coach screens, and external word-list
/// import. Parameter names mirror the host's controller fields.

Future<void> openLearningAssetsFlow({
  required BuildContext context,
  required LocalApi? api,
  required SettingsController settingsController,
  required SubtitleController subtitleController,
  required Future<void> Function(Map<String, dynamic> occurrence)
  openSlicePlayback,
  Future<void> Function(PersonalExpressionSourceView source)?
  onPlayExpressionSource,
  Future<void> Function(SentencePatternAssetView pattern)?
  onStartExpressionSpeaking,
}) async {
  if (api == null) return;
  final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => LearningAssetsScreen(
        api: api,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
        onPlayExpressionSource: onPlayExpressionSource,
        onStartExpressionSpeaking: onStartExpressionSpeaking,
      ),
    ),
  );
  if (occurrence != null) await openSlicePlayback(occurrence);
}

Future<void> openPersonalExpressionFlow({
  required BuildContext context,
  required LocalApi? api,
  required String language,
  PersonalExpressionSourceView? initialSource,
  Future<void> Function(PersonalExpressionSourceView source)? onPlaySource,
  Future<void> Function(SentencePatternAssetView pattern)? onStartSpeaking,
}) async {
  if (api == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PersonalExpressionScreen(
        api: api,
        language: language,
        initialSource: initialSource,
        onPlaySource: onPlaySource,
        onStartSpeaking: onStartSpeaking,
      ),
    ),
  );
}

Future<void> openLearningResourcesFlow({
  required BuildContext context,
  required LocalApi? api,
}) async {
  if (api == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => LearningResourceScreen(api: api)),
  );
}

Future<void> showCurrentPhraseCandidatesFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required SettingsController settingsController,
}) async {
  final cue = subtitleController.currentPrimaryCue;
  if (api == null || cue == null || playerController.mediaFingerprint == null) {
    return;
  }
  await showPhraseCandidates(
    context: context,
    api: api,
    sentenceId: cue.id,
    source: {
      'language': settingsController.resolveLearningLanguage(
        subtitleController.primaryTrack?.language,
      ),
      'media_id': playerController.mediaId,
      'sentence_id': cue.id,
      'sentence_text': cue.text,
      'media_title': playerController.mediaTitle ?? '',
      'media_fingerprint': playerController.mediaFingerprint,
      'start_ms': cue.start.inMilliseconds,
      'end_ms': cue.end.inMilliseconds,
    },
  );
}

Future<void> openPhraseFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required SettingsController settingsController,
  required LearningController learningController,
  required PhraseCandidate candidate,
  required Cue cue,
}) async {
  final l = AppLocalizations.of(context);
  if (api == null || playerController.mediaFingerprint == null) return;
  final canonical = candidate.canonicalForm;
  final details = await showPhraseCandidate(
    context: context,
    api: api,
    candidate: candidate,
    initialStatus: learningController.phraseEntries[canonical]?.entry.status,
    source: {
      'language': settingsController.resolveLearningLanguage(
        subtitleController.primaryTrack?.language,
      ),
      'media_id': playerController.mediaId,
      'sentence_id': cue.id,
      'sentence_text': cue.text,
      'media_title': playerController.mediaTitle ?? '',
      'media_fingerprint': playerController.mediaFingerprint,
      'start_ms': cue.start.inMilliseconds,
      'end_ms': cue.end.inMilliseconds,
    },
  );
  if (details != null && context.mounted) {
    learningController.updateSinglePhraseEntry(canonical, details);
    playerController.setStatus(l.text('statusPhraseSaved').replaceAll('{phrase}', candidate.displayForm));
  }
}

/// Owns the lemma text controller so it is disposed with the dialog route,
/// not while the exit animation still renders the field (the host previously
/// disposed it inline, a latent debug-mode assertion).
class _LemmaCorrectionDialog extends StatefulWidget {
  const _LemmaCorrectionDialog({required this.initialText});

  final String initialText;

  @override
  State<_LemmaCorrectionDialog> createState() => _LemmaCorrectionDialogState();
}

class _LemmaCorrectionDialogState extends State<_LemmaCorrectionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: const Text('Correct lemma'),
      content: TextField(controller: _controller),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l.text('save')),
        ),
      ],
    );
  }
}

Future<void> correctCurrentLemmaFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required SettingsController settingsController,
  required LearningController learningController,
}) async {
  final l = AppLocalizations.of(context);
  final token = learningController.selectedToken;
  if (api == null || token?.normalized == null) return;
  final corrected = await showDialog<String>(
    context: context,
    builder: (context) =>
        _LemmaCorrectionDialog(initialText: token!.normalized!),
  );
  if (corrected == null || corrected.isEmpty) return;
  await api.correctLemma(
    token!.normalized!,
    corrected,
    language: settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    ),
  );
  if (context.mounted) {
    playerController.setStatus(l.text('lemmaCorrectionSaved'));
  }
}

Future<void> showVocabularyFlow({
  required BuildContext context,
  required LocalApi? api,
  required SettingsController settingsController,
  required SubtitleController subtitleController,
  required PlaybackActionsCoordinator playbackActions,
  required PracticeActionsCoordinator practiceActions,
  required HuntingController huntingController,
  required AuxiliaryAudioController auxiliaryAudio,
  required Future<void> Function() pauseBackgroundPlayback,
  String? initialEntryId,
  bool openCrossModalReview = false,
}) async {
  final service = api;
  if (service == null) return;
  // The dictionary hosts its own slice playback; it only needs a way to
  // silence the primary player so a slice owns audio focus alone.
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => VocabularyScreen(
        api: service,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
        onExport: playbackActions.exportVocabulary,
        onImport: playbackActions.importVocabulary,
        huntingController: huntingController,
        auxiliaryAudio: auxiliaryAudio,
        initialEntryId: initialEntryId,
        openCrossModalReviewOnStart: openCrossModalReview,
        onPauseBackgroundPlayback: pauseBackgroundPlayback,
        onStartShadowing: practiceActions.startExternalShadowing,
      ),
    ),
  );
}

Future<void> openReviewQueueFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required PlaybackActionsCoordinator playbackActions,
  required Future<void> Function(ReviewQueueEntry entry) startReviewShadowing,
  required Future<void> Function(ReviewQueueEntry entry) startDelayedRetelling,
}) async {
  final service = api;
  if (service == null) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ReviewQueueScreen(
        api: service,
        currentMediaId: playerController.mediaId,
        onPlayRange: (startMs, endMs) => playbackActions.loopRange(
          startMs,
          endMs,
          'Looping review card',
          labelKey: 'loopReview',
        ),
        onPausePlayback: playbackActions.pauseReviewRange,
        onStartShadowing: startReviewShadowing,
        onStartDelayedRetelling: startDelayedRetelling,
      ),
    ),
  );
}

Future<void> openCoachDashboardFlow({
  required BuildContext context,
  required LocalApi? api,
  required String language,
  required Future<void> Function() openReviewQueue,
  required Future<void> Function({bool openCrossModalReview}) openVocabulary,
  required Future<void> Function() openPersonalExpression,
}) async {
  final service = api;
  if (service == null) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => CoachDashboardScreen(
        api: service,
        language: language,
        onNavigate: (destination, _) => switch (destination.kind) {
          'review_queue' => openReviewQueue(),
          'hunting_list' => openVocabulary(),
          'cross_modal_review' => openVocabulary(openCrossModalReview: true),
          'personal_expression' => openPersonalExpression(),
          _ => Future<void>.value(),
        },
      ),
    ),
  );
}

Future<void> importWordListFlow({
  required BuildContext context,
  required LocalApi? api,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required SettingsController settingsController,
  required Future<void> Function() reloadWordEntries,
}) async {
  final l = AppLocalizations.of(context);
  final service = api;
  if (service == null) return;
  const group = XTypeGroup(label: 'word list', extensions: ['txt', 'csv']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return;
  final content = await File(file.path).readAsString();
  final entries = <Map<String, dynamic>>[];
  var defaultStatus = 'known_recognized';
  var overwrite = false;
  try {
    entries.addAll(
      parseExternalWordList(
        content,
        csv: file.path.toLowerCase().endsWith('.csv'),
      ),
    );
  } on FormatException catch (error) {
    playerController.setStatus(error.message);
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(l.text('previewImport')),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(
            children: [
              Text(
                '${entries.length} words · ${entries.take(8).map((e) => e['word']).join(', ')}',
              ),
              DropdownButtonFormField<String>(
                initialValue: defaultStatus,
                items:
                    const [
                          'unknown_meaning',
                          'known_not_recognized',
                          'known_recognized',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(l.status(value)),
                          ),
                        )
                        .toList(),
                onChanged: (value) => refresh(() => defaultStatus = value!),
              ),
              CheckboxListTile(
                value: overwrite,
                title: Text(l.text('overwriteExisting')),
                onChanged: (value) => refresh(() => overwrite = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('import')),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return;
  final result = await service.importExternalVocabulary(
    entries,
    language: settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    ),
    defaultStatus: defaultStatus,
    overwriteExisting: overwrite,
  );
  await reloadWordEntries();
  playerController.setStatus(l.text('statusWordListImported').replaceAll('{result}', '$result'));
}
