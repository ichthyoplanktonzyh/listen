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
import '../widgets/common/capability_viz.dart' show capabilityAssessmentColor;
import '../widgets/vocabulary/vocabulary_book_view.dart';

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
    this.onPauseBackgroundPlayback,
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

  /// Pauses whatever is playing behind this route (the primary player) so a
  /// slice owns audio focus alone, matching the workbench behaviour.
  final Future<void> Function()? onPauseBackgroundPlayback;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
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
  }

  @override
  void dispose() {
    unawaited(widget.auxiliaryAudio.stop());
    super.dispose();
  }

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
            final narrowSubSurface = !twoPane && openDetails != null;
            return Scaffold(
              appBar: AppBar(
                leading: narrowSubSurface
                    ? BackButton(onPressed: _closeDetails)
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
        SizedBox(width: 340, child: _listColumn(l)),
        VerticalDivider(width: 1, color: colors.outlineVariant),
        Expanded(
          child: openDetails == null
              ? _emptyDetailsPane(l)
              : _detailBody(openDetails),
        ),
      ],
    );
  }

  Widget _narrowBody(AppLocalizations l) {
    final openDetails = state.details;
    if (openDetails != null) return _detailBody(openDetails);
    return _listColumn(l);
  }

  Widget _emptyDetailsPane(AppLocalizations l) => Center(
    child: ListenEmptyState(
      icon: Icons.hearing_outlined,
      message: l.text('dictionarySelectWord'),
    ),
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
              slicePlayer: slicePlayer,
              onPlay: (occurrence) =>
                  unawaited(_playOccurrenceMap(occurrence.toJson())),
              onMark: (occurrence, heard) =>
                  _markOccurrence(value.entry, occurrence, heard),
              onSearchLibrary: () => viewModel.searchLibraryFor(value.entry),
              onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
              onCollectCorpus: (occurrence) =>
                  _collectCorpus(value.entry, occurrence),
              pronunciationLoading: state.pronunciationLoading,
              onListeningOverride: (conclusion) => _reportUpdate(
                () => viewModel.setListeningOverride(value.entry, conclusion),
              ),
              onLoadEvidenceHistory: ({String? capability, int offset = 0}) =>
                  viewModel.observationHistory(value.entry.id, offset: offset),
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
  Widget _listColumn(AppLocalizations l) {
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
        _filterRow(
          children: [
            _assessmentChip(l.text('vocabFilterAll'), null),
            for (final value in assessmentFilters)
              _assessmentChip(
                l.text(value),
                value,
                color: capabilityAssessmentColor(colors, value),
              ),
          ],
        ),
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
      selectedEntryId: state.details?.entry.id,
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
