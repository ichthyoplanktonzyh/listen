import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Renders a subtitle [Cue] as a line of style-aware tokens,
/// with clickable words and phrase underlines.
class TokenLine extends StatefulWidget {
  const TokenLine({
    super.key,
    required this.cue,
    required this.profiles,
    this.capabilityProfiles = const {},
    this.capabilityDisplayChannel,
    required this.showStyles,
    required this.onWord,
    this.onWordTap,
    this.onChunk,
    this.phraseCandidates = const [],
    this.phraseEntries = const {},
    this.onPhrase,
    this.fontSize = 15,
    this.fontFamily,
    this.baseColor,
    this.currentTokenIndex,
    this.chunkPartition,
    this.currentChunkIndex,
    this.chunkDisplayStyle = 'capsule',
    this.chunkHighlightStyle = 'background',
    this.currentWordStyle = 'background',
    this.currentWordIntensity = 0.35,
    this.senseGroups = const [],
    this.groupingMode = 'off',
    this.wordTimings = const [],
    this.connectedSpeechRefs = const [],
    this.mediaPosition,
    this.subtitleOffset = Duration.zero,
    this.textAlign = TextAlign.center,
    this.lineHeight,
    this.trailing,
  });

  final Cue cue;
  final Map<String, LexicalEntry> profiles;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final String? capabilityDisplayChannel;
  final bool showStyles;
  final double fontSize;
  final String? fontFamily;
  final Color? baseColor;
  final int? currentTokenIndex;
  final SentenceChunkPartition? chunkPartition;
  final int? currentChunkIndex;
  final String chunkDisplayStyle;
  final String chunkHighlightStyle;
  final String currentWordStyle;
  final double currentWordIntensity;
  final List<SenseGroup> senseGroups;
  final List<WordTiming> wordTimings;

  /// Connected-speech references for this sentence, display-only (#31): they
  /// place the ‿ tie between linked words (been‿meaning). Pure presentation
  /// wiring — this widget never filters or reinterprets the analysis.
  final List<RhythmConnectedSpeechRef> connectedSpeechRefs;
  final Duration? mediaPosition;
  final Duration subtitleOffset;

  /// Center for subtitle/transcript surfaces; start for the reading view's
  /// flowing paragraphs.
  final TextAlign textAlign;

  /// Line-height multiplier for wrapped lines. Null keeps the font's own
  /// metrics — right for the one- or two-line subtitle drawn over video, where
  /// the app font's tall default leading reads as generous rather than broken.
  /// The transcript, which wraps long sentences into paragraphs, passes a
  /// tighter value so a single sentence's lines sit together instead of drifting
  /// apart like separate sentences.
  final double? lineHeight;

  /// An inline widget flowed after the sentence's last word, wrapping with the
  /// text rather than taking a row of its own. The transcript hangs its `解析`
  /// entry here so it sits at the sentence end, matching the reference.
  final Widget? trailing;

  /// Unified grouping presentation: `off`, `prosodic`, `semantic`, `compare`.
  /// The prosodic ([chunkPartition]) and semantic ([senseGroups]) data both
  /// flow in independently (ADR 0016); this only picks how one is drawn.
  final String groupingMode;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;

  /// A single tap on a word, when the host wants clicks to play from that word.
  /// The dictionary ([onWord]) always opens on a double tap; this is only the
  /// single-tap action. Non-null (the transcript) makes one tap seek to the
  /// word; null (the on-video overlay, the reading view) leaves a single tap to
  /// fall through to whatever sits behind the word.
  final Future<void> Function(SubtitleToken token, Cue cue)? onWordTap;
  final Future<void> Function(DisplayChunk chunk)? onChunk;
  final List<PhraseCandidate> phraseCandidates;
  final Map<String, LexicalEntryDetails> phraseEntries;
  final Future<void> Function(PhraseCandidate candidate, Cue cue)? onPhrase;

  @override
  State<TokenLine> createState() => _TokenLineState();
}

class _TokenLineState extends State<TokenLine> {
  // ── Optical geometry ──
  // The token line *is* the subtitle: every inset here sits between two glyphs
  // of running text drawn at the user's own subtitle size over the video, so it
  // is measured against the type rather than picked off the `ListenSpacing`
  // ladder (see that class's scope note). These are the values that decide
  // whether a line of words reads as one sentence or as a row of buttons, and
  // the ladder's 2pt floor is already too coarse for that: 1pt of extra air per
  // token accumulates into a visibly gappy line.

  /// Vertical inset of a plain (non-capsule) token. A hairline, because the
  /// token has to occupy exactly the line height the surrounding text does —
  /// any more and the subtitle's leading changes when chunk display is on.
  static const _plainTokenInsetVertical = 1.0;

  /// Air between two tokens. The capsule form gets one notch more because its
  /// border would otherwise touch its neighbour's.
  static double _tokenSeam({required bool capsule}) => capsule ? 5 : 4;

  /// Air around the divergence caret. Half the token seam: the marker has to
  /// read as sitting *at* a boundary between two words, so it must be closer to
  /// both of them than they are to each other.
  static const _divergenceMarkerSeam = 1.5;

  late Map<String, ({int startMs, int endMs})?> _sensePlaybackRanges;

  /// Tie placements derived from [TokenLine.connectedSpeechRefs]:
  /// space-token indices whose glyph is replaced by a ‿ tie, and word-token
  /// indices that get a tie inserted before them (direct adjacency).
  late Map<int, RhythmConnectedSpeechRef> _tieReplacesSpace;
  late Map<int, RhythmConnectedSpeechRef> _tieBeforeToken;

  Cue get cue => widget.cue;
  Map<String, LexicalEntry> get profiles => widget.profiles;
  Map<String, LexicalCapabilityProfile> get capabilityProfiles =>
      widget.capabilityProfiles;
  String? get capabilityDisplayChannel => widget.capabilityDisplayChannel;
  bool get showStyles => widget.showStyles;
  double get fontSize => widget.fontSize;
  String? get fontFamily => widget.fontFamily;
  double? get lineHeight => widget.lineHeight;
  Color? get baseColor => widget.baseColor;
  int? get currentTokenIndex => widget.currentTokenIndex;
  SentenceChunkPartition? get chunkPartition => widget.chunkPartition;
  int? get currentChunkIndex => widget.currentChunkIndex;
  String get chunkDisplayStyle => widget.chunkDisplayStyle;
  String get chunkHighlightStyle => widget.chunkHighlightStyle;
  String get currentWordStyle => widget.currentWordStyle;
  double get currentWordIntensity => widget.currentWordIntensity;
  List<SenseGroup> get senseGroups => widget.senseGroups;
  String get groupingMode => widget.groupingMode;
  Future<void> Function(SubtitleToken token, Cue cue) get onWord =>
      widget.onWord;
  Future<void> Function(SubtitleToken token, Cue cue)? get onWordTap =>
      widget.onWordTap;
  Future<void> Function(DisplayChunk chunk)? get onChunk => widget.onChunk;
  List<PhraseCandidate> get phraseCandidates => widget.phraseCandidates;
  Map<String, LexicalEntryDetails> get phraseEntries => widget.phraseEntries;
  Future<void> Function(PhraseCandidate candidate, Cue cue)? get onPhrase =>
      widget.onPhrase;

  @override
  void initState() {
    super.initState();
    _refreshSensePlaybackRanges();
    _refreshTieJunctions();
  }

  @override
  void didUpdateWidget(covariant TokenLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.senseGroups, widget.senseGroups) ||
        !identical(oldWidget.wordTimings, widget.wordTimings)) {
      _refreshSensePlaybackRanges();
    }
    if (!identical(oldWidget.connectedSpeechRefs, widget.connectedSpeechRefs) ||
        !identical(oldWidget.cue, widget.cue)) {
      _refreshTieJunctions();
    }
  }

  /// Projects each reference's token range onto junctions between consecutive
  /// word tokens. A single whitespace junction is drawn as the tie itself; a
  /// direct adjacency gets the tie inserted between; junctions containing
  /// punctuation are left unmarked — a link across punctuation would claim
  /// something the sentence text contradicts.
  void _refreshTieJunctions() {
    final replace = <int, RhythmConnectedSpeechRef>{};
    final before = <int, RhythmConnectedSpeechRef>{};
    for (final ref in widget.connectedSpeechRefs) {
      final start = ref.tokenStart;
      final end = ref.tokenEnd;
      if (start == null || end == null || end <= start) continue;
      final words = widget.cue.tokens
          .where(
            (token) =>
                token.kind == 'word' &&
                token.index >= start &&
                token.index <= end,
          )
          .toList(growable: false);
      for (var i = 0; i + 1 < words.length; i += 1) {
        final between = widget.cue.tokens
            .where(
              (token) =>
                  token.index > words[i].index &&
                  token.index < words[i + 1].index,
            )
            .toList(growable: false);
        if (between.isEmpty) {
          before[words[i + 1].index] = ref;
        } else if (between.every((token) => token.text.trim().isEmpty)) {
          replace[between.first.index] = ref;
        }
      }
    }
    _tieReplacesSpace = replace;
    _tieBeforeToken = before;
  }

  void _refreshSensePlaybackRanges() {
    // Playback ticks rebuild this widget, but the timeline lists keep their
    // identity. Cache projections until either source list is replaced so the
    // hot path only compares the current position with precomputed ranges.
    _sensePlaybackRanges = {
      for (final group in widget.senseGroups)
        group.id: senseGroupPlaybackRange(group, widget.wordTimings),
    };
  }

  @override
  Widget build(BuildContext context) {
    // `timed_text_track` states exact segment text and time but no token
    // boundaries. Render the stated text as text — an empty token list must
    // not become an empty sentence, and splitting it here would fabricate the
    // indices used by word timing, sense groups and prosody.
    if (cue.tokens.isEmpty) {
      return Text(
        cue.text,
        textAlign: widget.textAlign,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: fontFamily,
          height: lineHeight,
          color: baseColor,
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          ..._spans(context),
          if (widget.trailing != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: widget.trailing!,
            ),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _spans(BuildContext context) => switch (groupingMode) {
    'prosodic' => _chunkCapsuleSpans(context, divergenceBoundaries: const {}),
    'compare' => _chunkCapsuleSpans(
      context,
      divergenceBoundaries: _divergenceBoundaries(),
    ),
    'semantic' => _senseCapsuleSpans(context),
    _ => _spansForTokens(context, cue.tokens),
  };

  /// Prosodic (chunk) capsules — the acoustic reality of how the line was said.
  /// Shared by `prosodic` mode and the base layer of `compare` mode.
  List<InlineSpan> _chunkCapsuleSpans(
    BuildContext context, {
    required Set<int> divergenceBoundaries,
  }) {
    final partition = chunkPartition;
    if (partition == null || partition.chunks.isEmpty) {
      return _spansForTokens(
        context,
        cue.tokens,
        divergenceBoundaries: divergenceBoundaries,
      );
    }
    final spans = <InlineSpan>[];
    for (var index = 0; index < partition.chunks.length; index += 1) {
      final chunk = partition.chunks[index];
      final nextStart = index + 1 < partition.chunks.length
          ? partition.chunks[index + 1].tokenStart
          : null;
      final chunkTokens = cue.tokens
          .where(
            (token) =>
                (index == 0 || token.index >= chunk.tokenStart) &&
                (nextStart == null || token.index < nextStart),
          )
          .toList(growable: false);
      if (chunkTokens.isEmpty) continue;
      spans.add(
        _capsuleSpan(
          context,
          keyPrefix: 'chunk',
          keyIndex: chunk.index,
          tokens: chunkTokens,
          active: chunk.index == currentChunkIndex,
          onTap: onChunk == null ? null : () => onChunk!(chunk),
          divergenceBoundaries: divergenceBoundaries,
        ),
      );
    }
    return spans;
  }

  /// Semantic (sense-group) capsules, projected through the active word
  /// timeline for playback following and seeking (ADR 0016).
  List<InlineSpan> _senseCapsuleSpans(BuildContext context) {
    if (senseGroups.isEmpty) return _spansForTokens(context, cue.tokens);
    final groups = [...senseGroups]
      ..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    final spans = <InlineSpan>[];
    for (var index = 0; index < groups.length; index += 1) {
      final group = groups[index];
      final nextStart = index + 1 < groups.length
          ? groups[index + 1].startTokenIndex
          : null;
      final groupTokens = cue.tokens
          .where(
            (token) =>
                (index == 0 || token.index >= group.startTokenIndex) &&
                (nextStart == null || token.index < nextStart),
          )
          .toList(growable: false);
      if (groupTokens.isEmpty) continue;
      final range = _sensePlaybackRanges[group.id];
      final subtitlePosition = widget.mediaPosition == null
          ? null
          : widget.mediaPosition! - widget.subtitleOffset;
      final active =
          range != null &&
          subtitlePosition != null &&
          subtitlePosition >= Duration(milliseconds: range.startMs) &&
          subtitlePosition < Duration(milliseconds: range.endMs);
      spans.add(
        _capsuleSpan(
          context,
          keyPrefix: 'sense',
          keyIndex: group.groupIndex,
          tokens: groupTokens,
          active: active,
          onTap: range == null || onChunk == null
              ? null
              : () => onChunk!(
                  DisplayChunk(
                    index: group.groupIndex,
                    tokenStart: group.startTokenIndex,
                    tokenEnd: group.endTokenIndex,
                    text: group.text,
                    start: Duration(milliseconds: range.startMs),
                    end: Duration(milliseconds: range.endMs),
                  ),
                ),
          divergenceBoundaries: const {},
        ),
      );
    }
    return spans;
  }

  /// Sense-group boundaries (token index where a group starts) that do NOT
  /// coincide with a prosodic-chunk boundary: the listening hotspots where
  /// meaning says "split" but the speaker did not (or vice versa). Empty unless
  /// both data layers are present.
  Set<int> _divergenceBoundaries() {
    final partition = chunkPartition;
    if (partition == null || partition.chunks.isEmpty || senseGroups.isEmpty) {
      return const {};
    }
    final chunkBoundaries = <int>{
      for (var index = 1; index < partition.chunks.length; index += 1)
        partition.chunks[index].tokenStart,
    };
    return <int>{
      for (final group in senseGroups)
        if (group.groupIndex > 0 &&
            !chunkBoundaries.contains(group.startTokenIndex))
          group.startTokenIndex,
    };
  }

  /// Shared solid capsule renderer. [divergenceBoundaries] threads the
  /// compare-mode overlay into the inner token spans.
  InlineSpan _capsuleSpan(
    BuildContext context, {
    required String keyPrefix,
    required int keyIndex,
    required List<SubtitleToken> tokens,
    required bool active,
    required VoidCallback? onTap,
    required Set<int> divergenceBoundaries,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final capsule = chunkDisplayStyle == 'capsule';
    final content = Text.rich(
      TextSpan(
        children: _spansForTokens(
          context,
          tokens,
          divergenceBoundaries: divergenceBoundaries,
        ),
      ),
    );
    final container = AnimatedContainer(
      key: ValueKey('$keyPrefix-container-$keyIndex'),
      // Content settling: the charter base tempo (#32).
      duration: ListenMotion.base,
      padding: EdgeInsets.symmetric(
        horizontal: capsule ? ListenSpacing.gap8 : ListenSpacing.gap2,
        vertical: capsule ? ListenSpacing.gap4 : _plainTokenInsetVertical,
      ),
      decoration: BoxDecoration(
        // The capsule's ink, never a light block (§3.7). A pale grey fill
        // sitting on the video was the clearest case of the shell glowing over
        // content (charter P2) — over a bright frame the chip out-shone the
        // picture, and every word inside it came pre-highlighted. The surface
        // is now the overlay's own darkening token in both states, so the
        // capsule reads as a fold in the video rather than a sticker on it,
        // and the only thing that lights up is the current word.
        color: capsule
            ? active
                  // The chunk being spoken is content, so it may take a teal
                  // wash — laid over the ink, not instead of it.
                  ? Color.alphaBlend(
                      primary.withValues(alpha: 0.16),
                      ListenColors.overlaySurfaceSoft,
                    )
                  : ListenColors.overlaySurfaceSoft
            : active
            ? primary.withValues(alpha: 0.18)
            : Colors.transparent,
        border: capsule
            ? Border.all(
                color: active
                    ? primary.withValues(alpha: 0.42)
                    : ListenColors.overlayText.withValues(alpha: 0.18),
              )
            : null,
        borderRadius: ListenRadii.pillBorder,
        boxShadow: active && chunkHighlightStyle == 'glow'
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.34),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: content,
    );
    final capsuleWidget = GestureDetector(onTap: onTap, child: container);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _tokenSeam(capsule: capsule)),
        child: AnimatedScale(
          key: ValueKey('$keyPrefix-scale-$keyIndex'),
          scale: active && chunkHighlightStyle == 'bounce' ? 1.045 : 1,
          alignment: Alignment.bottomCenter,
          duration: ListenMotion.base,
          curve: ListenMotion.enter,
          child: capsuleWidget,
        ),
      ),
    );
  }

  List<InlineSpan> _spansForTokens(
    BuildContext context,
    List<SubtitleToken> tokens, {
    Set<int> divergenceBoundaries = const {},
  }) {
    if (tokens.isEmpty) return const [];
    final firstIndex = tokens.first.index;
    final lastIndex = tokens.last.index;
    final candidates = _nonOverlappingPhraseCandidates(
      phraseCandidates
          .where(
            (candidate) =>
                candidate.tokenStart >= firstIndex &&
                candidate.tokenEnd <= lastIndex,
          )
          .toList(growable: false),
    );
    final byStart = {
      for (final candidate in candidates) candidate.tokenStart: candidate,
    };
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < tokens.length) {
      if (divergenceBoundaries.contains(tokens[cursor].index)) {
        spans.add(_divergenceMarkerSpan(context, tokens[cursor].index));
      }
      final tieBefore = _tieBeforeToken[tokens[cursor].index];
      if (tieBefore != null) {
        spans.add(_tieSpan(context, tieBefore));
      }
      final tieReplacing = _tieReplacesSpace[tokens[cursor].index];
      if (tieReplacing != null) {
        spans.add(_tieSpan(context, tieReplacing));
        cursor += 1;
        continue;
      }
      final candidate = byStart[tokens[cursor].index];
      if (candidate == null) {
        spans.add(_tokenSpan(context, tokens[cursor]));
        cursor += 1;
        continue;
      }
      final end = candidate.tokenEnd;
      final phraseTokens = <SubtitleToken>[];
      while (cursor < tokens.length && tokens[cursor].index <= end) {
        phraseTokens.add(tokens[cursor]);
        cursor += 1;
      }
      final canonical = candidate.canonicalForm;
      final phraseDetails = phraseEntries[canonical];
      final status =
          _statusFromProfile(phraseDetails?.capabilityProfile) ??
          phraseDetails?.entry.status;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: PhraseUnderlineSpan(
            color: _phraseColor(context, status),
            tooltip: candidate.displayForm,
            onTap: onPhrase == null ? null : () => onPhrase!(candidate, cue),
            child: Text.rich(
              TextSpan(
                children: [
                  for (final token in phraseTokens) ...[
                    if (_tieBeforeToken[token.index] case final ref?)
                      _tieSpan(context, ref),
                    if (_tieReplacesSpace[token.index] case final ref?)
                      _tieSpan(context, ref)
                    else
                      _tokenSpan(context, token),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return spans;
  }

  /// The ‿ tie between linked words (#31): painted, so the mark never depends
  /// on font glyph coverage. It brightens while the current word sits inside
  /// the reference's range — cooperating with the current-word glow instead
  /// of competing with it. Static; nothing here animates.
  InlineSpan _tieSpan(BuildContext context, RhythmConnectedSpeechRef ref) {
    final active =
        currentTokenIndex != null &&
        ref.tokenStart != null &&
        ref.tokenEnd != null &&
        currentTokenIndex! >= ref.tokenStart! &&
        currentTokenIndex! <= ref.tokenEnd!;
    final hint = ref.hint.trim();
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Tooltip(
        message: hint.isNotEmpty ? hint : ref.label,
        child: SizedBox(
          width: math.max(8.0, fontSize * 0.5),
          height: fontSize,
          child: CustomPaint(
            painter: _TiePainter(
              color: ListenColors.soundConnected.withAlpha(active ? 235 : 150),
              glow: active,
            ),
          ),
        ),
      ),
    );
  }

  /// Compare-mode overlay: a small accent caret + dashed tick sitting between
  /// two tokens where the sense-group boundary diverges from the prosodic one.
  InlineSpan _divergenceMarkerSpan(
    BuildContext context,
    int tokenIndex,
  ) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: _divergenceMarkerSeam),
      child: Tooltip(
        message: AppLocalizations.of(context).text('groupingDivergenceHint'),
        child: _DivergenceMarker(
          key: ValueKey('divergence-marker-$tokenIndex'),
          height: fontSize,
          color: ListenColors.accent,
        ),
      ),
    ),
  );

  InlineSpan _tokenSpan(BuildContext context, SubtitleToken token) {
    final clickable = token.kind == 'word' && token.normalized != null;
    final status = _effectiveDisplayStatus(token.normalized);
    final current = token.index == currentTokenIndex;
    final style = _style(context, status, current: current);
    if (!clickable) return TextSpan(text: token.text, style: style);
    // Reduced motion keeps the highlight styles but freezes the bounce: the
    // word still reads as current through color/weight, nothing moves.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        // The dictionary always opens on a double tap, everywhere a word is
        // shown, so the gesture is one thing to learn. A single tap seeks to
        // this word only where the host wired click-to-play ([onWordTap] — the
        // transcript); elsewhere it does nothing and falls through.
        onTap: onWordTap == null ? null : () => onWordTap!(token, cue),
        onDoubleTap: () => onWord(token, cue),
        child: AnimatedScale(
          scale: !reduceMotion && current && currentWordStyle == 'bounce'
              ? 1 + currentWordIntensity * 0.22
              : 1,
          alignment: Alignment.bottomCenter,
          // Word-sync is beat-critical: the fastest step, so the accent
          // lands inside the word being spoken.
          duration: reduceMotion ? Duration.zero : ListenMotion.tap,
          curve: Curves.easeOutBack,
          child: Text(token.text, style: style),
        ),
      ),
    );
  }

  String? _effectiveDisplayStatus(String? normalized) {
    if (normalized == null) return null;
    final cap = capabilityProfiles[normalized];
    if (cap != null) {
      return switch (capabilityDisplayChannel) {
        'reading' => _statusForDimension(cap.reading, reading: true),
        'listening' => _statusForDimension(cap.listening, reading: false),
        _ => _statusFromProfile(cap),
      };
    }
    return profiles[normalized]?.status;
  }

  static String? _statusForDimension(
    CapabilityDimensionState dimension, {
    required bool reading,
  }) => switch (dimension.effectiveAssessment) {
    'not_acquired' => reading ? 'unknown_meaning' : 'known_not_recognized',
    'acquired' => 'known_recognized',
    _ => null,
  };

  static String? _statusFromProfile(LexicalCapabilityProfile? cap) {
    if (cap == null) return null;
    final reading = cap.reading.effectiveAssessment;
    final listening = cap.listening.effectiveAssessment;
    if (reading == 'not_acquired') return 'unknown_meaning';
    if (reading == 'acquired' && listening == 'not_acquired') {
      return 'known_not_recognized';
    }
    if (reading == 'acquired' && listening == 'acquired') {
      return 'known_recognized';
    }
    return null;
  }

  Color _phraseColor(BuildContext context, String? status) => switch (status) {
    'unknown_meaning' => Theme.of(context).colorScheme.error,
    'known_not_recognized' => ListenColors.learningNeedsReview,
    'known_recognized' => ListenColors.learningRecognized,
    _ => Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
  };

  TextStyle _style(
    BuildContext context,
    String? status, {
    bool current = false,
  }) {
    final base = TextStyle(
      fontSize: fontSize,
      fontFamily: fontFamily,
      height: lineHeight,
      // Glow is the charter's caption treatment (#30): the current word IS
      // the signal teal with a soft halo; the other styles keep the gentler
      // lerp. overlaySignal, not colorScheme.primary — over video the light
      // theme's deep teal would sink into the overlay ink.
      color: current
          ? currentWordStyle == 'glow'
                ? ListenColors.overlaySignal
                : Color.lerp(
                    baseColor ?? ListenColors.overlayText,
                    Theme.of(context).colorScheme.primary,
                    currentWordIntensity,
                  )
          : baseColor,
      backgroundColor: current && currentWordStyle == 'background'
          ? Theme.of(context).colorScheme.primary.withValues(
              alpha: 0.18 + currentWordIntensity * 0.2,
            )
          : null,
      fontWeight: current ? FontWeight.w800 : null,
      shadows: current && currentWordStyle == 'glow'
          ? [
              Shadow(
                color: ListenColors.overlaySignal.withValues(
                  alpha: 0.45 + currentWordIntensity * 0.45,
                ),
                blurRadius: 4 + currentWordIntensity * 12,
              ),
            ]
          : null,
    );
    if (!showStyles || status == null) return base;
    return switch (status) {
      'unknown_meaning' => base.copyWith(
        color: Theme.of(context).colorScheme.error,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.double,
      ),
      'known_not_recognized' => base.copyWith(
        color: ListenColors.learningNeedsReview,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
      ),
      'known_recognized' => base.copyWith(
        color: ListenColors.learningRecognized,
        fontWeight: FontWeight.bold,
      ),
      _ => base,
    };
  }
}

/// Select non-overlapping phrases prioritizing longer spans.
List<PhraseCandidate> _nonOverlappingPhraseCandidates(
  List<PhraseCandidate> values,
) {
  final sorted = [...values]
    ..sort((left, right) {
      final leftLength = left.tokenEnd - left.tokenStart;
      final rightLength = right.tokenEnd - right.tokenStart;
      return rightLength.compareTo(leftLength);
    });
  final selected = <PhraseCandidate>[];
  for (final candidate in sorted) {
    final start = candidate.tokenStart;
    final end = candidate.tokenEnd;
    final overlaps = selected.any(
      (value) => start <= value.tokenEnd && end >= value.tokenStart,
    );
    if (!overlaps) selected.add(candidate);
  }
  selected.sort((left, right) => left.tokenStart.compareTo(right.tokenStart));
  return selected;
}

/// Renders an underlined span for a detected phrase, with tooltip and
/// optional tap callback.
class PhraseUnderlineSpan extends StatelessWidget {
  const PhraseUnderlineSpan({
    super.key,
    required this.child,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  final Widget child;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  /// Optical geometry (see `_TokenLineState`): how far the words are lifted off
  /// the underline band drawn beneath them. Derived from that band's own 6pt
  /// height rather than from the spacing ladder — one point of overlap and the
  /// stroke crosses the descenders of the very words it is marking.
  static const _bandClearance = 5.0;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: _bandClearance),
        child: child,
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 6,
        child: Tooltip(
          message: tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(height: 2, color: color),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A small caret + dashed tick used as the compare-mode divergence marker.
class _DivergenceMarker extends StatelessWidget {
  const _DivergenceMarker({
    super.key,
    required this.height,
    required this.color,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: (height * 0.42).clamp(6.0, 12.0),
    height: height,
    child: CustomPaint(painter: _DivergenceMarkerPainter(color: color)),
  );
}

class _TiePainter extends CustomPainter {
  const _TiePainter({required this.color, required this.glow});

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 2 || size.height <= 2) return;
    final tie = Path()
      ..moveTo(1, size.height * 0.72)
      ..quadraticBezierTo(
        size.width / 2,
        size.height * 1.04,
        size.width - 1,
        size.height * 0.72,
      );
    if (glow) {
      // Static halo while the current word is inside the link; decoration
      // only — the tie stroke itself stays fully legible without it.
      canvas.drawPath(
        tie,
        Paint()
          ..color = color.withAlpha(90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.drawPath(
      tie,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TiePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}

class _DivergenceMarkerPainter extends CustomPainter {
  const _DivergenceMarkerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final caretHalf = size.width * 0.4;
    // Downward chevron pointing at the divergence point.
    canvas.drawPath(
      Path()
        ..moveTo(cx - caretHalf, size.height * 0.14)
        ..lineTo(cx, size.height * 0.34)
        ..lineTo(cx + caretHalf, size.height * 0.14),
      paint,
    );
    // Dashed vertical tick beneath the caret.
    var y = size.height * 0.42;
    final bottom = size.height * 0.9;
    while (y < bottom) {
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, (y + 2.2).clamp(0.0, bottom)),
        paint,
      );
      y += 4;
    }
  }

  @override
  bool shouldRepaint(_DivergenceMarkerPainter oldDelegate) =>
      oldDelegate.color != color;
}
