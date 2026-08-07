import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/auxiliary_audio_controller.dart';
import '../controllers/hunting_controller.dart';
import '../controllers/occurrence_media_resolver.dart';
import '../controllers/slice_player_controller.dart';
import '../controllers/vocabulary_view_model.dart';
import '../controllers/semantic_search_view_model.dart';
import '../localization.dart';
import '../models/api_failure.dart';
import '../models/production_corpus.dart';
import '../models/types.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/common/api_failure_disclosure.dart';
import '../widgets/common/listen_empty_state.dart';
import '../widgets/common/listen_loading.dart';
import '../widgets/vocabulary/hunting_list_panel.dart';
import '../widgets/vocabulary/semantic_search_dialog.dart';
import '../widgets/vocabulary/listening_dictionary_entry_view.dart';
import '../widgets/common/capability_viz.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/vocabulary_gap_panel.dart';

/// The dictionary hands slice audio to the practice window through this
/// callback; the occurrence arrives as the raw occurrence JSON.
typedef VocabularyShadowingCallback =
    Future<void> Function(String path, Map<String, dynamic> occurrence);

/// The listening dictionary workbench.
///
/// This is the View half of the screen: it renders [VocabularyState], turns
/// gestures into view-model intent, and owns the surfaces that need a
/// `BuildContext` — dialogs, the bottom sheet, SnackBar sentences and the
/// in-page slice player. State, request sequencing and degradation policy live
/// in [VocabularyViewModel]; the backend is reached only through
/// its injected [VocabularyViewModel].
///
class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.viewModel,
    required this.semanticSearchViewModel,
    required this.slicePlayer,
    required this.language,
    required this.onExport,
    required this.onImport,
    required this.huntingController,
    required this.auxiliaryAudio,
    this.initialEntryId,
    this.openCrossModalReviewOnStart = false,
    this.onPauseBackgroundPlayback,
    this.onStartShadowing,
  });

  final VocabularyViewModel viewModel;
  final SemanticSearchViewModel semanticSearchViewModel;
  final SlicePlayerController slicePlayer;
  final String language;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
  final AuxiliaryAudioController auxiliaryAudio;
  final String? initialEntryId;
  final bool openCrossModalReviewOnStart;

  /// Pauses whatever is playing behind this route (the primary player) so a
  /// slice owns audio focus alone, matching the workbench behaviour.
  final Future<void> Function()? onPauseBackgroundPlayback;

  /// Hands a slice's audio to the practice window. The occurrence is the raw
  /// occurrence JSON the practice surface already speaks.
  final VocabularyShadowingCallback? onStartShadowing;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const capabilities = ['reading', 'listening', 'speaking', 'writing'];
  static const assessmentFilters = ['acquired', 'not_acquired', 'unassessed'];

  VocabularyViewModel get viewModel => widget.viewModel;

  /// The dictionary hosts its own second-decoder slice playback so playing an
  /// example never leaves this screen or touches the primary player. It stays
  /// with the View: it is handed straight to the entry view, which subscribes
  /// to it directly.
  SlicePlayerController get slicePlayer => widget.slicePlayer;
  HuntingController get hunting => widget.huntingController;

  /// The current snapshot the build methods render from.
  VocabularyState get state => viewModel.state;

  @override
  void initState() {
    super.initState();
    unawaited(viewModel.load());
    // The gap instrument room is the default right pane, so its two sources
    // load up front (best-effort, each caught) rather than behind a click.
    unawaited(viewModel.loadGapPanel());
    unawaited(viewModel.probeSemanticSearch());
    // The hunting controller is shared with the app shell, whose
    // ListenableBuilder is already subscribed while this route's first build
    // is in progress — load() notifies synchronously, so defer it past the
    // frame (same pattern as realtime_conversation_panel).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(hunting.load());
    });
    final initialEntryId = widget.initialEntryId;
    if (initialEntryId != null) {
      unawaited(viewModel.openEntry(initialEntryId));
    }
    if (widget.openCrossModalReviewOnStart) {
      // The coach's cross-modal hand-off lands on the gap pane (the default
      // right pane) rather than a dialog; emphasise the candidates section.
      viewModel.landOnGapPane(highlightCandidates: true);
    }
  }

  @override
  void dispose() {
    unawaited(widget.auxiliaryAudio.stop());
    super.dispose();
  }

  String _capabilityLabelKey(String value) => switch (value) {
    'reading' => 'capabilityReading',
    'listening' => 'capabilityListening',
    'speaking' => 'capabilitySpeaking',
    _ => 'capabilityWriting',
  };

  // ── Auxiliary audio (the shared controller owns its own transport) ──

  Future<void> _acquireAuxiliaryAudioFocus() async {
    await slicePlayer.pause();
    await widget.onPauseBackgroundPlayback?.call();
  }

  Future<void> _playPronunciationAudio(String url) async {
    await widget.auxiliaryAudio.playRemote(
      url,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && widget.auxiliaryAudio.error != null) {
      _snack(AppLocalizations.of(context).text('pronunciationUnavailable'));
    }
  }

  Future<void> _speakSynthetic(String text, String purpose) async {
    final asset = await widget.auxiliaryAudio.speak(
      text,
      language: state.details?.entry.language ?? widget.language,
      purpose: purpose,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && asset == null) {
      _snack(AppLocalizations.of(context).text('ttsUnavailable'));
    }
  }

  void _closeDetails() {
    unawaited(widget.auxiliaryAudio.stop());
    viewModel.closeDetails();
  }

  // ── Dialogs and sheets (the surfaces that need a BuildContext) ──

  Future<void> _openProductionAttempt(ProductionCorpusHitView hit) async {
    final attemptId = hit.document.attemptId;
    final attempt = attemptId == null
        ? null
        : await viewModel.productionAttempt(attemptId);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('myOutputAttempt')),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '${hit.document.activityKind} · ${l.text('revision')} ${hit.document.responseRevision}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              if (attempt == null) ...[
                SelectableText(hit.document.responseText),
              ],
              // `attempt?.responses ?? const []` would infer `List<dynamic>`
              // here (a for-in gives the literal an `Iterable<dynamic>`
              // context), so promote instead and keep `response` typed.
              if (attempt != null)
                for (final response in attempt.responses) ...[
                  Text(
                    '${l.text('revision')} ${response.revision}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: ListenSpacing.gap4),
                  SelectableText(response.transcript),
                  const SizedBox(height: ListenSpacing.gap12),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  void _openSemanticIndexManager() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => SemanticSearchDialog(
          viewModel: widget.semanticSearchViewModel,
          language: widget.language,
        ),
      ),
    );
  }

  Future<void> _openProjectionReview(String lexicalEntryId) async {
    final l = AppLocalizations.of(context);
    final outcome = await viewModel.projectionProposals(lexicalEntryId);
    final proposals = outcome.proposals;
    if (proposals == null) {
      if (mounted) {
        _snack(l.text('projectionReviewUnavailable'), failure: outcome.failure);
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('projectionReviewTitle')),
        content: SizedBox(
          width: 680,
          child: proposals.isEmpty
              ? Text(l.text('projectionReviewEmpty'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final proposal in proposals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${proposal.capability} → ${proposal.proposedConclusion}',
                        ),
                        subtitle: Text(
                          '${proposal.rationale}\n${proposal.algorithmVersion} · ${proposal.status}',
                        ),
                        isThreeLine: true,
                        trailing: proposal.status != 'pending'
                            ? null
                            : Wrap(
                                children: [
                                  IconButton(
                                    tooltip: l.text('reject'),
                                    onPressed: () async {
                                      await viewModel.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'reject',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                  IconButton(
                                    tooltip: l.text('confirm'),
                                    onPressed: () async {
                                      await viewModel.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'confirm',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          viewModel.openEntry(lexicalEntryId),
                                        );
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _openHuntingList() async {
    await hunting.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: HuntingListPanel(
            controller: hunting,
            onRefresh: () async {
              await hunting.load();
            },
            onPromoteCandidate: (candidate) async {
              final saved = await hunting.promoteCandidate(candidate);
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingAdded'));
              }
            },
            onArchiveTarget: (target) async {
              final saved = await hunting.archive(target);
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingArchived'));
              }
            },
            onOpenEntry: (entryId) {
              Navigator.of(sheetContext).pop();
              unawaited(viewModel.openEntry(entryId));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addToHuntingList(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    if (hunting.state.containsLexicalEntry(entry.id)) {
      _snack(l.text('huntingAlreadyAdded'));
      return;
    }
    final saved = await hunting.addManual(entry);
    if (!mounted) return;
    if (saved) {
      _snack(l.text('huntingAdded'));
    } else if (hunting.state.error != null) {
      // The controller's own `error` is already a named sentence (#66), so the
      // localized one wins here rather than being pasted into a placeholder.
      _snack(l.text('huntingUpdateFailed'));
    }
  }

  // ── Slice playback (in-page, second decoder) ──

  Future<void> _playOccurrenceMap(Map<String, dynamic> occurrence) async {
    final resolution = await viewModel.resolveOccurrenceMedia(occurrence);
    if (!mounted) return;
    if (resolution is UnresolvedOccurrenceMedia) {
      await slicePlayer.showError(resolution.message, occurrence: occurrence);
      return;
    }
    await widget.onPauseBackgroundPlayback?.call();
    await slicePlayer.open(
      path: (resolution as ResolvedOccurrenceMedia).path,
      occurrence: occurrence,
    );
    slicePlayer.setShowVideo(true);
  }

  Future<void> _startShadowingOccurrence(LexicalOccurrence occurrence) async {
    final path = slicePlayer.state.path;
    final callback = widget.onStartShadowing;
    if (path == null || callback == null) return;
    await slicePlayer.pause();
    // Pushed contexts (deep links, tests) dismiss themselves; as a shell
    // route the dictionary stays and hands audio to the practice window.
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    await callback(path, occurrence.toJson());
  }

  Future<void> _playCorpus(CorpusOccurrence occurrence) async {
    if (occurrence.mediaId == null) return;
    final playable = await viewModel.corpusPlaybackOccurrence(occurrence);
    if (playable == null) {
      if (!mounted) return;
      await slicePlayer.showError(
        AppLocalizations.of(context).text('dictionaryClipNeedsSource'),
      );
      return;
    }
    await _playOccurrenceMap(playable);
  }

  // ── Outcomes the view turns into a sentence ──

  /// Every entry write shares one failure sentence; success is either silent
  /// or has its own line at the call site.
  Future<void> _reportUpdate(Future<ApiFailure?> Function() write) async {
    final l = AppLocalizations.of(context);
    final failure = await write();
    if (failure != null && mounted) {
      _snack(l.text('dictionaryUpdateFailed'), failure: failure);
    }
  }

  Future<void> _saveContent(
    LexicalEntry entry,
    String? definition,
    String? note,
  ) async {
    final l = AppLocalizations.of(context);
    final failure = await viewModel.saveContent(entry, definition, note);
    if (!mounted) return;
    if (failure != null) {
      _snack(l.text('dictionaryUpdateFailed'), failure: failure);
    } else {
      _snack(l.text('dictionaryContentSaved'));
    }
  }

  Future<bool> _collectCorpus(
    LexicalEntry entry,
    CorpusOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    final failure = await viewModel.collectCorpus(entry, occurrence);
    if (mounted) {
      _snack(
        l.text(
          failure == null ? 'dictionaryCollected' : 'dictionaryCollectFailed',
        ),
        failure: failure,
      );
    }
    return failure == null;
  }

  Future<void> _reindexCorpus() async {
    final l = AppLocalizations.of(context);
    final outcome = await viewModel.reindexCorpus();
    if (!mounted) return;
    final count = outcome.count;
    if (count == null) {
      _snack(l.text('dictionaryReindexFailed'), failure: outcome.failure);
    } else {
      _snack(l.text('dictionaryReindexDone').replaceAll('{count}', '$count'));
    }
  }

  Future<void> _addToReview(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    final failure = await viewModel.addToReview(entry);
    if (!mounted) return;
    _snack(
      l.text(
        failure == null ? 'dictionaryReviewQueued' : 'dictionaryReviewFailed',
      ),
      failure: failure,
    );
  }

  Future<void> _reviewClip(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    final failure = await viewModel.reviewClip(entry, occurrence);
    if (!mounted) return;
    _snack(
      l.text(
        failure == null ? 'dictionaryReviewQueued' : 'dictionaryReviewFailed',
      ),
      failure: failure,
    );
  }

  Future<bool> _markOccurrence(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    final l = AppLocalizations.of(context);
    final outcome = await viewModel.markOccurrence(entry, occurrence, heard);
    // An occurrence with no sentence anchor never asked anything, so it says
    // nothing either.
    if (!outcome.attempted) return false;
    final failure = outcome.failure;
    if (mounted) {
      _snack(
        l.text(
          failure != null
              ? 'dictionaryMarkFailed'
              : heard
              ? 'dictionaryMarkedHeard'
              : 'dictionaryMarkedNotHeard',
        ),
        failure: failure,
      );
    }
    return failure == null;
  }

  /// A SnackBar that names what failed, with the diagnostics one tap away.
  ///
  /// Every call here used to read
  /// `_snack(l.text('…').replaceAll('{error}', '$error'))`, which put the whole
  /// exception in the bar. A bar is one line and cannot hold a disclosure, so
  /// [failure] becomes an action that opens the same fields in a dialog — and
  /// the reference id a bug report needs stops being thrown away.
  void _snack(String message, {ApiFailure? failure}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: ApiFailureDisclosure.hasDetail(failure)
            ? SnackBarAction(
                label: AppLocalizations.of(context).text('failureDetailsShow'),
                onPressed: () =>
                    unawaited(showApiFailureDetails(context, failure!)),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two panes side by side above the fold, single column below it (the
        // narrow "B" form). Same semantics, two breakpoint shapes (S0).
        final twoPane =
            constraints.maxWidth >= ListenBreakpoints.vocabularyTwoPane;
        return ListenableBuilder(
          // One subscription for the whole surface, exactly like the setState
          // it replaces: the view model publishes the workbench's state, the
          // other two are shared controllers this screen also renders.
          listenable: Listenable.merge([
            viewModel,
            hunting,
            widget.auxiliaryAudio,
          ]),
          builder: (context, _) {
            final openDetails = state.details;
            // The narrow form stacks the list, gap pane and detail, so a
            // sub-surface needs a back affordance. The two-pane form keeps the
            // list beside the pane, so its app bar never grows a leading — it
            // never transforms (V5).
            final narrowSubSurface =
                !twoPane && (openDetails != null || state.narrowGapOpen);
            return Scaffold(
              appBar: AppBar(
                leading: narrowSubSurface
                    ? BackButton(
                        onPressed: () {
                          if (state.details != null) {
                            _closeDetails();
                          } else {
                            viewModel.closeNarrowGap();
                          }
                        },
                      )
                    : null,
                // Never transforms: title and tools stay constant whatever the
                // right pane shows. Detail actions live in the detail pane, not
                // the top bar (V5 death).
                title: Text(l.text('listeningDictionary')),
                actions: [
                  IconButton(
                    tooltip: l.text('huntingOpen'),
                    onPressed: () => unawaited(_openHuntingList()),
                    icon: Badge(
                      isLabelVisible: hunting.state.targets.isNotEmpty,
                      label: Text('${hunting.state.targets.length}'),
                      child: const Icon(Icons.gps_fixed),
                    ),
                  ),
                  _toolsMenu(l),
                ],
              ),
              body: twoPane ? _twoPaneBody(l) : _narrowBody(l),
            );
          },
        );
      },
    );
  }

  /// The maintenance domain, permanently layered off the core flow: import,
  /// export, corpus reindex and semantic-index management all live in one
  /// overflow menu (C3/V5).
  Widget _toolsMenu(AppLocalizations l) => PopupMenuButton<String>(
    tooltip: l.text('vocabToolsMenu'),
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      switch (value) {
        case 'import':
          unawaited(widget.onImport());
        case 'export':
          unawaited(widget.onExport());
        case 'reindex':
          unawaited(_reindexCorpus());
        case 'semantic':
          _openSemanticIndexManager();
      }
    },
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'import',
        child: _toolsItem(Icons.file_download_outlined, l.text('importAssets')),
      ),
      PopupMenuItem(
        value: 'export',
        child: _toolsItem(Icons.file_upload_outlined, l.text('exportAssets')),
      ),
      PopupMenuItem(
        value: 'reindex',
        child: _toolsItem(
          Icons.manage_search_outlined,
          l.text('dictionaryReindex'),
        ),
      ),
      PopupMenuItem(
        value: 'semantic',
        child: _toolsItem(
          Icons.travel_explore_outlined,
          l.text('vocabToolsSemanticIndex'),
        ),
      ),
    ],
  );

  Widget _toolsItem(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: ListenIconSize.control),
      const SizedBox(width: ListenSpacing.gap12),
      Text(label),
    ],
  );

  Widget _twoPaneBody(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final openDetails = state.details;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _listColumn(l, gapSelected: openDetails == null),
        ),
        VerticalDivider(width: 1, color: colors.outlineVariant),
        Expanded(
          child: openDetails == null ? _gapPane() : _detailBody(openDetails),
        ),
      ],
    );
  }

  Widget _narrowBody(AppLocalizations l) {
    final openDetails = state.details;
    if (openDetails != null) return _detailBody(openDetails);
    if (state.narrowGapOpen) return _gapPane();
    return _listColumn(l, gapSelected: false, showGapStrip: true);
  }

  Widget _gapPane() => VocabularyGapPanel(
    loading: state.gapLoading,
    candidates: state.gapCandidates,
    candidatesError: state.gapCandidatesError,
    production: state.gapProduction,
    productionError: state.gapProductionError,
    highlightCandidates: state.gapHighlightCandidates,
    onOpenEntry: (id) => unawaited(viewModel.openEntry(id)),
  );

  Widget _detailBody(LexicalEntryDetails value) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ListenBreakpoints.contentColumnMax,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailActionsHeader(value),
          Expanded(
            child: ListeningDictionaryEntryView(
              // Rebind state when switching entries so reveal/mark/search state
              // never leaks from another word.
              key: ValueKey(value.entry.id),
              details: value,
              showProductionCorpus: true,
              productionHits: state.productionHits,
              productionLoadFailed: state.productionLoadFailed,
              onOpenProductionAttempt: _openProductionAttempt,
              slicePlayer: slicePlayer,
              onPlay: (occurrence) =>
                  unawaited(_playOccurrenceMap(occurrence.toJson())),
              onShadowing: widget.onStartShadowing == null
                  ? null
                  : _startShadowingOccurrence,
              onMark: (occurrence, heard) =>
                  _markOccurrence(value.entry, occurrence, heard),
              onSearchLibrary: () => viewModel.searchLibraryFor(value.entry),
              onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
              onCollectCorpus: (occurrence) =>
                  _collectCorpus(value.entry, occurrence),
              suggestions: state.suggestions,
              suggestionsLoading: state.suggestionsLoading,
              pronunciationLoading: state.pronunciationLoading,
              onConfirmSuggestion: (suggestion) => _reportUpdate(
                () => viewModel.confirmSuggestion(value.entry, suggestion),
              ),
              onRejectSuggestion: (suggestion) => _reportUpdate(
                () => viewModel.rejectSuggestion(value.entry, suggestion),
              ),
              onCapabilityOverride: (capability, conclusion) => _reportUpdate(
                () => viewModel.setCapabilityOverride(
                  value.entry,
                  capability,
                  conclusion,
                ),
              ),
              onLoadEvidenceHistory: ({String? capability, int offset = 0}) =>
                  viewModel.observationHistory(
                    value.entry.id,
                    capability: capability,
                    offset: offset,
                  ),
              onSaveContent: (definition, note) =>
                  _saveContent(value.entry, definition, note),
              onCreateSenseFolder: (label, definition, gloss, externalRef) =>
                  _reportUpdate(
                    () => viewModel.createSenseFolder(
                      value.entry,
                      label,
                      definition,
                      gloss,
                      externalRef,
                    ),
                  ),
              onUpdateSenseFolder:
                  (id, label, definition, gloss, externalRef) => _reportUpdate(
                    () => viewModel.updateSenseFolder(
                      value.entry,
                      id,
                      label,
                      definition,
                      gloss,
                      externalRef,
                    ),
                  ),
              onDeleteSenseFolder: (id) => _reportUpdate(
                () => viewModel.deleteSenseFolder(value.entry, id),
              ),
              onAssignSenseFolder: (senseId, occurrence) => _reportUpdate(
                () => viewModel.assignSenseFolder(
                  value.entry,
                  senseId,
                  occurrence,
                ),
              ),
              onUnassignSenseFolder: (senseId, occurrence) => _reportUpdate(
                () => viewModel.unassignSenseFolder(
                  value.entry,
                  senseId,
                  occurrence,
                ),
              ),
              onReviewClip: (occurrence) =>
                  _reviewClip(value.entry, occurrence),
              externalLookupUrl: viewModel.externalLookupUrlFor(
                value.entry.displayForm,
                value.entry.language,
              ),
              onOpenExternal: viewModel.openExternal,
              pronunciationAudioUrl: state.pronunciationAudioUrl,
              onPlayPronunciationAudio: (url) =>
                  unawaited(_playPronunciationAudio(url)),
              onSpeakSynthetic: (text, purpose) =>
                  unawaited(_speakSynthetic(text, purpose)),
              speechBusy: widget.auxiliaryAudio.busy,
            ),
          ),
        ],
      ),
    ),
  );

  /// The detail pane's own action bar. These used to hijack the app bar (V5);
  /// they now travel with the detail so the shell never transforms.
  ///
  /// Its left slot used to repeat the display form, directly above the
  /// identity card's own word head — the same word twice, 12pt apart, and the
  /// small one carried nothing the big one did not. It now carries the thing
  /// the header could not say: which source the word was met in.
  Widget _detailActionsHeader(LexicalEntryDetails value) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final inHunting = hunting.state.containsLexicalEntry(value.entry.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Row(
        children: [
          Expanded(child: _detailSourceLabel(value)),
          TextButton.icon(
            onPressed: () => unawaited(_addToReview(value.entry)),
            icon: const Icon(
              Icons.queue_music_outlined,
              size: ListenIconSize.control,
            ),
            label: Text(l.text('dictionaryAddToReview')),
          ),
          IconButton(
            tooltip: inHunting
                ? l.text('huntingAlreadyAdded')
                : l.text('huntingAddCurrent'),
            onPressed: hunting.state.busy || inHunting
                ? null
                : () => unawaited(_addToHuntingList(value.entry)),
            icon: Icon(
              inHunting ? Icons.gps_fixed : Icons.add_location_alt_outlined,
              color: inHunting ? colors.primary : null,
            ),
          ),
          IconButton(
            tooltip: l.text('projectionReviewTitle'),
            onPressed: () => unawaited(_openProjectionReview(value.entry.id)),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
    );
  }

  /// Where this word was met: the durable media title of its first source
  /// clip, quiet enough to stay context rather than compete with the word
  /// head below it. When the entry has several sources the extra titles are
  /// in the tooltip — the bar has room for one, and the clips section is
  /// where the full list belongs.
  Widget _detailSourceLabel(LexicalEntryDetails value) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final titles = <String>{
      for (final occurrence in value.occurrences)
        if (occurrence.mediaTitleSnapshot.trim().isNotEmpty)
          occurrence.mediaTitleSnapshot.trim(),
    };
    final label = titles.isEmpty
        ? l.text('vocabDetailSourceUnknown')
        : titles.first;
    return Tooltip(
      message: titles.length > 1 ? titles.join('\n') : label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_outlined,
            size: ListenIconSize.inline,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: ListenSpacing.gap6),
          Flexible(
            child: Text(
              label,
              style: ListenType.caption.copyWith(
                color: colors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// The list column (left of the workbench, or the whole narrow screen): the
  /// search box, the persistent gap entry, the channel/assessment lens, then
  /// the word list.
  Widget _listColumn(
    AppLocalizations l, {
    required bool gapSelected,
    bool showGapStrip = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: state.semanticMode
                        ? l.text('semanticSearchHint')
                        : l.text('searchVocabulary'),
                  ),
                  onChanged: viewModel.searchChanged,
                  onSubmitted: (_) => viewModel.submitSearch(),
                ),
              ),
              // The semantic "use" surface folds into the main box; only the
              // "manage" surface stays in the tools menu. The toggle appears
              // only when the capability can actually search.
              if (state.semanticCanSearch) ...[
                const SizedBox(width: ListenSpacing.gap8),
                FilterChip(
                  label: Text(l.text('semanticSearchToggle')),
                  selected: state.semanticMode,
                  onSelected: viewModel.setSemanticMode,
                ),
              ],
            ],
          ),
        ),
        // The gap instrument room is a permanent entry, not a buried icon —
        // the workbench's self-falsification note asks for a visible way back
        // to the gap list. Two-pane uses a selectable entry row; the narrow
        // form uses a compact gap strip with live counts instead.
        if (showGapStrip)
          _narrowGapStrip(l)
        else
          ListTile(
            dense: true,
            selected: gapSelected,
            selectedTileColor: colors.primary.withValues(alpha: 0.08),
            leading: const Icon(Icons.hub_outlined),
            title: Text(l.text('vocabGapEntry')),
            onTap: viewModel.landOnGapPane,
          ),
        Divider(height: 1, color: colors.outlineVariant),
        // Primary lens: the four-channel capability axis. The channel always
        // re-lenses the entry rings (presentation); it only re-queries once an
        // assessment is picked, which is when the backend filters by capability.
        _filterRow(
          children: [
            for (final cap in capabilities)
              ChoiceChip(
                label: Text(l.text(_capabilityLabelKey(cap))),
                visualDensity: VisualDensity.compact,
                selected: state.capability == cap,
                onSelected: (_) => viewModel.selectCapability(cap),
              ),
          ],
        ),
        _filterRow(
          children: [
            _assessmentChip(l.text('vocabFilterAll'), null),
            for (final value in assessmentFilters)
              _assessmentChip(
                l.text(value),
                value,
                color: capabilityAssessmentColor(
                  Theme.of(context).colorScheme,
                  value,
                ),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(child: _listResults(l)),
      ],
    );
  }

  Widget _listResults(AppLocalizations l) {
    if (state.semanticMode) {
      if (state.semanticSearching) return const Center(child: ListenLoading());
      if (state.semanticHits.isEmpty) {
        return ListenEmptyState(
          icon: Icons.search_off,
          message: l.text('semanticSearchNoHits'),
        );
      }
      return ListView.separated(
        itemCount: state.semanticHits.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final hit = state.semanticHits[index];
          return ListTile(
            title: Text(
              hit.source.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${hit.source.kind}'
              '${hit.source.channel == null ? '' : ' · ${hit.source.channel}'}',
            ),
            trailing: Text(hit.similarity.toStringAsFixed(3)),
          );
        },
      );
    }
    if (state.loading) return const Center(child: ListenLoading());
    if (state.words.isEmpty && state.search.trim().isNotEmpty) {
      return _homeCorpusFallback(l);
    }
    return VocabularyBookView(
      words: state.words,
      onWord: (value) => unawaited(viewModel.openEntry(value.entry.id)),
      focusCapability: state.capability,
      selectedEntryId: state.details?.entry.id,
    );
  }

  /// The narrow ("B") form keeps a compact gap strip at the top of the list so
  /// gap-(c) is one tap away even without a second pane.
  Widget _narrowGapStrip(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final candidateCount = state.gapCandidates?.length;
    final targetCount = state.gapProduction?.targets.length;
    final subtitle = (candidateCount == null && targetCount == null)
        ? l.text('vocabGapEntry')
        : l
              .text('gapPaneSubtitle')
              .replaceAll('{candidates}', '${candidateCount ?? 0}')
              .replaceAll('{targets}', '${targetCount ?? 0}');
    return InkWell(
      onTap: viewModel.landOnGapPane,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: ListenIconSize.control,
              color: colors.secondary,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                subtitle,
                style: ListenType.caption.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              l.text('vocabGapStripAction'),
              style: ListenType.caption.copyWith(color: colors.secondary),
            ),
          ],
        ),
      ),
    );
  }

  /// No vocabulary asset matches the query: the dictionary stays useful as a
  /// pure lookup tool by searching the local corpus directly (play only —
  /// saving a clip needs an entry to attach it to).
  Widget _homeCorpusFallback(AppLocalizations l) {
    final results = state.homeResults;
    if (results == null) {
      return ListenEmptyState(
        icon: Icons.menu_book_outlined,
        message: l.text('noWords'),
        action: OutlinedButton.icon(
          onPressed: state.homeSearching
              ? null
              : () => unawaited(viewModel.searchHomeCorpus()),
          icon: state.homeSearching
              ? const ListenLoading.inline(size: 16)
              : const Icon(
                  Icons.travel_explore_outlined,
                  size: ListenIconSize.control,
                ),
          label: Text(l.text('dictionaryFindMore')),
        ),
      );
    }
    if (results.isEmpty) {
      final externalUrl = viewModel.externalLookupUrlFor(
        state.search,
        widget.language,
      );
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.text('dictionaryNoLibraryResults')),
            if (externalUrl != null) ...[
              const SizedBox(height: ListenSpacing.gap12),
              OutlinedButton.icon(
                onPressed: () => viewModel.openExternal(externalUrl),
                icon: const Icon(
                  Icons.open_in_new,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('dictionaryYouglish')),
              ),
            ],
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final result in results)
          CorpusResultTile(
            occurrence: result,
            target: state.search.trim(),
            onPlay: result.mediaId == null
                ? null
                : () => unawaited(_playCorpus(result)),
            onCollect: null,
          ),
      ],
    );
  }

  /// A lens row wraps; it never scrolls sideways.
  ///
  /// In the two-pane form this column is a fixed 340pt, and a horizontal list
  /// put the assessment filters half off the column edge with nothing to say
  /// more existed — a filter you cannot see is one you cannot tell is off,
  /// which is the opposite of an honest instrument (P4). Wrapping costs one
  /// extra line at the narrowest column and keeps every option on screen.
  Widget _filterRow({required List<Widget> children}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ListenSpacing.gap12,
      vertical: ListenSpacing.gap4,
    ),
    child: Wrap(
      spacing: ListenSpacing.gap8,
      runSpacing: ListenSpacing.gap4,
      children: children,
    ),
  );

  Widget _assessmentChip(String label, String? value, {Color? color}) =>
      ChoiceChip(
        avatar: color == null
            ? null
            : CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        selected: state.assessment == value,
        onSelected: (_) => viewModel.selectAssessment(value),
      );
}
