import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/practice.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../utils/format_duration.dart';
import 'pronunciation_button.dart';

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

/// The first listening-dictionary detail surface.  It deliberately consumes
/// the durable lexical-asset snapshots first: an occurrence stays directly
/// under its entry (sense folders arrive in a later phase).  The optional
/// callbacks light up Slice 3/4 behaviour — corpus enrichment, capability
/// override editing, definition/note editing, upgrade-suggestion resolution,
/// per-clip review exits, and external reference fallbacks.
class ListeningDictionaryEntryView extends StatefulWidget {
  const ListeningDictionaryEntryView({
    super.key,
    required this.details,
    required this.onPlay,
    required this.onMark,
    this.onSearchLibrary,
    this.onPlayCorpus,
    this.onCollectCorpus,
    this.suggestions = const [],
    this.onConfirmSuggestion,
    this.onRejectSuggestion,
    this.onCapabilityOverride,
    this.onSaveContent,
    this.onReviewClip,
    this.externalLookupUrl,
    this.onOpenExternal,
    this.pronunciationAudioUrl,
    this.libraryResultLimit = 50,
  });

  final LexicalEntryDetails details;
  final ValueChanged<LexicalOccurrence> onPlay;
  final Future<bool> Function(LexicalOccurrence occurrence, bool heard) onMark;

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

  /// Persists the user definition and personal note.
  final Future<void> Function(String? definition, String? note)? onSaveContent;

  /// Queues one clip (with its sentence anchor) into the sound review queue.
  final Future<void> Function(LexicalOccurrence occurrence)? onReviewClip;

  /// External reference lookup (e.g. YouGlish) — reference only, external
  /// results never become local practice material.
  final String? externalLookupUrl;
  final ValueChanged<String>? onOpenExternal;

  /// Dictionary-provider pronunciation audio, when a lookup produced one.
  final String? pronunciationAudioUrl;

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final occurrences = _sortedOccurrences();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          entry.displayForm,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          entry.kind == 'phrase'
              ? l.text('dictionaryPhrase')
              : l.text('dictionaryWord'),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: ListenColors.muted),
        ),
        const SizedBox(height: 16),
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
        if (widget.onSaveContent != null) ...[
          const SizedBox(height: 12),
          _contentEditor(l),
        ],
        const SizedBox(height: 20),
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
        const SizedBox(height: 4),
        Text(
          l
              .text('dictionaryCoverage')
              .replaceAll('{count}', '${occurrences.length}'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ListenColors.muted),
        ),
        const SizedBox(height: 10),
        if (occurrences.isEmpty)
          _EmptyClips(entry: entry, external: _externalRow(l))
        else
          for (final occurrence in occurrences) _clipTile(occurrence, l),
        if (widget.onSearchLibrary != null) ..._librarySection(l),
      ],
    );
  }

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
      onPlay: () => widget.onPlay(occurrence),
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
      const SizedBox(height: 8),
      TextField(
        key: const Key('dictionary-personal-note'),
        controller: _note,
        decoration: InputDecoration(
          isDense: true,
          labelText: l.text('personalNote'),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: _savingContent ? null : () => unawaited(_saveContent()),
          child: Text(l.text('save')),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  /// External references honour the copyright guardrail: links and dictionary
  /// audio only, never downloaded or treated as local practice material.
  Widget? _externalRow(AppLocalizations l) {
    final url = widget.externalLookupUrl;
    final audio = widget.pronunciationAudioUrl;
    final openExternal = widget.onOpenExternal;
    final hasLink = url != null && openExternal != null;
    if (!hasLink && audio == null) return null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          l.text('dictionaryExternalHint'),
          style: const TextStyle(color: ListenColors.muted, fontSize: 12),
        ),
        if (audio != null) PronunciationButton(audioUrl: audio),
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
      const SizedBox(height: 18),
      Text(
        l.text('dictionaryLibrarySection'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      if (results == null)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _searchingLibrary
                ? null
                : () => unawaited(_searchLibrary()),
            icon: _searchingLibrary
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_outlined, size: 18),
            label: Text(l.text('dictionaryFindMore')),
          ),
        )
      else if (results.isEmpty) ...[
        Text(
          l.text('dictionaryNoLibraryResults'),
          style: const TextStyle(color: ListenColors.muted),
        ),
        if (external != null) ...[const SizedBox(height: 10), external],
      ] else ...[
        if (results.length >= widget.libraryResultLimit) ...[
          Text(
            l
                .text('dictionarySampledHint')
                .replaceAll('{count}', '${widget.libraryResultLimit}'),
            style: const TextStyle(color: ListenColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
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
            const SizedBox(height: 6),
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
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
        borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 6),
            Text(
              l
                  .text('dictionaryNoClipsHint')
                  .replaceAll('{word}', entry.displayForm),
            ),
            if (external != null) ...[const SizedBox(height: 12), external!],
          ],
        ),
      ),
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
                const SizedBox(height: 8),
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
                          : ListenColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (onHeard == null)
                  Text(
                    l.text('dictionaryMarkUnavailable'),
                    style: const TextStyle(color: ListenColors.muted),
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
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
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
            style: const TextStyle(
              color: ListenColors.primary,
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
      children: [
        for (final (channel, label, icon) in _channels)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: _color(
                    _dimension(channel)?.effectiveAssessment ?? 'unassessed',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    l.text(label),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                for (final value in const ['acquired', 'not_acquired'])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(
                        l.text(value),
                        style: const TextStyle(fontSize: 12),
                      ),
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
                    style: TextStyle(
                      fontSize: 12,
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

  Color _color(String assessment) => switch (assessment) {
    'acquired' => ListenColors.learningRecognized,
    'not_acquired' => ListenColors.accent,
    _ => ListenColors.muted,
  };
}
