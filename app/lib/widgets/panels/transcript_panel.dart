import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/transcript_translation.dart';
import '../subtitle/token_line.dart';

class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({
    super.key,
    required this.track,
    required this.scrollController,
    required this.currentCue,
    required this.wordEntries,
    this.capabilityProfiles = const {},
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
    this.onImportSubtitle,
    this.groupingMode = 'off',
    this.chunkPartitionsBySentence = const {},
    this.senseGroupsBySentence = const {},
    this.chunkDisplayStyle = 'capsule',
    this.onToggleAnalysis,
    this.analysisExpanded = false,
    this.analysis,
    this.translationMode = TranscriptTranslation.source,
    this.translationFor,
    this.hasTranslationTrack = false,
    this.onImportTranslation,
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final Cue? currentCue;
  final Map<String, LexicalEntry> wordEntries;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final bool showStyles;
  final Color baseColor;
  final String groupingMode;
  final Map<String, SentenceChunkPartition> chunkPartitionsBySentence;
  final Map<String, List<SenseGroup>> senseGroupsBySentence;
  final String chunkDisplayStyle;

  /// Opens a word. [anchor] is where the reader clicked, in global
  /// coordinates, so the lookup can surface as a bubble over that word instead
  /// of replacing this panel — which is what used to happen, and what cost the
  /// reader their place in the text every single time.
  final Future<void> Function(SubtitleToken token, Cue cue, Offset anchor)
  onWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function()? onImportSubtitle;

  /// Opens or closes the analysis of the current sentence. Null on hosts with
  /// no analysis wired, which hides the control rather than offering a dead
  /// one.
  final VoidCallback? onToggleAnalysis;
  final bool analysisExpanded;

  /// The analysis body, rendered inside the current sentence while
  /// [analysisExpanded]. It arrives built so this panel stays free of the
  /// eight controllers a diagnosis card reads from.
  final Widget? analysis;

  /// Which of the two tracks the transcript shows.
  final TranscriptTranslation translationMode;

  /// The translation of one sentence, or null when that sentence has none.
  /// Resolving it needs the secondary track and both offsets, which live on
  /// the subtitle controller, so the host supplies the lookup.
  final String? Function(Cue cue)? translationFor;

  /// Whether a secondary track is loaded at all. This is what separates
  /// "there is no translation for this file" — said once, at the top — from
  /// "this sentence has none", which is said per sentence.
  final bool hasTranslationTrack;
  final VoidCallback? onImportTranslation;

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final Map<String, GlobalKey> _cueKeys = {};
  bool _syncScheduled = false;
  // While true the current cue is kept in view automatically. A manual scroll
  // (drag or wheel) pauses following so the user can read elsewhere without
  // being yanked back; programmatic scrolls never trip this.
  bool _following = true;

  // Where the last press landed, in global coordinates. Word taps arrive from
  // `TokenLine` without a position — it is one `InkWell` per token inside a
  // `RichText` — so the panel records the press itself and hands the point on
  // as the bubble's anchor. Reading it here also means the anchor is the pixel
  // the user actually aimed at, not the centre of a word box.
  Offset _lastPressPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scheduleCurrentCueSync();
  }

  @override
  void didUpdateWidget(covariant TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) {
      _cueKeys.clear();
      // A new transcript resumes automatic following from the top.
      _following = true;
    }
    if (oldWidget.currentCue?.id != widget.currentCue?.id ||
        oldWidget.track?.id != widget.track?.id) {
      _scheduleCurrentCueSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final effectiveBaseColor = widget.baseColor.computeLuminance() > 0.75
        ? colors.onSurface
        : widget.baseColor;
    return Material(
      color: colors.surfaceContainerLowest,
      child: widget.track == null
          ? _TranscriptEmptyState(onImportSubtitle: widget.onImportSubtitle)
          : NotificationListener<ScrollNotification>(
              // A real user drag carries dragDetails; programmatic scrolls do
              // not, so this pauses following only on genuine interaction.
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _pauseFollowing();
                }
                return false;
              },
              child: Listener(
                onPointerDown: (event) => _lastPressPosition = event.position,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _pauseFollowing();
                },
                // A column, not a stack: the resume-following control is a
                // strip attached under the list instead of a pill floating on
                // top of it. The reference app floats it, and floating it
                // covers whichever sentence happens to be at the bottom-right
                // — a different one at every window height. A strip costs one
                // row and covers nothing, which is the better trade.
                child: Column(
                  children: [
                    // Said once, at the top, because it is a fact about the
                    // file. Repeating it under all 200 sentences would be the
                    // same fact 200 times, and would drown the sentences that
                    // genuinely have no line of their own.
                    if (widget.translationMode.showsTranslation &&
                        !widget.hasTranslationTrack)
                      _NoTranslationTrackNotice(
                        message: l.text('noTranslationTrack'),
                        actionLabel: l.text('importSubtitle'),
                        onImport: widget.onImportTranslation,
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: ListenSpacing.gap8,
                        ),
                        itemCount: widget.track!.cues.length,
                        itemBuilder: (context, index) {
                          final cue = widget.track!.cues[index];
                          final selected = cue.id == widget.currentCue?.id;
                          return KeyedSubtree(
                            key: _keyFor(cue),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TranscriptCueRow(
                                  key: ValueKey('transcript-cue-${cue.id}'),
                                  selected: selected,
                                  accentColor: colors.primary,
                                  onTap: () => widget.onSeekCue(cue),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.translationMode.showsSource)
                                        TokenLine(
                                          cue: cue,
                                          profiles: widget.wordEntries,
                                          capabilityProfiles:
                                              widget.capabilityProfiles,
                                          showStyles: widget.showStyles,
                                          // Read as a paragraph, ragged-right.
                                          // TokenLine defaults to centre for the
                                          // on-video subtitle overlay; in the
                                          // transcript that centres every
                                          // wrapped line, which reads as a
                                          // column of poetry rather than prose.
                                          textAlign: TextAlign.start,
                                          // Tight prose leading so one wrapped
                                          // sentence reads as one sentence. The
                                          // subtitle default (font metrics) was
                                          // spacing lines far enough apart that a
                                          // wrapped line looked like the next
                                          // sentence.
                                          lineHeight: 1.35,
                                          // The playing sentence reads in the
                                          // primary hue rather than under a
                                          // full-width fill block: the
                                          // reference marks the current line
                                          // with blue text, and a fill that
                                          // wide becomes the brightest thing on
                                          // the panel — louder than the words it
                                          // is meant to point at.
                                          baseColor: selected
                                              ? colors.primary
                                              : effectiveBaseColor,
                                          onWord: (token, cue) => widget.onWord(
                                            token,
                                            cue,
                                            _lastPressPosition,
                                          ),
                                          groupingMode: widget.groupingMode,
                                          chunkDisplayStyle:
                                              widget.chunkDisplayStyle,
                                          chunkPartition:
                                              widget
                                                  .chunkPartitionsBySentence[cue
                                                  .id],
                                          senseGroups:
                                              widget.senseGroupsBySentence[cue
                                                  .id] ??
                                              const [],
                                        ),
                                      if (widget
                                              .translationMode
                                              .showsTranslation &&
                                          widget.hasTranslationTrack)
                                        _TranslationLine(
                                          text: widget.translationFor?.call(
                                            cue,
                                          ),
                                          missingLabel: l.text(
                                            'sentenceHasNoTranslation',
                                          ),
                                          alone: !widget
                                              .translationMode
                                              .showsSource,
                                        ),
                                    ],
                                  ),
                                ),
                                // The analysis belongs to one sentence, so it
                                // opens inside that sentence. As a panel tab it
                                // could be "open" while the sentence it
                                // described was scrolled out of sight, and
                                // reaching it always cost the transcript.
                                if (selected && widget.onToggleAnalysis != null)
                                  _AnalysisControl(
                                    expanded: widget.analysisExpanded,
                                    label: l.text('analyseSentence'),
                                    onPressed: widget.onToggleAnalysis!,
                                  ),
                                if (selected &&
                                    widget.analysisExpanded &&
                                    widget.analysis != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      ListenSpacing.gap12,
                                      0,
                                      ListenSpacing.gap12,
                                      ListenSpacing.gap12,
                                    ),
                                    child: widget.analysis,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (!_following && widget.currentCue != null)
                      _BackToCurrentBar(
                        label: l.text('backToCurrentSentence'),
                        onPressed: _resumeFollowing,
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  GlobalKey _keyFor(Cue cue) => _cueKeys.putIfAbsent(cue.id, () => GlobalKey());

  void _pauseFollowing() {
    if (_following) setState(() => _following = false);
  }

  void _resumeFollowing() {
    setState(() => _following = true);
    _scheduleCurrentCueSync();
  }

  void _scheduleCurrentCueSync({int attempt = 0}) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncCurrentCue(attempt: attempt);
    });
  }

  void _syncCurrentCue({required int attempt}) {
    if (!_following) return;
    final cue = widget.currentCue;
    if (cue == null) return;

    final cueContext = _cueKeys[cue.id]?.currentContext;
    if (cueContext != null) {
      Scrollable.ensureVisible(
        cueContext,
        alignment: 0.38,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (attempt >= 3 || !_jumpNearCurrentCue(cue)) return;
    _scheduleCurrentCueSync(attempt: attempt + 1);
  }

  bool _jumpNearCurrentCue(Cue cue) {
    final track = widget.track;
    if (track == null || track.cues.isEmpty) return false;
    if (!widget.scrollController.hasClients) return false;

    final index = track.cues.indexWhere((value) => value.id == cue.id);
    if (index < 0) return false;

    final position = widget.scrollController.position;
    final maxScroll = position.maxScrollExtent;
    if (maxScroll <= 0) return false;

    final denominator = track.cues.length <= 1 ? 1 : track.cues.length - 1;
    final target = (maxScroll * (index / denominator)).clamp(
      position.minScrollExtent,
      maxScroll,
    );
    widget.scrollController.jumpTo(target.toDouble());
    return true;
  }
}

/// One sentence in the transcript: the text (and its translation line), made
/// tappable to seek, with the playing sentence marked by a left accent rule.
///
/// This replaced a `ListTile` that carried a 58px timecode gutter on every row
/// and a full-width `primaryContainer` fill on the current one. Together those
/// made the transcript read like a subtitle editor — a column of timecodes with
/// a lit block sliding down it — rather than a page of text. The timecodes go
/// (seeking is a click on the sentence, and the reference reader shows none),
/// and the current line is carried by primary-hue text plus a thin rule instead
/// of a block that outshouts the words.
///
/// The rule keeps its 2.5px width whether or not the row is current — only its
/// colour changes — so a sentence becoming current never nudges its text
/// sideways.
class _TranscriptCueRow extends StatelessWidget {
  const _TranscriptCueRow({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: selected ? accentColor : Colors.transparent,
            width: 2.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap16,
          vertical: ListenSpacing.gap12,
        ),
        child: child,
      ),
    ),
  );
}

/// The translation of one sentence, under the original.
///
/// A sentence whose translation track covers nothing here says so rather than
/// rendering an empty line: with the original above it, a blank row reads as a
/// translation that exists and is empty, which is a different and false claim.
/// The reference app puts a permanent "translation is disabled" line in this
/// slot; the honest version of that is naming which sentence has none.
class _TranslationLine extends StatelessWidget {
  const _TranslationLine({
    required this.text,
    required this.missingLabel,
    required this.alone,
  });

  final String? text;
  final String missingLabel;

  /// True in translation-only mode, where this line is the sentence rather
  /// than an annotation on it, and takes the reading size to match.
  final bool alone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    if (text == null) {
      return Padding(
        padding: const EdgeInsets.only(top: ListenSpacing.gap2),
        child: Text(
          missingLabel,
          key: const Key('transcript-translation-missing'),
          style: theme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: alone ? 0 : ListenSpacing.gap2),
      child: Text(
        text!,
        key: const Key('transcript-translation'),
        style: alone
            ? theme.bodyMedium
            : theme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// Said once when the media has no second track at all.
class _NoTranslationTrackNotice extends StatelessWidget {
  const _NoTranslationTrackNotice({
    required this.message,
    required this.actionLabel,
    required this.onImport,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('transcript-no-translation-track'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Row(
          children: [
            Icon(
              Icons.translate_outlined,
              size: ListenIconSize.control,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            if (onImport != null)
              TextButton(onPressed: onImport, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// The per-sentence analysis toggle, drawn quietly under the current sentence.
///
/// It only exists on the sentence being played, which is the only one the
/// analysis can describe — an always-present control on every row would be a
/// button wall down the length of the transcript.
class _AnalysisControl extends StatelessWidget {
  const _AnalysisControl({
    required this.expanded,
    required this.label,
    required this.onPressed,
  });

  final bool expanded;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: ListenSpacing.gap16),
        child: TextButton.icon(
          key: const Key('transcript-analyse-sentence'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
            padding: ListenPadding.tight,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: ListenIconSize.inline,
          ),
          label: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ),
    );
  }
}

/// The strip that offers to resume following the current sentence.
///
/// It takes its own row at the bottom edge of the list rather than floating
/// over it: the transcript is content, and a control that hides a line of it
/// covers a different line at every window height. Being laid out also makes
/// it honest about its cost — the list gets shorter while the offer stands,
/// and gets its height back the moment following resumes.
class _BackToCurrentBar extends StatelessWidget {
  const _BackToCurrentBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('transcript-back-to-current'),
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: ListenPadding.row,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.vertical_align_center,
                  size: ListenIconSize.control,
                  color: colors.primary,
                ),
                const SizedBox(width: ListenSpacing.gap6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptEmptyState extends StatelessWidget {
  const _TranscriptEmptyState({required this.onImportSubtitle});

  final Future<void> Function()? onImportSubtitle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: ListenPadding.pageCompact,
        child: ConstrainedBox(
          // A centred notice, not a column: glyph, one heading, one sentence,
          // one action. See `noticeColumnMax` for why this rung exists rather
          // than reusing `formColumnMax`.
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.noticeColumnMax,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subtitles_outlined,
                size: ListenIconSize.illustration,
                color: colors.primary,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                l.text('noTranscriptTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('importSubtitleHint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (onImportSubtitle != null) ...[
                const SizedBox(height: ListenSpacing.gap16),
                FilledButton.icon(
                  onPressed: () => onImportSubtitle!(),
                  icon: const Icon(Icons.add),
                  label: Text(l.text('importSubtitle')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
