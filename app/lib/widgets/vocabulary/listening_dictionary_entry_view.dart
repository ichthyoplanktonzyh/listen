import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../utils/format_duration.dart';

/// The first listening-dictionary detail surface.  It deliberately consumes
/// the durable lexical-asset snapshots first: an occurrence stays directly
/// under its entry (sense folders arrive in a later phase).  The optional
/// library callbacks light up Slice 3 corpus enrichment — searching the
/// rebuildable local corpus for more example clips and saving one as a
/// durable source occurrence of this entry.
class ListeningDictionaryEntryView extends StatefulWidget {
  const ListeningDictionaryEntryView({
    super.key,
    required this.details,
    required this.onPlay,
    required this.onMark,
    this.onSearchLibrary,
    this.onPlayCorpus,
    this.onCollectCorpus,
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

  @override
  State<ListeningDictionaryEntryView> createState() =>
      _ListeningDictionaryEntryViewState();
}

class _ListeningDictionaryEntryViewState
    extends State<ListeningDictionaryEntryView> {
  final Set<int> _revealed = {};
  final Set<int> _submitting = {};
  final Map<int, bool> _marks = {};
  List<CorpusOccurrence>? _libraryResults;
  bool _searchingLibrary = false;
  final Set<String> _collected = {};
  final Set<String> _collecting = {};

  Future<void> _mark(
    int index,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    setState(() => _submitting.add(index));
    final saved = await widget.onMark(occurrence, heard);
    if (!mounted) return;
    setState(() {
      _submitting.remove(index);
      if (saved) _marks[index] = heard;
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.details.entry;
    final occurrences = widget.details.occurrences;
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
        _CapabilitySummary(profile: widget.details.capabilityProfile),
        const SizedBox(height: 20),
        Text(
          l.text('dictionaryClips'),
          style: Theme.of(context).textTheme.titleMedium,
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
          _EmptyClips(entry: entry)
        else
          for (final (index, occurrence) in occurrences.indexed)
            _ClipTile(
              occurrence: occurrence,
              target: occurrence.originalForm ?? entry.displayForm,
              revealed: _revealed.contains(index),
              submitting: _submitting.contains(index),
              mark: _marks[index],
              onReveal: () => setState(() => _revealed.add(index)),
              onPlay: () => widget.onPlay(occurrence),
              onHeard: occurrence.sentenceId == null
                  ? null
                  : () => _mark(index, occurrence, true),
              onNotHeard: occurrence.sentenceId == null
                  ? null
                  : () => _mark(index, occurrence, false),
            ),
        if (widget.onSearchLibrary != null) ..._librarySection(l),
      ],
    );
  }

  List<Widget> _librarySection(AppLocalizations l) {
    final results = _libraryResults;
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
      else if (results.isEmpty)
        Text(
          l.text('dictionaryNoLibraryResults'),
          style: const TextStyle(color: ListenColors.muted),
        )
      else
        for (final result in results)
          CorpusResultTile(
            occurrence: result,
            target: widget.details.entry.displayForm,
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
    ];
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
              Padding(
                padding: const EdgeInsets.only(right: 4),
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
  const _EmptyClips({required this.entry});

  final LexicalEntry entry;

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
    required this.revealed,
    required this.submitting,
    required this.mark,
    required this.onReveal,
    required this.onPlay,
    required this.onHeard,
    required this.onNotHeard,
  });

  final LexicalOccurrence occurrence;
  final String target;
  final bool revealed;
  final bool submitting;
  final bool? mark;
  final VoidCallback onReveal;
  final VoidCallback onPlay;
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

class _CapabilitySummary extends StatelessWidget {
  const _CapabilitySummary({required this.profile});

  final LexicalCapabilityProfile? profile;

  static const _channels = [
    ('reading', 'capabilityReading', Icons.menu_book_outlined),
    ('listening', 'capabilityListening', Icons.hearing_outlined),
    ('speaking', 'capabilitySpeaking', Icons.record_voice_over_outlined),
    ('writing', 'capabilityWriting', Icons.edit_outlined),
  ];

  String _assessment(String channel) {
    final value = profile;
    if (value == null) return 'unassessed';
    return switch (channel) {
      'reading' => value.reading.effectiveAssessment,
      'listening' => value.listening.effectiveAssessment,
      'speaking' => value.speaking.effectiveAssessment,
      _ => value.writing.effectiveAssessment,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (channel, label, icon) in _channels)
          Chip(
            avatar: Icon(icon, size: 17, color: _color(_assessment(channel))),
            label: Text('${l.text(label)} · ${l.text(_assessment(channel))}'),
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
