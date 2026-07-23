import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/slice_player_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../models/production_corpus.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/capability_viz.dart';
import '../common/listen_loading.dart';
import 'dictionary_inline_clip_player.dart';
import 'pronunciation_button.dart';
import '../../theme/typography.dart';

/// Estimated words-per-minute of one clip from its sentence snapshot and time
/// window. A rough, whitespace-tokenized decoration — never a scored metric —
/// so it returns null instead of guessing on degenerate input.
int? clipSpeechRateWpm(String sentence, int startMs, int endMs) {
  final words = sentence
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;
  final durationMs = endMs - startMs;
  if (words == 0 || durationMs < 300) return null;
  return (words * 60000 / durationMs).round();
}

/// The listening-dictionary detail surface keeps the complete entry-level
/// occurrence list authoritative while offering optional user-owned sense
/// folders for organization. The optional callbacks light up Slice 3/4 behaviour — corpus enrichment, capability
/// override editing, definition/note editing, upgrade-suggestion resolution,
/// per-clip review exits, and external reference fallbacks.
class ListeningDictionaryEntryView extends StatefulWidget {
  const ListeningDictionaryEntryView({
    super.key,
    required this.details,
    this.showProductionCorpus = false,
    this.productionHits,
    this.productionLoadFailed = false,
    this.onOpenProductionAttempt,
    this.slicePlayer,
    required this.onPlay,
    required this.onMark,
    this.onShadowing,
    this.onSearchLibrary,
    this.onPlayCorpus,
    this.onCollectCorpus,
    this.suggestions = const [],
    this.onConfirmSuggestion,
    this.onRejectSuggestion,
    this.onCapabilityOverride,
    this.onLoadEvidenceHistory,
    this.onSaveContent,
    this.onCreateSenseFolder,
    this.onUpdateSenseFolder,
    this.onDeleteSenseFolder,
    this.onAssignSenseFolder,
    this.onUnassignSenseFolder,
    this.onReviewClip,
    this.externalLookupUrl,
    this.onOpenExternal,
    this.pronunciationAudioUrl,
    this.onPlayPronunciationAudio,
    this.onSpeakSynthetic,
    this.speechBusy = false,
    this.libraryResultLimit = 50,
  });

  final LexicalEntryDetails details;

  /// The vocabulary screen enables this section; reusable detail surfaces
  /// remain layout-compatible until they opt into the projection.
  final bool showProductionCorpus;

  /// `null` while loading; an empty list is an honest no-output state.
  final List<ProductionCorpusHitView>? productionHits;
  final bool productionLoadFailed;
  final ValueChanged<ProductionCorpusHitView>? onOpenProductionAttempt;
  final SlicePlayerController? slicePlayer;
  final ValueChanged<LexicalOccurrence> onPlay;
  final Future<bool> Function(LexicalOccurrence occurrence, bool heard) onMark;
  final Future<void> Function(LexicalOccurrence occurrence)? onShadowing;

  /// Searches the local corpus for more contexts of this entry.
  final Future<List<CorpusOccurrence>> Function()? onSearchLibrary;
  final ValueChanged<CorpusOccurrence>? onPlayCorpus;

  /// Saves a corpus hit as a durable source occurrence of this entry.
  /// Returns true when persisted.
  final Future<bool> Function(CorpusOccurrence occurrence)? onCollectCorpus;

  /// Pending listening upgrade suggestions for this entry.
  final List<UpgradeSuggestion> suggestions;
  final Future<void> Function(UpgradeSuggestion suggestion)?
  onConfirmSuggestion;
  final Future<void> Function(UpgradeSuggestion suggestion)? onRejectSuggestion;

  /// Sets or clears (conclusion == null) one channel's user override.
  final Future<void> Function(String capability, String? conclusion)?
  onCapabilityOverride;

  /// Loads one page of the append-only evidence trail (issue #2). Read-only:
  /// the section renders history and never writes. `capability == null` means
  /// all channels; paging via [offset].
  final Future<List<LearningObservationView>> Function({
    String? capability,
    int offset,
  })?
  onLoadEvidenceHistory;

  /// Persists the user definition and personal note.
  final Future<void> Function(String? definition, String? note)? onSaveContent;

  final Future<void> Function(
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  )?
  onCreateSenseFolder;
  final Future<void> Function(
    String id,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  )?
  onUpdateSenseFolder;
  final Future<void> Function(String id)? onDeleteSenseFolder;
  final Future<void> Function(String senseId, LexicalOccurrence occurrence)?
  onAssignSenseFolder;
  final Future<void> Function(String senseId, LexicalOccurrence occurrence)?
  onUnassignSenseFolder;

  /// Queues one clip (with its sentence anchor) into the sound review queue.
  final Future<void> Function(LexicalOccurrence occurrence)? onReviewClip;

  /// External reference lookup (e.g. YouGlish) — reference only, external
  /// results never become local practice material.
  final String? externalLookupUrl;
  final ValueChanged<String>? onOpenExternal;

  /// Dictionary-provider pronunciation audio, when a lookup produced one.
  final String? pronunciationAudioUrl;
  final ValueChanged<String>? onPlayPronunciationAudio;

  /// Synthetic speech is a supplemental rendering of the supplied text. It
  /// never replaces a real media slice or becomes learning evidence.
  final void Function(String text, String purpose)? onSpeakSynthetic;
  final bool speechBusy;

  /// The request limit used by [onSearchLibrary]; hitting it means the
  /// results were sampled, which the coverage-honest UI must say.
  final int libraryResultLimit;

  @override
  State<ListeningDictionaryEntryView> createState() =>
      _ListeningDictionaryEntryViewState();
}

class _ListeningDictionaryEntryViewState
    extends State<ListeningDictionaryEntryView> {
  // Clip UI state is keyed by a durable occurrence identity, not list index,
  // so re-sorting by speech rate cannot misattribute reveals or marks.
  final Set<String> _revealed = {};
  final Set<String> _submitting = {};
  final Map<String, bool> _marks = {};
  bool _sortByRate = false;
  List<CorpusOccurrence>? _libraryResults;
  bool _searchingLibrary = false;
  final Set<String> _collected = {};
  final Set<String> _collecting = {};
  late final TextEditingController _definition;
  late final TextEditingController _note;
  bool _savingContent = false;
  bool _savingSenseFolder = false;
  LexicalOccurrence? _activeOccurrence;
  final PageController _clipPageController = PageController();

  LexicalEntry get entry => widget.details.entry;

  @override
  void initState() {
    super.initState();
    _definition = TextEditingController(text: entry.userDefinition ?? '');
    _note = TextEditingController(text: entry.personalNote ?? '');
  }

  @override
  void didUpdateWidget(covariant ListeningDictionaryEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.entry.userDefinition != entry.userDefinition) {
      _definition.text = entry.userDefinition ?? '';
    }
    if (oldWidget.details.entry.personalNote != entry.personalNote) {
      _note.text = entry.personalNote ?? '';
    }
  }

  @override
  void dispose() {
    _clipPageController.dispose();
    _definition.dispose();
    _note.dispose();
    super.dispose();
  }

  String _clipKey(LexicalOccurrence occurrence) =>
      '${occurrence.mediaFingerprintSnapshot}'
      ':${occurrence.startMsSnapshot}'
      ':${occurrence.sentenceId ?? occurrence.sentenceTextSnapshot}';

  Future<void> _mark(
    String key,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    setState(() => _submitting.add(key));
    final saved = await widget.onMark(occurrence, heard);
    if (!mounted) return;
    setState(() {
      _submitting.remove(key);
      if (saved) _marks[key] = heard;
    });
  }

  Future<void> _searchLibrary() async {
    final search = widget.onSearchLibrary;
    if (search == null) return;
    setState(() => _searchingLibrary = true);
    List<CorpusOccurrence> results;
    try {
      results = await search();
    } catch (_) {
      results = const [];
    }
    if (!mounted) return;
    // A context the learner already saved as a durable slice is not "more".
    final knownSentences = widget.details.occurrences
        .map((occurrence) => occurrence.sentenceId)
        .whereType<String>()
        .toSet();
    setState(() {
      _searchingLibrary = false;
      _libraryResults = results
          .where(
            (result) =>
                result.sentenceId == null ||
                !knownSentences.contains(result.sentenceId),
          )
          .toList(growable: false);
    });
  }

  Future<void> _collect(CorpusOccurrence occurrence) async {
    final collect = widget.onCollectCorpus;
    if (collect == null) return;
    setState(() => _collecting.add(occurrence.id));
    final saved = await collect(occurrence);
    if (!mounted) return;
    setState(() {
      _collecting.remove(occurrence.id);
      if (saved) _collected.add(occurrence.id);
    });
  }

  Future<void> _saveContent() async {
    final save = widget.onSaveContent;
    if (save == null) return;
    setState(() => _savingContent = true);
    final definition = _definition.text.trim();
    final note = _note.text.trim();
    await save(
      definition.isEmpty ? null : definition,
      note.isEmpty ? null : note,
    );
    if (mounted) setState(() => _savingContent = false);
  }

  void _play(LexicalOccurrence occurrence) {
    widget.onPlay(occurrence);
    setState(() => _activeOccurrence = occurrence);
  }

  void _selectClip(List<LexicalOccurrence> occurrences, int index) {
    if (index < 0 || index >= occurrences.length) return;
    _play(occurrences[index]);
    if (_clipPageController.hasClients) {
      unawaited(
        _clipPageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  List<LexicalOccurrence> _sortedOccurrences() {
    final occurrences = widget.details.occurrences;
    if (!_sortByRate) return occurrences;
    final sorted = occurrences.toList();
    int rateOf(LexicalOccurrence occurrence) =>
        clipSpeechRateWpm(
          occurrence.sentenceTextSnapshot,
          occurrence.startMsSnapshot,
          occurrence.endMsSnapshot,
        ) ??
        // Unmeasurable clips sink to the end instead of faking a speed.
        1 << 30;
    final rates = {
      for (final occurrence in sorted) _clipKey(occurrence): rateOf(occurrence),
    };
    sorted.sort((a, b) => rates[_clipKey(a)]!.compareTo(rates[_clipKey(b)]!));
    return sorted;
  }

  Set<String> get _assignedOccurrenceIds => {
    for (final folder in widget.details.senseFolders)
      for (final occurrence in folder.occurrences) occurrence.id,
  };

  Future<void> _editSenseFolder([LexicalSenseFolder? existing]) async {
    final result = await showDialog<_SenseFolderDraft>(
      context: context,
      builder: (context) => _SenseFolderDialog(existing: existing),
    );
    if (result == null) return;
    setState(() => _savingSenseFolder = true);
    try {
      if (existing == null) {
        await widget.onCreateSenseFolder?.call(
          result.label,
          result.definition,
          result.gloss,
          result.externalRef,
        );
      } else {
        await widget.onUpdateSenseFolder?.call(
          existing.id,
          result.label,
          result.definition,
          result.gloss,
          result.externalRef,
        );
      }
    } finally {
      if (mounted) setState(() => _savingSenseFolder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final occurrences = _sortedOccurrences();
    final productionDocuments = <String, ProductionCorpusHitView>{};
    for (final hit
        in widget.productionHits ?? const <ProductionCorpusHitView>[]) {
      productionDocuments.putIfAbsent(hit.document.id, () => hit);
    }
    final unassignedOccurrences = occurrences
        .where((occurrence) => !_assignedOccurrenceIds.contains(occurrence.id))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          entry.displayForm,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: ListenSpacing.gap6),
        Text(
          entry.kind == 'phrase'
              ? l.text('dictionaryPhrase')
              : l.text('dictionaryWord'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ListenSpacing.gap16),
        for (final suggestion in widget.suggestions)
          _SuggestionBanner(
            suggestion: suggestion,
            onConfirm: widget.onConfirmSuggestion,
            onReject: widget.onRejectSuggestion,
          ),
        _CapabilityEditor(
          profile: widget.details.capabilityProfile,
          onOverride: widget.onCapabilityOverride,
        ),
        // Evidence & history (issue #2) sits directly under the capability
        // status it explains, but is its own layer: suggestions above say
        // "what to do next", this says "what actually happened".
        if (widget.onLoadEvidenceHistory != null) ...[
          const SizedBox(height: ListenSpacing.gap12),
          _EvidenceHistorySection(
            key: ValueKey('evidence-${widget.details.entry.id}'),
            loader: widget.onLoadEvidenceHistory!,
          ),
        ],
        if (widget.onSaveContent != null) ...[
          const SizedBox(height: ListenSpacing.gap12),
          _contentEditor(l),
        ],
        if (widget.onCreateSenseFolder != null) ...[
          const SizedBox(height: ListenSpacing.gap16),
          _senseFolderSection(l),
        ],
        if (widget.showProductionCorpus) ...[
          const SizedBox(height: ListenSpacing.gap16),
          Text(
            l.text('myOutput'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ListenSpacing.gap4),
          if (widget.productionHits == null && !widget.productionLoadFailed)
            const LinearProgressIndicator()
          else if (widget.productionLoadFailed)
            Text(
              l.text('myOutputUnavailable'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else if (widget.productionHits!.isEmpty)
            Text(
              l.text('myOutputEmpty'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              l
                  .text(
                    widget.productionHits!.length == 1
                        ? 'myOutputCountOne'
                        : 'myOutputCount',
                  )
                  .replaceAll('{count}', '${widget.productionHits!.length}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            for (final hit in productionDocuments.values)
              ListTile(
                key: ValueKey('production-output-${hit.document.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  hit.document.responseText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_assistanceLabel(l, hit.document.assistance)} · '
                  '${l.text('revision')} ${hit.document.responseRevision}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (widget.onSpeakSynthetic != null)
                      PronunciationButton(
                        key: ValueKey('production-speech-${hit.document.id}'),
                        tooltip: l.text('readAloudSynthetic'),
                        busy: widget.speechBusy,
                        synthetic: true,
                        onPressed: () => widget.onSpeakSynthetic!(
                          hit.document.responseText,
                          'production_corpus_readback',
                        ),
                      ),
                    const Icon(Icons.open_in_new),
                  ],
                ),
                onTap: widget.onOpenProductionAttempt == null
                    ? null
                    : () => widget.onOpenProductionAttempt!(hit),
              ),
          ],
        ],
        const SizedBox(height: ListenSpacing.gap16),
        Row(
          children: [
            Expanded(
              child: Text(
                l.text('dictionaryClips'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (occurrences.length > 1)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l.text('dictionarySortDefault')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l.text('dictionarySortByRate')),
                  ),
                ],
                selected: {_sortByRate},
                onSelectionChanged: (value) =>
                    setState(() => _sortByRate = value.first),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l
              .text('dictionaryCoverage')
              .replaceAll('{count}', '${occurrences.length}'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        if (unassignedOccurrences.isNotEmpty)
          Text(
            l.text('dictionaryUnassignedClips'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        if (_activeOccurrence != null && widget.slicePlayer != null)
          DictionaryInlineClipPlayer(
            controller: widget.slicePlayer!,
            occurrence: _activeOccurrence!,
            target: _activeOccurrence!.originalForm ?? entry.displayForm,
            onShadowing: widget.onShadowing == null
                ? null
                : () => widget.onShadowing!(_activeOccurrence!),
            onClose: () {
              unawaited(widget.slicePlayer!.close());
              setState(() => _activeOccurrence = null);
            },
          ),
        if (occurrences.isNotEmpty)
          Focus(
            autofocus: _activeOccurrence != null,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.space) {
                unawaited(widget.slicePlayer?.togglePlayback());
                return KeyEventResult.handled;
              }
              final current = _activeOccurrence == null
                  ? 0
                  : occurrences.indexWhere(
                      (item) => item.id == _activeOccurrence!.id,
                    );
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _selectClip(
                  occurrences,
                  current <= 0 ? occurrences.length - 1 : current - 1,
                );
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _selectClip(
                  occurrences,
                  current >= occurrences.length - 1 ? 0 : current + 1,
                );
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              key: const Key('dictionary-clip-rail'),
              height: 112,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _selectClip(
                      occurrences,
                      _activeOccurrence == null
                          ? 0
                          : (occurrences.indexWhere(
                                      (item) =>
                                          item.id == _activeOccurrence!.id,
                                    ) -
                                    1) %
                                occurrences.length,
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _clipPageController,
                      itemCount: occurrences.length,
                      onPageChanged: (index) => _play(occurrences[index]),
                      itemBuilder: (context, index) {
                        final occurrence = occurrences[index];
                        final selected = _activeOccurrence?.id == occurrence.id;
                        final key = _clipKey(occurrence);
                        final revealed = _revealed.contains(key);
                        final wpm = clipSpeechRateWpm(
                          occurrence.sentenceTextSnapshot,
                          occurrence.startMsSnapshot,
                          occurrence.endMsSnapshot,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Card(
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () =>
                                        _selectClip(occurrences, index),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            revealed
                                                ? occurrence
                                                      .sentenceTextSnapshot
                                                : l.text(
                                                    'dictionaryRevealSentence',
                                                  ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(
                                            height: ListenSpacing.gap4,
                                          ),
                                          Text(
                                            '${wpm == null ? '' : l.text('dictionaryWpm').replaceAll('{wpm}', '$wpm')} · ${index + 1}/${occurrences.length}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: l.text('dictionaryRevealSentence'),
                                  onPressed: () =>
                                      setState(() => _revealed.add(key)),
                                  icon: const Icon(Icons.visibility_outlined),
                                ),
                                if (widget.onReviewClip != null)
                                  IconButton(
                                    tooltip: l.text('dictionaryReviewClip'),
                                    onPressed: () => unawaited(
                                      widget.onReviewClip!(occurrence),
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_add_outlined,
                                    ),
                                  ),
                                IconButton.filledTonal(
                                  tooltip: l.text('dictionaryPlayClip'),
                                  onPressed: () =>
                                      _selectClip(occurrences, index),
                                  icon: const Icon(Icons.headphones_outlined),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () => _selectClip(
                      occurrences,
                      _activeOccurrence == null
                          ? 0
                          : (occurrences.indexWhere(
                                      (item) =>
                                          item.id == _activeOccurrence!.id,
                                    ) +
                                    1) %
                                occurrences.length,
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
        if (occurrences.isNotEmpty) const SizedBox(height: ListenSpacing.gap8),
        if (occurrences.isEmpty)
          _EmptyClips(entry: entry, external: _externalRow(l))
        else if (unassignedOccurrences.isEmpty)
          Text(
            l.text('dictionaryNoClips'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (widget.onSearchLibrary != null) ..._librarySection(l),
      ],
    );
  }

  String _assistanceLabel(AppLocalizations l, String value) => switch (value) {
    'content_anchored' => l.text('productionAssistanceContent'),
    'source_reconstruction' => l.text('productionAssistanceReconstruction'),
    'learner_revision' => l.text('productionAssistanceRevision'),
    'explicit_target' => l.text('productionAssistanceTarget'),
    'model_suggested' => l.text('productionAssistanceModel'),
    'direct_imitation' => l.text('productionAssistanceImitation'),
    _ => l.text('productionAssistanceUnknown'),
  };

  Widget _senseFolderSection(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              l.text('dictionarySenseFolders'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: l.text('dictionaryAddSenseFolder'),
            onPressed: _savingSenseFolder
                ? null
                : () => unawaited(_editSenseFolder()),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      Text(
        l.text('dictionarySenseFoldersHint'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      if (widget.details.senseFolders.isEmpty)
        Text(
          l.text('dictionaryNoSenseFolders'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      else
        for (final details in widget.details.senseFolders)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(details.folder.label),
            subtitle: Text(
              [
                ?details.folder.definition,
                l
                    .text('dictionarySenseFolderClipCount')
                    .replaceAll('{count}', '${details.occurrences.length}'),
              ].join(' · '),
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: l.text('edit'),
                  onPressed: _savingSenseFolder
                      ? null
                      : () => unawaited(_editSenseFolder(details.folder)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: l.text('delete'),
                  onPressed:
                      _savingSenseFolder || widget.onDeleteSenseFolder == null
                      ? null
                      : () => unawaited(
                          widget.onDeleteSenseFolder!(details.folder.id),
                        ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            children: [
              if (details.occurrences.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l.text('dictionarySenseFolderEmpty')),
                )
              else
                for (final occurrence in details.occurrences)
                  _clipWithSenseAction(occurrence, l, details.folder.id),
            ],
          ),
    ],
  );

  Widget _clipWithSenseAction(
    LexicalOccurrence occurrence,
    AppLocalizations l,
    String? assignedSenseId,
  ) => Column(
    children: [
      _clipTile(occurrence, l),
      if (widget.onAssignSenseFolder != null &&
          widget.details.senseFolders.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            tooltip: l.text('dictionaryAssignSenseFolder'),
            onSelected: (value) => value == assignedSenseId
                ? unawaited(
                    widget.onUnassignSenseFolder?.call(value, occurrence),
                  )
                : unawaited(widget.onAssignSenseFolder!(value, occurrence)),
            itemBuilder: (context) => [
              for (final folder in widget.details.senseFolders)
                PopupMenuItem(
                  value: folder.folder.id,
                  child: Text(
                    folder.folder.id == assignedSenseId
                        ? l
                              .text('dictionaryUnassignSenseFolder')
                              .replaceAll('{label}', folder.folder.label)
                        : folder.folder.label,
                  ),
                ),
            ],
            child: TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.folder_outlined, size: 16),
              label: Text(
                assignedSenseId == null
                    ? l.text('dictionaryAssignSenseFolder')
                    : l.text('dictionaryAssignedSenseFolder'),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _clipTile(LexicalOccurrence occurrence, AppLocalizations l) {
    final key = _clipKey(occurrence);
    final wpm = clipSpeechRateWpm(
      occurrence.sentenceTextSnapshot,
      occurrence.startMsSnapshot,
      occurrence.endMsSnapshot,
    );
    return _ClipTile(
      occurrence: occurrence,
      target: occurrence.originalForm ?? entry.displayForm,
      wpmLabel: wpm == null
          ? null
          : l.text('dictionaryWpm').replaceAll('{wpm}', '$wpm'),
      revealed: _revealed.contains(key),
      submitting: _submitting.contains(key),
      mark: _marks[key],
      onReveal: () => setState(() => _revealed.add(key)),
      onPlay: () => _play(occurrence),
      onReview: widget.onReviewClip == null
          ? null
          : () => unawaited(widget.onReviewClip!(occurrence)),
      onHeard: occurrence.sentenceId == null
          ? null
          : () => _mark(key, occurrence, true),
      onNotHeard: occurrence.sentenceId == null
          ? null
          : () => _mark(key, occurrence, false),
    );
  }

  Widget _contentEditor(AppLocalizations l) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    shape: const Border(),
    title: Text(
      l.text('dictionaryContentSection'),
      style: Theme.of(context).textTheme.titleSmall,
    ),
    children: [
      TextField(
        key: const Key('dictionary-user-definition'),
        controller: _definition,
        decoration: InputDecoration(
          isDense: true,
          labelText: l.text('userDefinition'),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      TextField(
        key: const Key('dictionary-personal-note'),
        controller: _note,
        decoration: InputDecoration(
          isDense: true,
          labelText: l.text('personalNote'),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: _savingContent ? null : () => unawaited(_saveContent()),
          child: Text(l.text('save')),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
    ],
  );

  /// External references honour the copyright guardrail: links and dictionary
  /// audio only, never downloaded or treated as local practice material.
  Widget? _externalRow(AppLocalizations l) {
    final url = widget.externalLookupUrl;
    final audio = widget.pronunciationAudioUrl;
    final openExternal = widget.onOpenExternal;
    final hasLink = url != null && openExternal != null;
    final canPlayAudio =
        audio != null && widget.onPlayPronunciationAudio != null;
    final canSynthesize = audio == null && widget.onSpeakSynthetic != null;
    if (!hasLink && !canPlayAudio && !canSynthesize) return null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          l.text('dictionaryExternalHint'),
          style: ListenType.body.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (canPlayAudio)
          PronunciationButton(
            tooltip: l.text('pronunciation'),
            busy: widget.speechBusy,
            onPressed: () => widget.onPlayPronunciationAudio!(audio),
          )
        else if (canSynthesize)
          PronunciationButton(
            tooltip: l.text('dictionarySyntheticFallback'),
            busy: widget.speechBusy,
            synthetic: true,
            onPressed: () => widget.onSpeakSynthetic!(
              entry.displayForm,
              'dictionary_pronunciation_fallback',
            ),
          ),
        if (hasLink)
          OutlinedButton.icon(
            onPressed: () => openExternal(url),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.text('dictionaryYouglish')),
          ),
      ],
    );
  }

  List<Widget> _librarySection(AppLocalizations l) {
    final results = _libraryResults;
    final external = _externalRow(l);
    return [
      const SizedBox(height: ListenSpacing.gap16),
      Text(
        l.text('dictionaryLibrarySection'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: ListenSpacing.gap8),
      if (results == null)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _searchingLibrary
                ? null
                : () => unawaited(_searchLibrary()),
            icon: _searchingLibrary
                ? const ListenLoading.inline(size: 16)
                : const Icon(Icons.travel_explore_outlined, size: 18),
            label: Text(l.text('dictionaryFindMore')),
          ),
        )
      else if (results.isEmpty) ...[
        Text(
          l.text('dictionaryNoLibraryResults'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (external != null) ...[
          const SizedBox(height: ListenSpacing.gap8),
          external,
        ],
      ] else ...[
        if (results.length >= widget.libraryResultLimit) ...[
          Text(
            l
                .text('dictionarySampledHint')
                .replaceAll('{count}', '${widget.libraryResultLimit}'),
            style: ListenType.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        for (final result in results)
          CorpusResultTile(
            occurrence: result,
            target: entry.displayForm,
            onPlay: widget.onPlayCorpus == null || result.mediaId == null
                ? null
                : () => widget.onPlayCorpus!(result),
            collected: _collected.contains(result.id),
            collecting: _collecting.contains(result.id),
            onCollect:
                widget.onCollectCorpus == null ||
                    result.mediaId == null ||
                    result.sentenceId == null
                ? null
                : () => unawaited(_collect(result)),
          ),
      ],
    ];
  }
}

/// One pending listening upgrade suggestion with its evidence count and the
/// confirm/defer resolution actions (restored from the pre-dictionary detail
/// dialog).
/// Issue #2: the user-readable evidence trail. Strictly read-only — it renders
/// what the append-only observation store says and never writes back.
/// Collapsed by default so the capability summary stays the first read;
/// expanding is the explicit "show me the evidence" act (the system's
/// knowledge waits for the user to come look, it never pushes).
class _EvidenceHistorySection extends StatefulWidget {
  const _EvidenceHistorySection({super.key, required this.loader});

  final Future<List<LearningObservationView>> Function({
    String? capability,
    int offset,
  })
  loader;

  @override
  State<_EvidenceHistorySection> createState() =>
      _EvidenceHistorySectionState();
}

class _EvidenceHistorySectionState extends State<_EvidenceHistorySection> {
  /// Mirrors the server's default page size; a full page means there may be
  /// earlier evidence to fetch.
  static const _pageSize = 50;

  bool expanded = false;
  bool loading = false;
  bool loadFailed = false;

  /// `null` selects all channels.
  String? capability;

  /// `null` while never loaded; an empty list is an honest no-evidence state.
  List<LearningObservationView>? rows;
  bool maybeMore = false;

  Future<void> _load({required int offset}) async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final page = await widget.loader(capability: capability, offset: offset);
      if (!mounted) return;
      setState(() {
        loading = false;
        rows = offset == 0 ? page : [...?rows, ...page];
        maybeMore = page.length >= _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadFailed = true;
      });
    }
  }

  void _toggle() {
    setState(() => expanded = !expanded);
    if (expanded && rows == null && !loading) unawaited(_load(offset: 0));
  }

  void _selectCapability(String? value) {
    if (value == capability) return;
    setState(() {
      capability = value;
      rows = null;
      maybeMore = false;
    });
    unawaited(_load(offset: 0));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.history_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Text(
                  l.text('evidenceHistoryTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: ListenSpacing.gap8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in const [
                (null, 'evidenceFilterAll'),
                ('listening', 'capabilityListening'),
                ('reading', 'capabilityReading'),
                ('speaking', 'capabilitySpeaking'),
                ('writing', 'capabilityWriting'),
              ])
                ChoiceChip(
                  label: Text(l.text(option.$2)),
                  selected: capability == option.$1,
                  onSelected: (_) => _selectCapability(option.$1),
                ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap8),
          if (loading && rows == null) const LinearProgressIndicator(),
          if (loadFailed)
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.text('evidenceHistoryLoadFailed'),
                    style: TextStyle(color: colors.error),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_load(offset: rows?.length ?? 0)),
                  child: Text(l.text('retry')),
                ),
              ],
            ),
          if (rows != null && rows!.isEmpty && !loading && !loadFailed)
            Text(
              l.text('evidenceHistoryEmpty'),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          if (rows != null)
            for (final row in rows!) _EvidenceRow(observation: row),
          if (maybeMore && !loading && !loadFailed)
            TextButton(
              onPressed: () => unawaited(_load(offset: rows!.length)),
              child: Text(l.text('evidenceHistoryLoadMore')),
            ),
        ],
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.observation});

  final LearningObservationView observation;

  /// Localized label when the key is known; the raw wire value otherwise, so
  /// a future kind degrades to honest snake_case instead of a wrong label.
  static String _label(AppLocalizations l, String prefix, String value) {
    final key =
        '$prefix${value.split('_').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join()}';
    final resolved = l.text(key);
    return resolved == key ? value : resolved;
  }

  static String _formatTime(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final (outcomeIcon, outcomeColor) = switch (observation.outcome) {
      'success' => (Icons.check_circle_outline, colors.primary),
      'partial' => (Icons.remove_circle_outline, colors.onSurfaceVariant),
      _ => (Icons.highlight_off, colors.error),
    };
    final channelIcon = switch (observation.capability) {
      'listening' => Icons.hearing_outlined,
      'reading' => Icons.menu_book_outlined,
      'speaking' => Icons.record_voice_over_outlined,
      _ => Icons.edit_outlined,
    };
    final detail = [
      if (observation.surfaceForm != null &&
          observation.surfaceForm!.isNotEmpty)
        observation.surfaceForm!,
      _label(l, 'obsAssistance', observation.assistance),
      _label(l, 'obsOrigin', observation.origin),
      _formatTime(observation.occurredAtMs),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(channelIcon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: ListenSpacing.gap8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _label(l, 'obsTask', observation.taskType),
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: ListenSpacing.gap6),
                    Icon(outcomeIcon, size: 15, color: outcomeColor),
                    const SizedBox(width: ListenSpacing.gap2),
                    Text(
                      _label(l, 'obsOutcome', observation.outcome),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: outcomeColor),
                    ),
                  ],
                ),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionBanner extends StatelessWidget {
  const _SuggestionBanner({
    required this.suggestion,
    required this.onConfirm,
    required this.onReject,
  });

  final UpgradeSuggestion suggestion;
  final Future<void> Function(UpgradeSuggestion suggestion)? onConfirm;
  final Future<void> Function(UpgradeSuggestion suggestion)? onReject;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l
                  .text('dictionaryUpgradeSuggestion')
                  .replaceAll('{count}', '${suggestion.evidenceContextCount}'),
            ),
            const SizedBox(height: ListenSpacing.gap6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null)
                  TextButton(
                    onPressed: () => unawaited(onReject!(suggestion)),
                    child: Text(l.text('deferUpgrade')),
                  ),
                if (onConfirm != null)
                  FilledButton(
                    onPressed: () => unawaited(onConfirm!(suggestion)),
                    child: Text(l.text('confirmListeningAcquired')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One local-corpus hit: playable through the slice window and savable as a
/// durable source occurrence when its media link is still alive.
class CorpusResultTile extends StatelessWidget {
  const CorpusResultTile({
    super.key,
    required this.occurrence,
    required this.target,
    required this.onPlay,
    required this.onCollect,
    this.collected = false,
    this.collecting = false,
  });

  final CorpusOccurrence occurrence;
  final String target;
  final VoidCallback? onPlay;
  final VoidCallback? onCollect;
  final bool collected;
  final bool collecting;

  String _kindKey() => switch (occurrence.kind) {
    'chunk' => 'corpusKindChunk',
    'lexical' => 'corpusKindWord',
    _ => 'corpusKindSentence',
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final linked = occurrence.mediaId != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        title: _HighlightedSentence(
          sentence: occurrence.sourceSnapshot,
          target: target,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            [
              l.text(_kindKey()),
              formatDuration(Duration(milliseconds: occurrence.startMs)),
              if (!linked) l.text('dictionaryClipNeedsSource'),
            ].join(' · '),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (collected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: ListenColors.learningRecognized,
                ),
              )
            else if (onCollect != null)
              IconButton(
                tooltip: l.text('dictionaryCollect'),
                onPressed: collecting ? null : onCollect,
                icon: collecting
                    ? const ListenLoading.inline(size: 16)
                    : const Icon(Icons.bookmark_add_outlined),
              ),
            IconButton.filledTonal(
              tooltip: l.text('dictionaryPlayClip'),
              icon: Icon(linked ? Icons.headphones_outlined : Icons.link_off),
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyClips extends StatelessWidget {
  const _EmptyClips({required this.entry, this.external});

  final LexicalEntry entry;
  final Widget? external;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: ListenRadii.surfaceBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('dictionaryNoClips'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ListenSpacing.gap6),
            Text(
              l
                  .text('dictionaryNoClipsHint')
                  .replaceAll('{word}', entry.displayForm),
            ),
            if (external != null) ...[
              const SizedBox(height: ListenSpacing.gap12),
              external!,
            ],
          ],
        ),
      ),
    );
  }
}

class _SenseFolderDraft {
  const _SenseFolderDraft({
    required this.label,
    this.definition,
    this.gloss,
    this.externalRef,
  });

  final String label;
  final String? definition;
  final String? gloss;
  final String? externalRef;
}

class _SenseFolderDialog extends StatefulWidget {
  const _SenseFolderDialog({this.existing});

  final LexicalSenseFolder? existing;

  @override
  State<_SenseFolderDialog> createState() => _SenseFolderDialogState();
}

class _SenseFolderDialogState extends State<_SenseFolderDialog> {
  late final TextEditingController _label;
  late final TextEditingController _definition;
  late final TextEditingController _gloss;
  late final TextEditingController _externalRef;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _label = TextEditingController(text: value?.label ?? '');
    _definition = TextEditingController(text: value?.definition ?? '');
    _gloss = TextEditingController(text: value?.gloss ?? '');
    _externalRef = TextEditingController(text: value?.externalRef ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    _definition.dispose();
    _gloss.dispose();
    _externalRef.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l.text('dictionaryAddSenseFolder')
            : l.text('dictionaryEditSenseFolder'),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              controller: _label,
              decoration: InputDecoration(
                labelText: l.text('dictionarySenseFolderLabel'),
              ),
            ),
            TextField(
              controller: _definition,
              decoration: InputDecoration(
                labelText: l.text('dictionarySenseFolderDefinition'),
              ),
            ),
            TextField(
              controller: _gloss,
              decoration: InputDecoration(
                labelText: l.text('dictionarySenseFolderGloss'),
              ),
            ),
            TextField(
              controller: _externalRef,
              decoration: InputDecoration(
                labelText: l.text('dictionarySenseFolderExternalRef'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.text('close')),
        ),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            Navigator.pop(
              context,
              _SenseFolderDraft(
                label: label,
                definition: _optional(_definition),
                gloss: _optional(_gloss),
                externalRef: _optional(_externalRef),
              ),
            );
          },
          child: Text(l.text('save')),
        ),
      ],
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.occurrence,
    required this.target,
    required this.wpmLabel,
    required this.revealed,
    required this.submitting,
    required this.mark,
    required this.onReveal,
    required this.onPlay,
    required this.onReview,
    required this.onHeard,
    required this.onNotHeard,
  });

  final LexicalOccurrence occurrence;
  final String target;
  final String? wpmLabel;
  final bool revealed;
  final bool submitting;
  final bool? mark;
  final VoidCallback onReveal;
  final VoidCallback onPlay;
  final VoidCallback? onReview;
  final VoidCallback? onHeard;
  final VoidCallback? onNotHeard;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final linked = occurrence.mediaId != null;
    final status = linked
        ? l.text('dictionaryClipReady')
        : l.text('dictionaryClipNeedsSource');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        title: revealed
            ? _HighlightedSentence(
                sentence: occurrence.sentenceTextSnapshot,
                target: target,
              )
            : Text(l.text('dictionaryRevealSentence')),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  occurrence.mediaTitleSnapshot,
                  formatDuration(
                    Duration(milliseconds: occurrence.startMsSnapshot),
                  ),
                  ?wpmLabel,
                  status,
                ].join(' · '),
              ),
              if (revealed) ...[
                const SizedBox(height: ListenSpacing.gap8),
                if (mark != null)
                  Text(
                    l.text(
                      mark!
                          ? 'dictionaryMarkedHeard'
                          : 'dictionaryMarkedNotHeard',
                    ),
                    style: TextStyle(
                      color: mark!
                          ? ListenColors.learningRecognized
                          : Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (onHeard == null)
                  Text(
                    l.text('dictionaryMarkUnavailable'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: submitting ? null : onNotHeard,
                        icon: const Icon(
                          Icons.hearing_disabled_outlined,
                          size: 17,
                        ),
                        label: Text(l.text('dictionaryNotHeard')),
                      ),
                      FilledButton.icon(
                        onPressed: submitting ? null : onHeard,
                        icon: submitting
                            ? const ListenLoading.inline(size: 16)
                            : const Icon(Icons.hearing_outlined, size: 17),
                        label: Text(l.text('dictionaryHeard')),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        onTap: revealed ? null : onReveal,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!revealed)
              IconButton(
                tooltip: l.text('dictionaryRevealSentence'),
                icon: const Icon(Icons.visibility_outlined),
                onPressed: onReveal,
              ),
            if (onReview != null)
              IconButton(
                tooltip: l.text('dictionaryReviewClip'),
                icon: const Icon(Icons.playlist_add_outlined),
                onPressed: onReview,
              ),
            IconButton.filledTonal(
              tooltip: l.text('dictionaryPlayClip'),
              icon: Icon(linked ? Icons.headphones_outlined : Icons.link_off),
              // An unlinked snapshot can still be recovered through the shared
              // resolver (current media fingerprint or a user-selected file).
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedSentence extends StatelessWidget {
  const _HighlightedSentence({required this.sentence, required this.target});

  final String sentence;
  final String target;

  @override
  Widget build(BuildContext context) {
    final normalizedTarget = target.trim();
    final start = normalizedTarget.isEmpty
        ? -1
        : sentence.toLowerCase().indexOf(normalizedTarget.toLowerCase());
    if (start < 0) return Text(sentence);
    final end = start + normalizedTarget.length;
    return Text.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: sentence.substring(0, start)),
          TextSpan(
            text: sentence.substring(start, end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: sentence.substring(end)),
        ],
      ),
    );
  }
}

/// The four-channel snapshot, editable in place when [onOverride] is wired:
/// selecting a chip sets that channel's user override, re-selecting the
/// active one clears it (mirroring the side-panel pattern).
class _CapabilityEditor extends StatelessWidget {
  const _CapabilityEditor({required this.profile, this.onOverride});

  final LexicalCapabilityProfile? profile;
  final Future<void> Function(String capability, String? conclusion)?
  onOverride;

  static const _channels = [
    ('reading', 'capabilityReading', Icons.menu_book_outlined),
    ('listening', 'capabilityListening', Icons.hearing_outlined),
    ('speaking', 'capabilitySpeaking', Icons.record_voice_over_outlined),
    ('writing', 'capabilityWriting', Icons.edit_outlined),
  ];

  CapabilityDimensionState? _dimension(String channel) {
    final value = profile;
    if (value == null) return null;
    return switch (channel) {
      'reading' => value.reading,
      'listening' => value.listening,
      'speaking' => value.speaking,
      _ => value.writing,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The entry-scale portrait ring (#47): same graphic language as the
        // coach dashboard and the book list, ahead of the editable rows.
        Padding(
          padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
          child: CapabilityRing(
            assessments: capabilityProfileAssessments(profile),
            size: 44,
            withTooltip: true,
          ),
        ),
        for (final (channel, label, icon) in _channels)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: capabilityAssessmentColor(
                    Theme.of(context).colorScheme,
                    _dimension(channel)?.effectiveAssessment ?? 'unassessed',
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap8),
                SizedBox(
                  width: 72,
                  child: Text(l.text(label), style: ListenType.reading),
                ),
                for (final value in const ['acquired', 'not_acquired'])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(l.text(value), style: ListenType.body),
                      selected:
                          _dimension(channel)?.effectiveAssessment == value,
                      visualDensity: VisualDensity.compact,
                      onSelected: onOverride == null
                          ? null
                          : (_) => unawaited(
                              onOverride!(
                                channel,
                                _dimension(channel)?.effectiveAssessment ==
                                        value
                                    ? null
                                    : value,
                              ),
                            ),
                    ),
                  ),
                if ((_dimension(channel)?.effectiveAssessment ??
                        'unassessed') ==
                    'unassessed')
                  Text(
                    l.text('unassessed'),
                    style: ListenType.body.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (_dimension(channel)?.userOverride != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: 'User override',
                      child: Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
