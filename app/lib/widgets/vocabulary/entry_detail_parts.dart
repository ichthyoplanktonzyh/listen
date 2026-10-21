import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/capability_viz.dart';
import '../common/listen_loading.dart';

/// Issue #2: the user-readable evidence trail. Strictly read-only — it renders
/// what the append-only observation store says and never writes back.
/// Collapsed by default so the capability summary stays the first read;
/// expanding is the explicit "show me the evidence" act (the system's
/// knowledge waits for the user to come look, it never pushes).
class EntryEvidenceSection extends StatefulWidget {
  const EntryEvidenceSection({super.key, required this.loader});

  final Future<List<LearningObservationView>> Function({
    String? capability,
    int offset,
  })
  loader;

  @override
  State<EntryEvidenceSection> createState() => _EntryEvidenceSectionState();
}

class _EntryEvidenceSectionState extends State<EntryEvidenceSection> {
  /// Mirrors the server's default page size; a full page means there may be
  /// earlier evidence to fetch.
  static const _pageSize = 50;

  bool expanded = false;
  bool loading = false;
  bool loadFailed = false;

  /// `null` while never loaded; an empty list is an honest no-evidence state.
  List<LearningObservationView>? rows;
  bool maybeMore = false;

  Future<void> _load({required int offset}) async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final page = await widget.loader(capability: 'listening', offset: offset);
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
                  size: ListenIconSize.control,
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
    const channelIcon = Icons.hearing_outlined;
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
          Icon(
            channelIcon,
            size: ListenIconSize.control,
            color: colors.onSurfaceVariant,
          ),
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
                    Icon(
                      outcomeIcon,
                      size: ListenIconSize.inline,
                      color: outcomeColor,
                    ),
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
      margin: const EdgeInsets.only(bottom: ListenSpacing.gap8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: ListenPadding.row,
        title: _HighlightedSentence(
          sentence: occurrence.sourceSnapshot,
          target: target,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: ListenSpacing.gap4),
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
                  size: ListenIconSize.control,
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

class EntryEmptyClips extends StatelessWidget {
  const EntryEmptyClips({super.key, required this.entry, this.external});

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

class SenseFolderDraft {
  const SenseFolderDraft({
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

class SenseFolderDialog extends StatefulWidget {
  const SenseFolderDialog({super.key, this.existing});

  final LexicalSenseFolder? existing;

  @override
  State<SenseFolderDialog> createState() => _SenseFolderDialogState();
}

class _SenseFolderDialogState extends State<SenseFolderDialog> {
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
              SenseFolderDraft(
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

class EntryClipTile extends StatelessWidget {
  const EntryClipTile({
    super.key,
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
      margin: const EdgeInsets.only(bottom: ListenSpacing.gap8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: ListenPadding.row,
        title: revealed
            ? _HighlightedSentence(
                sentence: occurrence.sentenceTextSnapshot,
                target: target,
              )
            : Text(l.text('dictionaryRevealSentence')),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: ListenSpacing.gap4),
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
                    spacing: ListenSpacing.gap8,
                    runSpacing: ListenSpacing.gap4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: submitting ? null : onNotHeard,
                        icon: const Icon(
                          Icons.hearing_disabled_outlined,
                          size: ListenIconSize.control,
                        ),
                        label: Text(l.text('dictionaryNotHeard')),
                      ),
                      FilledButton.icon(
                        onPressed: submitting ? null : onHeard,
                        icon: submitting
                            ? const ListenLoading.inline(size: 16)
                            : const Icon(
                                Icons.hearing_outlined,
                                size: ListenIconSize.control,
                              ),
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

/// The manually editable listening conclusion for this lexical entry.
class EntryCapabilityEditor extends StatelessWidget {
  const EntryCapabilityEditor({
    super.key,
    required this.profile,
    this.onListeningOverride,
  });

  final LexicalCapabilityProfile? profile;
  final Future<void> Function(String? conclusion)? onListeningOverride;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final dimension = profile?.listening;
    final assessment = dimension?.effectiveAssessment ?? 'unassessed';
    final assessed = assessment == 'acquired' || assessment == 'not_acquired';
    return Row(
      children: [
        Icon(
          Icons.hearing_outlined,
          size: ListenIconSize.control,
          color: capabilityAssessmentColor(colors, assessment),
        ),
        const SizedBox(width: ListenSpacing.gap8),
        Expanded(
          child: Text(
            l.text('capabilityListening'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final value in const ['acquired', 'not_acquired'])
              ButtonSegment<String>(value: value, label: Text(l.text(value))),
          ],
          selected: assessed ? {assessment} : const <String>{},
          onSelectionChanged: onListeningOverride == null
              ? null
              : (selection) => unawaited(
                  onListeningOverride!(
                    selection.isEmpty ? null : selection.first,
                  ),
                ),
        ),
        if (dimension?.userOverride != null)
          Padding(
            padding: const EdgeInsets.only(left: ListenSpacing.gap4),
            child: Tooltip(
              message: l.text('capabilityUserOverride'),
              child: Icon(
                Icons.person_outline,
                size: ListenIconSize.inline,
                color: colors.outline,
              ),
            ),
          ),
      ],
    );
  }
}
