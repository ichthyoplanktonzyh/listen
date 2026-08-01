import 'package:flutter/material.dart';

import '../../controllers/auxiliary_audio_controller.dart';
import '../../controllers/hunting_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/learning_assets_view_models.dart';
import '../../controllers/learning_flow_view_models.dart';
import '../../controllers/occurrence_media_resolver.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/practice_actions_coordinator.dart';
import '../../controllers/coach_dashboard_controller.dart';
import '../../controllers/personal_expression_view_model.dart';
import '../../controllers/review_controller.dart';
import '../../controllers/semantic_search_view_model.dart';
import '../../controllers/slice_player_controller.dart';
import '../../controllers/vocabulary_view_model.dart';
import '../../learning_assets_ui.dart';
import '../../localization.dart';
import '../../models/personal_expression.dart';
import '../../models/practice.dart';
import '../../models/types.dart';
import '../../screens/personal_expression_screen.dart';
import '../../screens/review_queue_screen.dart';
import '../../screens/vocabulary_screen.dart';
import '../coach/coach_dashboard_screen.dart';

/// Dialog- and navigation-driven vocabulary/learning flows extracted from the
/// composition root: learning assets/resources, phrase candidates, lemma
/// correction, the vocabulary/review/coach screens, and external word-list
/// import. Parameter names mirror the host's controller fields.

/// Gives route-scoped notifiers an explicit owner without pushing disposal
/// into the reusable screen widgets themselves.
class _OwnedNotifiersRoute extends StatefulWidget {
  const _OwnedNotifiersRoute({required this.notifiers, required this.child});

  final List<ChangeNotifier> notifiers;
  final Widget child;

  @override
  State<_OwnedNotifiersRoute> createState() => _OwnedNotifiersRouteState();
}

class _OwnedNotifiersRouteState extends State<_OwnedNotifiersRoute> {
  @override
  void dispose() {
    for (final notifier in widget.notifiers.reversed) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<PersonalExpressionDetailOutcome> _openPersonalExpressionDetail({
  required BuildContext context,
  required SentencePatternAssetView pattern,
  required PersonalExpressionDetailViewModelFactory createViewModel,
  Future<void> Function(PersonalExpressionSourceView source)? onPlaySource,
  Future<void> Function(SentencePatternAssetView pattern)? onStartSpeaking,
}) async {
  final viewModel = createViewModel(pattern);
  final outcome = await Navigator.of(context)
      .push<PersonalExpressionDetailOutcome>(
        MaterialPageRoute(
          builder: (_) => _OwnedNotifiersRoute(
            notifiers: [viewModel],
            child: PersonalExpressionDetailScreen(
              viewModel: viewModel,
              pattern: pattern,
              onPlaySource: onPlaySource,
              onStartSpeaking: onStartSpeaking == null
                  ? null
                  : (value) async {
                      Navigator.of(context).pop();
                      await onStartSpeaking(value);
                    },
            ),
          ),
        ),
      );
  return outcome ?? PersonalExpressionDetailOutcome.closed;
}

Future<void> openLearningAssetsFlow({
  required BuildContext context,
  required LearningAssetsViewModel? viewModel,
  required PersonalExpressionViewModel Function()?
  createPersonalExpressionViewModel,
  required PersonalExpressionDetailViewModelFactory?
  createPersonalExpressionDetailViewModel,
  required PlayerController playerController,
  required Future<void> Function(Map<String, dynamic> occurrence)
  openSlicePlayback,
  Future<void> Function(PersonalExpressionSourceView source)? onPlaySource,
  Future<void> Function(SentencePatternAssetView pattern)? onStartSpeaking,
}) async {
  if (viewModel == null ||
      createPersonalExpressionViewModel == null ||
      createPersonalExpressionDetailViewModel == null) {
    viewModel?.dispose();
    // Unavailable State (CONTEXT.md): opening the assets screen is
    // user-triggered, so name the cause and recovery instead of swallowing
    // the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [viewModel],
        child: LearningAssetsScreen(
          viewModel: viewModel,
          personalExpressionBuilder: (_) {
            final personalExpressionViewModel =
                createPersonalExpressionViewModel();
            return _OwnedNotifiersRoute(
              notifiers: [personalExpressionViewModel],
              child: PersonalExpressionScreen(
                viewModel: personalExpressionViewModel,
                onOpenPattern: (context, pattern) =>
                    _openPersonalExpressionDetail(
                      context: context,
                      pattern: pattern,
                      createViewModel: createPersonalExpressionDetailViewModel,
                      onPlaySource: onPlaySource,
                      onStartSpeaking: onStartSpeaking,
                    ),
                language: personalExpressionViewModel.language,
                onPlaySource: onPlaySource,
                onStartSpeaking: onStartSpeaking,
              ),
            );
          },
        ),
      ),
    ),
  );
  if (occurrence != null) await openSlicePlayback(occurrence);
}

Future<void> openPersonalExpressionFlow({
  required BuildContext context,
  required PersonalExpressionViewModel? viewModel,
  required PersonalExpressionDetailViewModelFactory? createDetailViewModel,
  required PlayerController playerController,
  PersonalExpressionSourceView? initialSource,
  Future<void> Function(PersonalExpressionSourceView source)? onPlaySource,
  Future<void> Function(SentencePatternAssetView pattern)? onStartSpeaking,
}) async {
  if (viewModel == null || createDetailViewModel == null) {
    viewModel?.dispose();
    // Unavailable State (CONTEXT.md): the expressions screen is a standing
    // user destination; a dead click would hide why it will not open.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [viewModel],
        child: PersonalExpressionScreen(
          viewModel: viewModel,
          onOpenPattern: (context, pattern) => _openPersonalExpressionDetail(
            context: context,
            pattern: pattern,
            createViewModel: createDetailViewModel,
            onPlaySource: onPlaySource,
            onStartSpeaking: onStartSpeaking,
          ),
          language: viewModel.language,
          initialSource: initialSource,
          onPlaySource: onPlaySource,
          onStartSpeaking: onStartSpeaking,
        ),
      ),
    ),
  );
}

Future<void> openLearningResourcesFlow({
  required BuildContext context,
  required LearningResourcesViewModel? viewModel,
  required PlayerController playerController,
}) async {
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): user-triggered menu entry — report the
    // missing core instead of doing nothing.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [viewModel],
        child: LearningResourceScreen(viewModel: viewModel),
      ),
    ),
  );
}

Future<void> openPhraseFlow({
  required BuildContext context,
  required PhraseCandidateViewModel? viewModel,
  required PlayerController playerController,
  required LearningController learningController,
}) async {
  final l = AppLocalizations.of(context);
  if (viewModel == null || playerController.mediaFingerprint == null) {
    viewModel?.dispose();
    // Unavailable State (CONTEXT.md): the phrase chip is a user tap; saving a
    // phrase needs both the core and an open, fingerprinted media source.
    playerController.setStatus(l.text('statusOpenMediaAndCoreFirst'));
    return;
  }
  final canonical = viewModel.candidate.canonicalForm;
  LexicalEntryDetails? details;
  try {
    details = await showPhraseCandidate(context: context, viewModel: viewModel);
  } finally {
    viewModel.dispose();
  }
  if (details != null && context.mounted) {
    learningController.updateSinglePhraseEntry(canonical, details);
    playerController.setStatus(
      l
          .text('statusPhraseSaved')
          .replaceAll('{phrase}', viewModel.candidate.displayForm),
    );
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
      title: Text(l.text('correctLemma')),
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
  required LemmaCorrectionViewModel? viewModel,
  required PlayerController playerController,
  required LearningController learningController,
}) async {
  final l = AppLocalizations.of(context);
  final token = learningController.selectedToken;
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): the correct-lemma button is a user
    // action; report the missing core instead of swallowing the click.
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  // Legitimate silence: the correct-lemma affordance only renders inside the
  // inspector of a selected token, so no selection here means a stale
  // callback race rather than a user-visible refusal.
  if (token?.normalized == null) return;
  final corrected = await showDialog<String>(
    context: context,
    builder: (context) =>
        _LemmaCorrectionDialog(initialText: token!.normalized!),
  );
  // Legitimate silence: the user cancelled the dialog or cleared the field.
  if (corrected == null || corrected.isEmpty) return;
  await viewModel.save(corrected);
  if (context.mounted) {
    playerController.setStatus(l.text('lemmaCorrectionSaved'));
  }
}

Future<void> showVocabularyFlow({
  required BuildContext context,
  required VocabularyViewModel? viewModel,
  required SemanticSearchViewModel? semanticSearchViewModel,
  required PlayerController playerController,
  required PlaybackActionsCoordinator playbackActions,
  required PracticeActionsCoordinator practiceActions,
  required HuntingController huntingController,
  required AuxiliaryAudioController auxiliaryAudio,
  required Future<void> Function() pauseBackgroundPlayback,
  String? initialEntryId,
  bool openCrossModalReview = false,
}) async {
  if (viewModel == null || semanticSearchViewModel == null) {
    viewModel?.dispose();
    semanticSearchViewModel?.dispose();
    // Unavailable State (CONTEXT.md): the vocabulary entry points (rail item,
    // asset card, app-bar menu) are user clicks — a silent return here reads
    // as a dead button when the core is disconnected.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  // The dictionary hosts its own slice playback; it only needs a way to
  // silence the primary player so a slice owns audio focus alone.
  final slicePlayer = SlicePlayerController();
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [viewModel, semanticSearchViewModel, slicePlayer],
        child: VocabularyScreen(
          viewModel: viewModel,
          semanticSearchViewModel: semanticSearchViewModel,
          slicePlayer: slicePlayer,
          language: viewModel.language,
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
    ),
  );
}

Future<void> openReviewQueueFlow({
  required BuildContext context,
  required ReviewController? controller,
  required OccurrenceMediaResolver? resolver,
  required PlayerController playerController,
  required Future<void> Function() pauseBackgroundPlayback,
  required Future<void> Function(ReviewQueueEntry entry) startReviewShadowing,
  required Future<void> Function(ReviewQueueEntry entry) startDelayedRetelling,
}) async {
  if (controller == null || resolver == null) {
    controller?.dispose();
    // Unavailable State (CONTEXT.md): the review queue is a user destination;
    // report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  final slicePlayer = SlicePlayerController();
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      // The card plays its source clip on its own decoder (S5 · R1); it only
      // needs a way to silence the primary player so the clip owns audio.
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [controller, slicePlayer],
        child: ReviewQueueScreen(
          controller: controller,
          resolver: resolver,
          slicePlayer: slicePlayer,
          onPauseBackgroundPlayback: pauseBackgroundPlayback,
          onStartShadowing: startReviewShadowing,
          onStartDelayedRetelling: startDelayedRetelling,
        ),
      ),
    ),
  );
}

Future<void> openCoachDashboardFlow({
  required BuildContext context,
  required CoachDashboardController? controller,
  required PlayerController playerController,
  required String language,
  required Future<void> Function() openReviewQueue,
  required Future<void> Function({bool openCrossModalReview}) openVocabulary,
  required Future<void> Function() openPersonalExpression,
}) async {
  if (controller == null) {
    // Unavailable State (CONTEXT.md): the coach dashboard is a user
    // destination; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => _OwnedNotifiersRoute(
        notifiers: [controller],
        child: CoachDashboardScreen(
          controller: controller,
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
    ),
  );
}

Future<void> importWordListFlow({
  required BuildContext context,
  required ExternalVocabularyImportViewModel? viewModel,
  required PlayerController playerController,
}) async {
  final l = AppLocalizations.of(context);
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): importing a word list is user-triggered
    // and cannot proceed without the core — say so before opening a picker.
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  try {
    final selected = await viewModel.pick();
    // Legitimate silence: the user dismissed the file picker themselves.
    if (!selected) return;
    final formatFailure = viewModel.state.formatFailure;
    if (formatFailure != null) {
      playerController.setStatus(formatFailure);
      return;
    }
    final entries = viewModel.state.entries;
    var defaultStatus = 'known_recognized';
    var overwrite = false;
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
                  onChanged: (value) =>
                      refresh(() => overwrite = value ?? false),
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
    final result = await viewModel.import(
      defaultStatus: defaultStatus,
      overwriteExisting: overwrite,
    );
    playerController.setStatus(
      l.text('statusWordListImported').replaceAll('{result}', '$result'),
    );
  } finally {
    viewModel.dispose();
  }
}
