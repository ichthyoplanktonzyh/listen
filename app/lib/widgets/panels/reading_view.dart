import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/reading_controller.dart';
import '../../localization.dart';
import '../../models/reading.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';

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

  /// Opens the read-listen pairing card (Slice 4); null hides the chip.
  final Future<void> Function(ReadingParagraph paragraph)? onOpenDiff;
  final VoidCallback onClose;

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<ReadingView> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _paragraphKeys = {};

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
      final target =
          _scroll.position.maxScrollExtent * (index / (count - 1));
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    itemCount: _state.paragraphs.length,
                    itemBuilder: (context, index) =>
                        _paragraph(context, _state.paragraphs[index]),
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
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      child: Row(
        children: [
          Icon(Icons.chrome_reader_mode_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            l.text('readingViewTitle'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
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
    ),
  );

  Widget _paragraph(BuildContext context, ReadingParagraph paragraph) {
    final colors = Theme.of(context).colorScheme;
    if (paragraph.nonSpeech) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
    final translation = _state.translationByAnchor[paragraph.anchorCueId];
    final composite = composeParagraphCue(paragraph);
    return KeyedSubtree(
      key: _paragraphKeys.putIfAbsent(paragraph.anchorCueId, GlobalKey.new),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => widget.controller.markPosition(paragraph.anchorCueId),
        child: Container(
          key: ValueKey('reading-paragraph-${paragraph.anchorCueId}'),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
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
                      color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16, height: 1.65),
                child: TokenLine(
                  cue: composite.cue,
                  profiles: widget.wordEntries,
                  capabilityProfiles: widget.capabilityProfiles,
                  showStyles: widget.showStyles,
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
                const SizedBox(height: 6),
                Text(
                  translation,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (anchored) _sentenceChips(context, paragraph),
            ],
          ),
        ),
      ),
    );
  }

  /// Replay affordances for the anchored paragraph: whole paragraph plus one
  /// chip per sentence, all through the slice window (primary playback
  /// position stays untouched).
  Widget _sentenceChips(BuildContext context, ReadingParagraph paragraph) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    String label(ReadingSentence sentence) {
      final text = sentence.text;
      return text.length <= 26 ? text : '${text.substring(0, 26)}…';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ActionChip(
            avatar: Icon(Icons.play_arrow, size: 16, color: colors.primary),
            label: Text(l.text('readingPlayParagraph')),
            onPressed: () {
              widget.controller.noteSlicePlay(paragraph.anchorCueId);
              unawaited(widget.onPlayParagraph(paragraph));
            },
          ),
          if (widget.onStartTask != null)
            ActionChip(
              key: ValueKey('reading-task-${paragraph.anchorCueId}'),
              avatar: Icon(
                Icons.checklist_outlined,
                size: 16,
                color: colors.primary,
              ),
              label: Text(l.text('readingTaskStart')),
              onPressed: () => unawaited(widget.onStartTask!(paragraph)),
            ),
          if (widget.onOpenDiff != null)
            ActionChip(
              key: ValueKey('reading-diff-${paragraph.anchorCueId}'),
              avatar: Icon(
                Icons.compare_arrows,
                size: 16,
                color: colors.primary,
              ),
              label: Text(l.text('readingDiffChip')),
              onPressed: () => unawaited(widget.onOpenDiff!(paragraph)),
            ),
          for (final sentence in paragraph.sentences)
            ActionChip(
              avatar: Icon(
                Icons.volume_up_outlined,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              label: Text(label(sentence)),
              tooltip: l.text('readingPlaySentence'),
              onPressed: () {
                widget.controller.noteSlicePlay(paragraph.anchorCueId);
                unawaited(widget.onPlaySentence(sentence));
              },
            ),
        ],
      ),
    );
  }
}
