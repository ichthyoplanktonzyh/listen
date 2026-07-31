import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/reading_controller.dart';
import '../../localization.dart';
import '../../models/reading.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';
import '../../theme/typography.dart';

enum ReadingLens { clean, reading, listening }

/// The reading posture surface (Phase 3.13). Replaces the player stage while
/// open: independent reading rhythm, paragraph layout, word taps into the
/// standard learning panel, and per-sentence replay through the slice window
/// so the primary playback position never moves.
class ReadingView extends StatefulWidget {
  const ReadingView({
    super.key,
    required this.controller,
    required this.wordEntries,
    required this.capabilityProfiles,
    required this.showStyles,
    required this.onWord,
    required this.onPlaySentence,
    required this.onPlayParagraph,
    this.onStartTask,
    this.onSaveSentencePattern,
    this.onOpenDiff,
    required this.onClose,
  });

  final ReadingController controller;
  final Map<String, LexicalEntry> wordEntries;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final bool showStyles;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(ReadingSentence sentence) onPlaySentence;
  final Future<void> Function(ReadingParagraph paragraph) onPlayParagraph;

  /// Opens the paragraph-task flow (Slice 3); null hides the task chip.
  final Future<void> Function(ReadingParagraph paragraph)? onStartTask;
  final Future<void> Function(ReadingSentence sentence)? onSaveSentencePattern;

  /// Opens the read-listen pairing card (Slice 4); null hides the chip.
  final Future<void> Function(ReadingParagraph paragraph)? onOpenDiff;
  final VoidCallback onClose;

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<ReadingView> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _paragraphKeys = {};
  String? _hoveredAnchor;
  ReadingLens _lens = ReadingLens.clean;
  bool _overviewVisible = false;

  ReadingState get _state => widget.controller.state;

  @override
  void initState() {
    super.initState();
    // Restore the reading cursor once paragraph heights exist.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnchor());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealAnchor() {
    if (!mounted) return;
    final anchor = _state.anchorCueId;
    if (anchor == null) return;
    final context = _paragraphKeys[anchor]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.15);
      return;
    }
    // Distant paragraphs are not built yet; jump proportionally, then let the
    // next frame fine-tune once the target is laid out.
    final index = _state.anchorParagraphIndex;
    final count = _state.paragraphs.length;
    if (count > 1 && _scroll.hasClients) {
      final target = _scroll.position.maxScrollExtent * (index / (count - 1));
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _paragraphKeys[anchor]?.currentContext;
        if (retry != null) Scrollable.ensureVisible(retry, alignment: 0.15);
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          _header(l, colors),
          if (_overviewVisible) _vocabularyOverview(context),
          Expanded(
            child: _state.paragraphs.isEmpty
                ? Center(
                    child: Text(
                      l.text('readingEmpty'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: ListenPadding.pageCompact,
                    itemCount: _state.paragraphs.length,
                    itemBuilder: (context, index) => Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        // 900 was the widest reading measure in the app and the
                        // only one above the 780 the charter calls comfortable;
                        // prose here is exactly what `contentColumnMax` is for.
                        constraints: const BoxConstraints(
                          maxWidth: ListenBreakpoints.contentColumnMax,
                        ),
                        child: _paragraph(context, _state.paragraphs[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppLocalizations l, ColorScheme colors) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < ListenBreakpoints.readingCompact;
        return Padding(
          // Asymmetric on purpose and kept that way: the row opens with a bare
          // `Icon` and closes with `IconButton`s that carry their own hit
          // padding, so an even inset would look off-centre. Only the numbers
          // move onto the ladder (20/10 → 16/8).
          padding: const EdgeInsets.fromLTRB(
            ListenSpacing.gap16,
            ListenSpacing.gap8,
            ListenSpacing.gap8,
            ListenSpacing.gap8,
          ),
          child: Row(
            children: [
              Icon(Icons.chrome_reader_mode_outlined, color: colors.primary),
              const SizedBox(width: ListenSpacing.gap8),
              Text(
                l.text('readingViewTitle'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (compact)
                IconButton(
                  key: const ValueKey('reading-vocabulary-overview'),
                  tooltip: l.text('readingVocabularyOverview'),
                  onPressed: () =>
                      setState(() => _overviewVisible = !_overviewVisible),
                  icon: const Icon(
                    Icons.analytics_outlined,
                    size: ListenIconSize.control,
                  ),
                )
              else
                TextButton.icon(
                  key: const ValueKey('reading-vocabulary-overview'),
                  onPressed: () =>
                      setState(() => _overviewVisible = !_overviewVisible),
                  icon: const Icon(
                    Icons.analytics_outlined,
                    size: ListenIconSize.control,
                  ),
                  label: Text(l.text('readingVocabularyOverview')),
                ),
              PopupMenuButton<ReadingLens>(
                key: const ValueKey('reading-lens-menu'),
                tooltip: l.text('readingLens'),
                initialValue: _lens,
                onSelected: (value) => setState(() => _lens = value),
                itemBuilder: (context) => [
                  for (final lens in ReadingLens.values)
                    PopupMenuItem(
                      value: lens,
                      child: Text(_lensLabel(l, lens)),
                    ),
                ],
                child: Padding(
                  padding: ListenPadding.row,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.filter_alt_outlined,
                        size: ListenIconSize.control,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: ListenSpacing.gap6),
                        Text(_lensLabel(l, _lens)),
                      ],
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: l.text(
                  _state.translationVisible
                      ? 'readingHideTranslation'
                      : 'readingShowTranslation',
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.translate,
                    color: _state.translationVisible
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  onPressed: () => widget.controller.setTranslationVisible(
                    !_state.translationVisible,
                  ),
                ),
              ),
              Tooltip(
                message: l.text('readingBackToPlayer'),
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _paragraph(BuildContext context, ReadingParagraph paragraph) {
    final colors = Theme.of(context).colorScheme;
    if (paragraph.nonSpeech) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap8),
        child: Center(
          child: Text(
            paragraph.sentences.single.text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final anchored = paragraph.anchorCueId == _state.anchorCueId;
    final active = anchored || paragraph.anchorCueId == _hoveredAnchor;
    final translation = _state.translationByAnchor[paragraph.anchorCueId];
    final composite = composeParagraphCue(paragraph);
    return KeyedSubtree(
      key: _paragraphKeys.putIfAbsent(paragraph.anchorCueId, GlobalKey.new),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredAnchor = paragraph.anchorCueId),
        onExit: (_) {
          if (_hoveredAnchor == paragraph.anchorCueId) {
            setState(() => _hoveredAnchor = null);
          }
        },
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.basic,
          onShowFocusHighlight: (focused) {
            if (focused) widget.controller.markPosition(paragraph.anchorCueId);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => widget.controller.markPosition(paragraph.anchorCueId),
            child: Container(
              key: ValueKey('reading-paragraph-${paragraph.anchorCueId}'),
              margin: const EdgeInsets.only(bottom: ListenSpacing.gap6),
              // One paragraph is the repeating unit a reader scans down, and
              // the 3pt anchor bar rides the left edge of this same inset.
              padding: ListenPadding.row,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: anchored ? colors.primary : Colors.transparent,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatDuration(paragraph.start),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ListenSpacing.gap4),
                  DefaultTextStyle.merge(
                    style: ListenType.title.copyWith(height: 1.65),
                    child: TokenLine(
                      cue: composite.cue,
                      profiles: widget.wordEntries,
                      capabilityProfiles: widget.capabilityProfiles,
                      capabilityDisplayChannel: switch (_lens) {
                        ReadingLens.reading => 'reading',
                        ReadingLens.listening => 'listening',
                        ReadingLens.clean => null,
                      },
                      showStyles: _lens != ReadingLens.clean,
                      baseColor: colors.onSurface,
                      fontSize: 16,
                      textAlign: TextAlign.start,
                      onWord: (token, _) {
                        final origin = composite.tokenOrigins[token.index];
                        if (origin == null) return Future.value();
                        return widget.onWord(origin.$2, origin.$1);
                      },
                    ),
                  ),
                  if (translation != null && _state.translationVisible) ...[
                    const SizedBox(height: ListenSpacing.gap6),
                    Text(
                      translation,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (active) _inlineToolbar(context, paragraph),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _lensLabel(AppLocalizations l, ReadingLens lens) =>
      l.text(switch (lens) {
        ReadingLens.clean => 'readingLensClean',
        ReadingLens.reading => 'readingLensReading',
        ReadingLens.listening => 'readingLensListening',
      });

  Widget _vocabularyOverview(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final words = <String>{};
    for (final paragraph in _state.paragraphs) {
      for (final sentence in paragraph.sentences) {
        for (final cue in sentence.cues) {
          for (final token in cue.tokens) {
            if (token.kind == 'word' && token.normalized != null) {
              words.add(token.normalized!);
            }
          }
        }
      }
    }
    var readingAssessed = 0;
    var listeningAssessed = 0;
    for (final word in words) {
      final profile = widget.capabilityProfiles[word];
      if (profile == null) continue;
      if (profile.reading.effectiveAssessment != 'unassessed') {
        readingAssessed++;
      }
      if (profile.listening.effectiveAssessment != 'unassessed') {
        listeningAssessed++;
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        // The strip's gutter must equal the prose list's, or the metrics sit
        // out of line with the paragraphs below them; only its depth is its
        // own, since a one-line strip does not want a page's vertical inset.
        padding: ListenPadding.pageCompact.copyWith(
          top: ListenSpacing.gap12,
          bottom: ListenSpacing.gap12,
        ),
        child: Wrap(
          spacing: ListenSpacing.gap24,
          runSpacing: 8,
          children: [
            _OverviewMetric(
              label: l.text('readingVocabularyUnique'),
              value: words.length,
            ),
            _OverviewMetric(
              label: l.text('readingVocabularyReadingAssessed'),
              value: readingAssessed,
            ),
            _OverviewMetric(
              label: l.text('readingVocabularyListeningAssessed'),
              value: listeningAssessed,
            ),
          ],
        ),
      ),
    );
  }

  /// A contextual toolbar appears only for hover, selection, or keyboard
  /// focus. Sentence replays are compact numbered actions instead of a
  /// permanent chip row competing with the prose.
  Widget _inlineToolbar(BuildContext context, ReadingParagraph paragraph) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: ListenSpacing.gap8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              TextButton.icon(
                key: ValueKey('reading-play-${paragraph.anchorCueId}'),
                icon: const Icon(
                  Icons.play_arrow,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('readingPlayParagraph')),
                onPressed: () {
                  widget.controller.noteSlicePlay(paragraph.anchorCueId);
                  unawaited(widget.onPlayParagraph(paragraph));
                },
              ),
              if (widget.onStartTask != null)
                IconButton(
                  key: ValueKey('reading-task-${paragraph.anchorCueId}'),
                  tooltip: l.text('readingTaskStart'),
                  icon: const Icon(
                    Icons.checklist_outlined,
                    size: ListenIconSize.control,
                  ),
                  onPressed: () => unawaited(widget.onStartTask!(paragraph)),
                ),
              if (widget.onOpenDiff != null)
                IconButton(
                  key: ValueKey('reading-diff-${paragraph.anchorCueId}'),
                  tooltip: l.text('readingDiffChip'),
                  icon: const Icon(
                    Icons.compare_arrows,
                    size: ListenIconSize.control,
                  ),
                  onPressed: () => unawaited(widget.onOpenDiff!(paragraph)),
                ),
              for (var i = 0; i < paragraph.sentences.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message:
                          '${l.text('readingPlaySentence')}: ${paragraph.sentences[i].text}',
                      child: TextButton.icon(
                        key: ValueKey(
                          'reading-sentence-${paragraph.anchorCueId}-$i',
                        ),
                        icon: const Icon(
                          Icons.volume_up_outlined,
                          size: ListenIconSize.control,
                        ),
                        label: Text('${i + 1}'),
                        onPressed: () {
                          widget.controller.noteSlicePlay(
                            paragraph.anchorCueId,
                          );
                          unawaited(
                            widget.onPlaySentence(paragraph.sentences[i]),
                          );
                        },
                      ),
                    ),
                    if (widget.onSaveSentencePattern != null)
                      IconButton(
                        key: ValueKey(
                          'reading-save-pattern-${paragraph.anchorCueId}-$i',
                        ),
                        tooltip: l.text('expressionSaveTitle'),
                        icon: const Icon(
                          Icons.bookmark_add_outlined,
                          size: ListenIconSize.control,
                        ),
                        onPressed: () => unawaited(
                          widget.onSaveSentencePattern!(paragraph.sentences[i]),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$value', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: ListenSpacing.gap6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
