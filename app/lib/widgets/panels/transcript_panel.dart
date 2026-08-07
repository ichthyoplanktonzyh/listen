import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../models/workbench_study_mode.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
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
    this.translationMode = TranscriptTranslation.source,
    this.translationFor,
    this.hasTranslationTrack = false,
    this.onImportTranslation,
    this.studyMode = WorkbenchStudyMode.normal,
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

  /// Opens or closes the floating analysis window for the current sentence.
  /// Null on hosts with no analysis wired, which hides the control rather than
  /// offering a dead one. [analysisExpanded] reflects whether that window is
  /// currently open, so the entry can read as pressed.
  final VoidCallback? onToggleAnalysis;
  final bool analysisExpanded;

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

  /// How the transcript presents itself: read-through, blind, or word-select.
  /// The reading states are displays of this same panel, so they are branches
  /// here rather than separate windows.
  final WorkbenchStudyMode studyMode;

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
    final colors = Theme.of(context).colorScheme;
    final Widget body;
    if (widget.track == null) {
      body = _TranscriptEmptyState(onImportSubtitle: widget.onImportSubtitle);
    } else {
      // The reading states are displays of this same pane. Read-through is the
      // scrolling transcript; blind and word-select replace it with a single
      // sentence in focus — the reference does not keep the list behind them.
      body = switch (widget.studyMode) {
        WorkbenchStudyMode.normal => _readThroughList(context),
        WorkbenchStudyMode.blindListening => _BlindView(
          cue: widget.currentCue,
          index: _currentCueIndex,
          total: widget.track!.cues.length,
        ),
        WorkbenchStudyMode.wordSelection => _WordSelectView(
          // A different sentence is a different exercise: rebuild from scratch
          // so filled blanks never bleed across sentences.
          key: ValueKey(widget.currentCue?.id),
          cue: widget.currentCue,
          index: _currentCueIndex,
          total: widget.track!.cues.length,
        ),
      };
    }
    return Material(color: colors.surfaceContainerLowest, child: body);
  }

  Widget _readThroughList(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final effectiveBaseColor = widget.baseColor.computeLuminance() > 0.75
        ? colors.onSurface
        : widget.baseColor;
    return NotificationListener<ScrollNotification>(
      // A real user drag carries dragDetails; programmatic scrolls do not, so
      // this pauses following only on genuine interaction.
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
        // A stack, so the resume-following control floats as a FAB over the
        // bottom-right of the list, matching the reference app. It is offered
        // only while following is paused *and* the list has drifted off the
        // current sentence, so whatever row sits beneath it is by definition
        // not the one the reader is tracking; one tap scrolls that sentence
        // back into view and the FAB retires.
        child: Stack(
          children: [
            Column(
              children: [
                // Said once, at the top, because it is a fact about the file.
                // Repeating it under all 200 sentences would be the same fact 200
                // times, and would drown the sentences that genuinely have no line
                // of their own.
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.translationMode.showsSource)
                                    TokenLine(
                                      cue: cue,
                                      profiles: widget.wordEntries,
                                      capabilityProfiles:
                                          widget.capabilityProfiles,
                                      showStyles: widget.showStyles,
                                      // Read as a paragraph, ragged-right. TokenLine
                                      // defaults to centre for the on-video subtitle
                                      // overlay; in the transcript that centres every
                                      // wrapped line, which reads as a column of
                                      // poetry rather than prose.
                                      textAlign: TextAlign.start,
                                      // Tight prose leading so one wrapped sentence
                                      // reads as one sentence.
                                      lineHeight: 1.35,
                                      // The playing sentence reads in the primary
                                      // hue rather than under a full-width fill
                                      // block: a fill that wide becomes the
                                      // brightest thing on the panel — louder than
                                      // the words it is meant to point at.
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
                                      chunkPartition: widget
                                          .chunkPartitionsBySentence[cue.id],
                                      senseGroups:
                                          widget.senseGroupsBySentence[cue
                                              .id] ??
                                          const [],
                                      // The analysis is about one sentence, so
                                      // its entry rides the end of that
                                      // sentence's text — inline at the sentence
                                      // tail, matching the reference — rather
                                      // than a row of its own. Tapping it opens
                                      // the floating analysis window.
                                      trailing:
                                          selected &&
                                              widget.onToggleAnalysis != null
                                          ? _AnalysisControl(
                                              expanded: widget.analysisExpanded,
                                              label: l.text('analyseSentence'),
                                              onPressed: widget.onToggleAnalysis!,
                                            )
                                          : null,
                                    ),
                                  if (widget.translationMode.showsTranslation &&
                                      widget.hasTranslationTrack)
                                    _TranslationLine(
                                      text: widget.translationFor?.call(cue),
                                      missingLabel: l.text(
                                        'sentenceHasNoTranslation',
                                      ),
                                      alone:
                                          !widget.translationMode.showsSource,
                                    ),
                                  // Translation-only mode hides the source line
                                  // the entry would hang from, so it falls back
                                  // to a row of its own there.
                                  if (!widget.translationMode.showsSource &&
                                      selected &&
                                      widget.onToggleAnalysis != null)
                                    _AnalysisControl(
                                      expanded: widget.analysisExpanded,
                                      label: l.text('analyseSentence'),
                                      onPressed: widget.onToggleAnalysis!,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (!_following && widget.currentCue != null)
              Positioned(
                right: ListenSpacing.gap16,
                bottom: ListenSpacing.gap16,
                child: _BackToCurrentFab(
                  label: l.text('backToCurrentSentence'),
                  onPressed: _resumeFollowing,
                ),
              ),
          ],
        ),
      ),
    );
  }

  GlobalKey _keyFor(Cue cue) => _cueKeys.putIfAbsent(cue.id, () => GlobalKey());

  /// 1-based position of the current sentence, or 0 before one is playing.
  int get _currentCueIndex {
    final cue = widget.currentCue;
    final cues = widget.track?.cues;
    if (cue == null || cues == null) return 0;
    final index = cues.indexWhere((value) => value.id == cue.id);
    return index < 0 ? 0 : index + 1;
  }

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

/// The header row shared by the single-sentence focus modes: an optional label
/// on the left and the `n / total` count on the right, matching the reference's
/// progress pill.
class _FocusHeader extends StatelessWidget {
  const _FocusHeader({this.label, required this.index, required this.total});

  final String? label;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        if (label != null) ...[
          Icon(
            Icons.hearing_outlined,
            size: ListenIconSize.control,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: ListenSpacing.gap8),
          Text(
            label!,
            style: theme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
          const Spacer(),
        ],
        DecoratedBox(
          key: const Key('transcript-focus-progress'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: ListenRadii.pillBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap12,
              vertical: ListenSpacing.gap4,
            ),
            child: Text(
              '$index / $total',
              style: theme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown by both focus modes before a sentence is playing — there is no current
/// sentence to blank, so it asks for one rather than rendering an empty frame.
class _FocusAwaitingCue extends StatelessWidget {
  const _FocusAwaitingCue({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: ListenPadding.page,
        child: Text(
          message,
          key: const Key('transcript-focus-awaiting'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Blind listening: the current sentence only, with most words blanked to a
/// gap the size of the hidden word. The learner reads what scaffolding is left
/// and catches the rest by ear. No candidate words — that is word-select.
class _BlindView extends StatelessWidget {
  const _BlindView({
    required this.cue,
    required this.index,
    required this.total,
  });

  final Cue? cue;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    if (cue == null) {
      return Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FocusHeader(
              label: l.text('blindModeLabel'),
              index: index,
              total: total,
            ),
            const SizedBox(height: ListenSpacing.gap16),
            Expanded(
              child: _FocusAwaitingCue(message: l.text('focusAwaitingCue')),
            ),
          ],
        ),
      );
    }
    // Scrollable: one long sentence, blanked and loosely leaded, can outrun a
    // short pane.
    return SingleChildScrollView(
      padding: ListenPadding.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FocusHeader(
            label: l.text('blindModeLabel'),
            index: index,
            total: total,
          ),
          const SizedBox(height: ListenSpacing.gap16),
          Text.rich(
            TextSpan(children: _blankSpans(context, _blankSentence(cue!))),
            key: const Key('transcript-blind-sentence'),
            style: theme.titleMedium?.copyWith(height: 1.9),
          ),
        ],
      ),
    );
  }
}

/// Word select: the current sentence blanked, and below it the removed words as
/// chips to place back. The chips are exactly the blanked words, shuffled — the
/// exercise is self-contained in the sentence, no external answer data.
class _WordSelectView extends StatefulWidget {
  const _WordSelectView({
    super.key,
    required this.cue,
    required this.index,
    required this.total,
  });

  final Cue? cue;
  final int index;
  final int total;

  @override
  State<_WordSelectView> createState() => _WordSelectViewState();
}

class _WordSelectViewState extends State<_WordSelectView> {
  late List<_Segment> _segments;
  late List<_Candidate> _candidates;

  // slot index -> the candidate placed in it, or null while empty.
  final Map<int, int> _placed = {};

  // Tap recognizers for filled blanks, rebuilt each frame and disposed here so
  // they never outlive the spans that hold them.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _build() {
    final cue = widget.cue;
    _segments = cue == null ? const [] : _blankSentence(cue);
    final blanks = _segments.whereType<_Blank>().toList();
    // The pool is the removed words themselves, shuffled deterministically per
    // sentence so it is stable across rebuilds within a sitting.
    final rng = Random(cue == null ? 0 : cue.id.hashCode ^ 0x5f3759df);
    final pool = [
      for (var i = 0; i < blanks.length; i += 1)
        _Candidate(id: i, word: blanks[i].answer),
    ]..shuffle(rng);
    _candidates = pool;
  }

  int? get _nextEmptySlot {
    for (final segment in _segments) {
      if (segment is _Blank && !_placed.containsKey(segment.slot)) {
        return segment.slot;
      }
    }
    return null;
  }

  void _place(_Candidate candidate) {
    final slot = _nextEmptySlot;
    if (slot == null) return;
    setState(() => _placed[slot] = candidate.id);
  }

  void _clear(int slot) => setState(() => _placed.remove(slot));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    if (widget.cue == null) {
      return Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FocusHeader(index: widget.index, total: widget.total),
            const SizedBox(height: ListenSpacing.gap16),
            Expanded(
              child: _FocusAwaitingCue(message: l.text('focusAwaitingCue')),
            ),
          ],
        ),
      );
    }
    final usedIds = _placed.values.toSet();
    return SingleChildScrollView(
      padding: ListenPadding.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FocusHeader(index: widget.index, total: widget.total),
          const SizedBox(height: ListenSpacing.gap16),
          Text.rich(
            TextSpan(
              children: _filledSpans(context, _segments, _placed, _candidates),
            ),
            key: const Key('transcript-word-select-sentence'),
            style: theme.titleMedium?.copyWith(height: 2.1),
          ),
          const SizedBox(height: ListenSpacing.gap16),
          Divider(color: colors.outlineVariant),
          const SizedBox(height: ListenSpacing.gap8),
          Text(
            l.text('wordSelectPrompt'),
            style: theme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap12),
          Wrap(
            spacing: ListenSpacing.gap12,
            runSpacing: ListenSpacing.gap12,
            children: [
              for (final candidate in _candidates)
                _WordChip(
                  label: candidate.word,
                  used: usedIds.contains(candidate.id),
                  onTap: () => _place(candidate),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _filledSpans(
    BuildContext context,
    List<_Segment> segments,
    Map<int, int> placed,
    List<_Candidate> candidates,
  ) {
    final colors = Theme.of(context).colorScheme;
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    for (final segment in segments) {
      if (segment is _Literal) {
        spans.add(TextSpan(text: segment.text));
        continue;
      }
      final blank = segment as _Blank;
      final placedId = placed[blank.slot];
      if (placedId == null) {
        spans.add(_underscoreSpan(context, blank.answer.length));
      } else {
        final word = candidates.firstWhere((c) => c.id == placedId).word;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _clear(blank.slot);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(
              color: colors.primary,
              decoration: TextDecoration.underline,
              decorationColor: colors.primary,
            ),
            recognizer: recognizer,
          ),
        );
      }
    }
    return spans;
  }
}

/// One candidate word placed in the pool.
class _Candidate {
  const _Candidate({required this.id, required this.word});
  final int id;
  final String word;
}

/// A tappable candidate chip. A placed chip stays visible but greys out, so the
/// pool never changes shape underfoot as words are used.
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.label,
    required this.used,
    required this.onTap,
  });

  final String label;
  final bool used;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: used ? null : onTap,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: used ? colors.outlineVariant : colors.outline),
        foregroundColor: colors.onSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap16,
          vertical: ListenSpacing.gap8,
        ),
      ),
      child: Text(label),
    );
  }
}

/// A blank standing in for one hidden word (`_Blank`) or a run of kept text —
/// words, spaces, punctuation — shown verbatim (`_Literal`).
sealed class _Segment {
  const _Segment();
}

class _Literal extends _Segment {
  const _Literal(this.text);
  final String text;
}

class _Blank extends _Segment {
  const _Blank({required this.answer, required this.slot});
  final String answer;
  final int slot;
}

/// Blanks a sentence for the focus modes: word tokens are hidden with a
/// deterministic ~60% probability (seeded by the sentence id so it is stable
/// within a sitting), everything else — spaces, punctuation, kept words — is
/// literal. At least one word is always blanked so word-select has an exercise,
/// and never every word so blind keeps some scaffolding.
List<_Segment> _blankSentence(Cue cue) {
  final words = [
    for (var i = 0; i < cue.tokens.length; i += 1)
      if (_isBlankable(cue.tokens[i])) i,
  ];
  final rng = Random(cue.id.hashCode);
  final blanked = <int>{};
  for (final index in words) {
    if (rng.nextDouble() < 0.6) blanked.add(index);
  }
  // Guardrails: at least one blank, and at least one word left visible.
  if (words.isNotEmpty && blanked.isEmpty) blanked.add(words.first);
  if (words.length > 1 && blanked.length == words.length) {
    blanked.remove(words.first);
  }

  final segments = <_Segment>[];
  var slot = 0;
  for (var i = 0; i < cue.tokens.length; i += 1) {
    final token = cue.tokens[i];
    if (blanked.contains(i)) {
      segments.add(_Blank(answer: token.text, slot: slot++));
    } else {
      segments.add(_Literal(token.text));
    }
  }
  return segments;
}

bool _isBlankable(SubtitleToken token) =>
    token.kind == 'word' && (token.normalized?.isNotEmpty ?? false);

/// The blind view's non-interactive spans: literals verbatim, blanks as an
/// underscore run the width of the hidden word.
List<InlineSpan> _blankSpans(BuildContext context, List<_Segment> segments) {
  final spans = <InlineSpan>[];
  for (final segment in segments) {
    if (segment is _Literal) {
      spans.add(TextSpan(text: segment.text));
    } else {
      spans.add(_underscoreSpan(context, (segment as _Blank).answer.length));
    }
  }
  return spans;
}

/// A blank: an underscore run sized to the hidden word, clamped so a very short
/// or very long word still reads as a gap.
InlineSpan _underscoreSpan(BuildContext context, int wordLength) {
  final colors = Theme.of(context).colorScheme;
  final count = wordLength.clamp(2, 12);
  return TextSpan(
    text: ' ${'_' * count} ',
    style: TextStyle(color: colors.onSurfaceVariant),
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
    // Open reads in the primary hue; closed is a quiet outline chip so it sits
    // at the sentence tail without competing with the words.
    final accent = expanded ? colors.primary : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: ListenSpacing.gap6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('transcript-analyse-sentence'),
          onTap: onPressed,
          borderRadius: ListenRadii.pillBorder,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ListenRadii.pillBorder,
              border: Border.all(color: expanded ? colors.primary : colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ListenSpacing.gap8,
                vertical: ListenSpacing.gap2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded ? Icons.info : Icons.info_outline,
                    size: ListenIconSize.inline,
                    color: accent,
                  ),
                  const SizedBox(width: ListenSpacing.gap4),
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip that offers to resume following the current sentence.
///
/// It floats as a small pill over the bottom-right of the list rather than
/// taking a laid-out row, matching the reference app. The trade-off a laid-out
/// strip avoided — covering a line of transcript — does not bite here: the
/// offer only stands while following is paused and the current sentence has
/// scrolled away, so the row it overlaps is never the one the reader is on, and
/// the tap that would reveal it also retires the pill. Icon-only, with the
/// label carried as a tooltip so it stays legible to a screen reader.
class _BackToCurrentFab extends StatelessWidget {
  const _BackToCurrentFab({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Material(
        key: const Key('transcript-back-to-current'),
        color: colors.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: ListenRadii.surfaceBorder,
          side: BorderSide(color: colors.outlineVariant),
        ),
        elevation: 2,
        shadowColor: colors.shadow,
        child: InkWell(
          onTap: onPressed,
          borderRadius: ListenRadii.surfaceBorder,
          child: Semantics(
            button: true,
            label: label,
            child: SizedBox(
              width: 40,
              height: 52,
              child: Icon(
                Icons.keyboard_double_arrow_down,
                size: ListenIconSize.chrome,
                color: colors.onSurfaceVariant,
              ),
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
