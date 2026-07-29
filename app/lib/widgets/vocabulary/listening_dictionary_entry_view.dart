import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/slice_player_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../models/production_corpus.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';
import '../common/listen_loading.dart';
import 'dictionary_inline_clip_player.dart';
import 'entry_detail_parts.dart';
import 'entry_section_anchors.dart';
import 'pronunciation_button.dart';
import '../../theme/typography.dart';

/// The leaf widgets of this surface live in `entry_detail_parts.dart`; the
/// corpus tile is re-exported so existing importers keep one entry point.
export 'entry_detail_parts.dart' show CorpusResultTile;

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
    this.suggestionsLoading = false,
    this.pronunciationLoading = false,
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

  /// True while the suggestion probe is still in flight. Decoration data
  /// announces its own waiting (#82 / V6) instead of holding the identity
  /// card hostage — an empty list with this false is an honest "none".
  final bool suggestionsLoading;

  /// True while the dictionary provider lookup that yields
  /// [pronunciationAudioUrl] is still in flight. Same rule as above: the
  /// pronunciation control waits by itself, nothing else does.
  final bool pronunciationLoading;
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

  /// The anchored sections scroll under a pinned identity card. One controller
  /// so an anchor tap can scroll, and so scrolling can report back which
  /// section is currently being read.
  final ScrollController _sectionScroll = ScrollController();
  final GlobalKey _scrollAreaKey = GlobalKey();

  /// Section anchor keys live here, one per section id, so they survive
  /// rebuilds. A global key rebuilt every frame would remount the section.
  final Map<String, GlobalKey> _anchorKeys = {};

  GlobalKey _anchorKey(String id) =>
      _anchorKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'section-$id'));

  /// The section whose top most recently passed the reading line. Null until
  /// the first layout resolves it.
  String? _activeSectionId;

  /// Rebuilt every frame from the widget's inputs, so the scroll listener
  /// always measures the sections that actually exist right now.
  List<EntryDetailSection> _sections = const [];

  LexicalEntry get entry => widget.details.entry;

  @override
  void initState() {
    super.initState();
    _definition = TextEditingController(text: entry.userDefinition ?? '');
    _note = TextEditingController(text: entry.personalNote ?? '');
    _sectionScroll.addListener(_syncActiveSection);
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
    _sectionScroll.removeListener(_syncActiveSection);
    _sectionScroll.dispose();
    _definition.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Scrolls [section] to the top of the reading area. An anchor, not a tab:
  /// the other sections stay built and stay reachable by scrolling past.
  void _goToSection(EntryDetailSection section) {
    final target = section.anchorKey.currentContext;
    if (target == null) return;
    setState(() => _activeSectionId = section.id);
    unawaited(
      Scrollable.ensureVisible(
        target,
        // Reduce motion jumps instead of gliding (charter motion discipline).
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : ListenMotion.base,
        curve: ListenMotion.move,
        alignment: 0,
      ),
    );
  }

  /// Reports which section the reader is currently in, so the anchor bar is a
  /// position readout rather than a click memory.
  void _syncActiveSection() {
    if (!mounted || _sections.isEmpty) return;
    final viewport = _scrollAreaKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    // The reading line sits a quarter down the viewport: whatever section has
    // crossed it is what the reader is looking at.
    final readingLine = viewport.size.height * 0.25;
    String? current;
    for (final section in _sections) {
      final target = section.anchorKey.currentContext?.findRenderObject();
      if (target is! RenderBox || !target.attached) continue;
      final top = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= readingLine) current = section.id;
    }
    current ??= _sections.first.id;
    if (current != _activeSectionId) {
      setState(() => _activeSectionId = current);
    }
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
    final result = await showDialog<SenseFolderDraft>(
      context: context,
      builder: (context) => SenseFolderDialog(existing: existing),
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

    // V4: the detail is an identity card plus five anchored sections, not one
    // eight-part scroll. Absent capabilities drop their section rather than
    // showing an empty anchor.
    _sections = [
      // Evidence is a fixed segment: the four-channel override lives here even
      // when no history loader is wired, so the conclusion is always editable
      // next to what it was drawn from.
      EntryDetailSection(
        id: 'evidence',
        anchorKey: _anchorKey('evidence'),
        label: l.text('dictionaryAnchorEvidence'),
        child: _evidenceSection(l),
      ),
      EntryDetailSection(
        id: 'clips',
        anchorKey: _anchorKey('clips'),
        label: l.text('dictionaryAnchorClips'),
        count: occurrences.isEmpty ? null : occurrences.length,
        child: _clipsSection(l, occurrences, unassignedOccurrences),
      ),
      if (widget.showProductionCorpus)
        EntryDetailSection(
          id: 'output',
          anchorKey: _anchorKey('output'),
          label: l.text('dictionaryAnchorOutput'),
          child: _outputSection(l, productionDocuments),
        ),
      if (widget.onCreateSenseFolder != null)
        EntryDetailSection(
          id: 'senses',
          anchorKey: _anchorKey('senses'),
          label: l.text('dictionaryAnchorSenses'),
          count: widget.details.senseFolders.isEmpty
              ? null
              : widget.details.senseFolders.length,
          child: _senseFolderSection(l),
        ),
      if (widget.onSaveContent != null)
        EntryDetailSection(
          id: 'notes',
          anchorKey: _anchorKey('notes'),
          label: l.text('dictionaryAnchorNotes'),
          child: _contentEditor(l),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // V6: the identity card is built from `details` alone, so it paints as
        // soon as the entry lands. Nothing below can delay it.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: _identityCard(l),
        ),
        // The suggestion banner stays pinned above the anchors (V4) and waits
        // for itself.
        if (widget.suggestionsLoading || widget.suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              24,
              ListenSpacing.gap12,
              24,
              0,
            ),
            child: _suggestionRegion(l),
          ),
        const SizedBox(height: ListenSpacing.gap8),
        EntrySectionAnchorBar(
          sections: _sections,
          activeId: _activeSectionId ?? _sections.first.id,
          onSelect: _goToSection,
        ),
        Expanded(
          child: SingleChildScrollView(
            key: _scrollAreaKey,
            controller: _sectionScroll,
            // Every section stays built (anchors, not tabs), so scrolling to
            // the last one is always possible and evidence stays readable
            // beside clips.
            padding: const EdgeInsets.fromLTRB(
              24,
              ListenSpacing.gap12,
              24,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in _sections)
                  Padding(
                    key: section.anchorKey,
                    padding: const EdgeInsets.only(bottom: ListenSpacing.gap24),
                    child: section.child,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Who this word is: the form, its kind, the four-channel ring. Built purely
  /// from `details`, which is why it never waits (#82 / V6).
  Widget _identityCard(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const Key('dictionary-identity-card'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.displayForm,
                // The one hero size on the ladder (22). It used to read
                // `headlineMedium`, an unmapped Material slot at 28/w400 —
                // two sizes above anything the type scale defines, which is
                // what made the word head shout at the source line beside it.
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: ListenSpacing.gap2),
              Row(
                children: [
                  Text(
                    entry.kind == 'phrase'
                        ? l.text('dictionaryPhrase')
                        : l.text('dictionaryWord'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap8),
                  _pronunciationControl(l),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: ListenSpacing.gap12),
        CapabilityRing(
          assessments: capabilityProfileAssessments(
            widget.details.capabilityProfile,
          ),
          size: 40,
          withTooltip: true,
        ),
      ],
    );
  }

  /// The dictionary audio decoration: it announces its own wait rather than
  /// holding the card, and degrades to synthetic speech or to nothing.
  Widget _pronunciationControl(AppLocalizations l) {
    if (widget.pronunciationLoading) {
      return Tooltip(
        message: l.text('dictionaryPronunciationLoading'),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: ListenSpacing.gap4),
          child: ListenLoading.inline(size: 16),
        ),
      );
    }
    final audio = widget.pronunciationAudioUrl;
    if (audio != null && widget.onPlayPronunciationAudio != null) {
      return PronunciationButton(
        tooltip: l.text('pronunciation'),
        busy: widget.speechBusy,
        onPressed: () => widget.onPlayPronunciationAudio!(audio),
      );
    }
    if (audio == null && widget.onSpeakSynthetic != null) {
      return PronunciationButton(
        tooltip: l.text('dictionarySyntheticFallback'),
        busy: widget.speechBusy,
        synthetic: true,
        onPressed: () => widget.onSpeakSynthetic!(
          entry.displayForm,
          'dictionary_pronunciation_fallback',
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// Pending upgrade suggestions, with their own waiting line.
  Widget _suggestionRegion(AppLocalizations l) {
    if (widget.suggestions.isEmpty) {
      return Row(
        key: const Key('dictionary-suggestions-loading'),
        children: [
          const ListenLoading.inline(size: 16),
          const SizedBox(width: ListenSpacing.gap8),
          Text(
            l.text('dictionarySuggestionsLoading'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final suggestion in widget.suggestions)
          EntrySuggestionBanner(
            suggestion: suggestion,
            onConfirm: widget.onConfirmSuggestion,
            onReject: widget.onRejectSuggestion,
          ),
      ],
    );
  }

  /// Section 1 · evidence: what actually happened, and the user's override of
  /// the conclusion drawn from it.
  Widget _evidenceSection(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.onLoadEvidenceHistory != null) ...[
        EntryEvidenceSection(
          key: ValueKey('evidence-${widget.details.entry.id}'),
          loader: widget.onLoadEvidenceHistory!,
        ),
        const SizedBox(height: ListenSpacing.gap12),
      ],
      EntryCapabilityEditor(
        profile: widget.details.capabilityProfile,
        onOverride: widget.onCapabilityOverride,
      ),
    ],
  );

  /// Section 2 · clips: the inline player, the keyboard-navigable rail and the
  /// library search — inherited unchanged from the pre-anchor detail.
  Widget _clipsSection(
    AppLocalizations l,
    List<LexicalOccurrence> occurrences,
    List<LexicalOccurrence> unassignedOccurrences,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          l
              .text('dictionaryCoverage')
              .replaceAll('{count}', '${occurrences.length}'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      if (unassignedOccurrences.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l.text('dictionaryUnassignedClips'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
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
      if (occurrences.isNotEmpty) _clipRail(l, occurrences),
      if (occurrences.isNotEmpty) const SizedBox(height: ListenSpacing.gap8),
      if (occurrences.isEmpty)
        EntryEmptyClips(entry: entry, external: _externalRow(l))
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

  /// The clip rail: arrow keys move between clips, space toggles playback.
  /// Behaviour is inherited verbatim — S4 only moved it into its section.
  Widget _clipRail(
    AppLocalizations l,
    List<LexicalOccurrence> occurrences,
  ) => Focus(
    autofocus: _activeOccurrence != null,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.space) {
        unawaited(widget.slicePlayer?.togglePlayback());
        return KeyEventResult.handled;
      }
      final current = _activeOccurrence == null
          ? 0
          : occurrences.indexWhere((item) => item.id == _activeOccurrence!.id);
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
                              (item) => item.id == _activeOccurrence!.id,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: ListenSpacing.gap4,
                  ),
                  child: Card(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectClip(occurrences, index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    revealed
                                        ? occurrence.sentenceTextSnapshot
                                        : l.text('dictionaryRevealSentence'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: ListenSpacing.gap4),
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
                          onPressed: () => setState(() => _revealed.add(key)),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        if (widget.onReviewClip != null)
                          IconButton(
                            tooltip: l.text('dictionaryReviewClip'),
                            onPressed: () =>
                                unawaited(widget.onReviewClip!(occurrence)),
                            icon: const Icon(Icons.playlist_add_outlined),
                          ),
                        IconButton.filledTonal(
                          tooltip: l.text('dictionaryPlayClip'),
                          onPressed: () => _selectClip(occurrences, index),
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
                              (item) => item.id == _activeOccurrence!.id,
                            ) +
                            1) %
                        occurrences.length,
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );

  /// Section 3 · my output: what the learner has actually produced with this
  /// word. `null` hits mean still loading; failure and emptiness stay
  /// distinguishable (V6 — this section waits alone).
  Widget _outputSection(
    AppLocalizations l,
    Map<String, ProductionCorpusHitView> productionDocuments,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.text('myOutput'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: ListenSpacing.gap4),
      if (widget.productionHits == null && !widget.productionLoadFailed)
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            key: const Key('dictionary-output-loading'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListenLoading.inline(size: 16),
              const SizedBox(width: ListenSpacing.gap8),
              Text(
                l.text('myOutputLoading'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        )
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
  );

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
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: ListenIconSize.control,
                  ),
                ),
                IconButton(
                  tooltip: l.text('delete'),
                  onPressed:
                      _savingSenseFolder || widget.onDeleteSenseFolder == null
                      ? null
                      : () => unawaited(
                          widget.onDeleteSenseFolder!(details.folder.id),
                        ),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: ListenIconSize.control,
                  ),
                ),
              ],
            ),
            children: [
              if (details.occurrences.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
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
              icon: const Icon(
                Icons.folder_outlined,
                size: ListenIconSize.control,
              ),
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
    return EntryClipTile(
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

  /// External references honour the copyright guardrail: a link out only,
  /// never downloaded or treated as local practice material.
  ///
  /// The pronunciation control moved to the identity card in S4 (#82) — it is
  /// part of who the word is, and it must not be gated behind an empty-clip
  /// state or a library search.
  Widget? _externalRow(AppLocalizations l) {
    final url = widget.externalLookupUrl;
    final openExternal = widget.onOpenExternal;
    if (url == null || openExternal == null) return null;
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
        OutlinedButton.icon(
          onPressed: () => openExternal(url),
          icon: const Icon(
            Icons.open_in_new,
            size: ListenIconSize.control,
          ),
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
                : const Icon(
                    Icons.travel_explore_outlined,
                    size: ListenIconSize.control,
                  ),
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
