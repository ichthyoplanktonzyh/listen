import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';

/// Renders a subtitle [Cue] as a line of style-aware tokens,
/// with clickable words and phrase underlines.
class TokenLine extends StatefulWidget {
  const TokenLine({
    super.key,
    required this.cue,
    required this.profiles,
    this.capabilityProfiles = const {},
    required this.showStyles,
    required this.onWord,
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
    this.mediaPosition,
    this.subtitleOffset = Duration.zero,
  });

  final Cue cue;
  final Map<String, LexicalEntry> profiles;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
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
  final Duration? mediaPosition;
  final Duration subtitleOffset;

  /// Unified grouping presentation: `off`, `prosodic`, `semantic`, `compare`.
  /// The prosodic ([chunkPartition]) and semantic ([senseGroups]) data both
  /// flow in independently (ADR 0016); this only picks how one is drawn.
  final String groupingMode;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(DisplayChunk chunk)? onChunk;
  final List<PhraseCandidate> phraseCandidates;
  final Map<String, LexicalEntryDetails> phraseEntries;
  final Future<void> Function(PhraseCandidate candidate, Cue cue)? onPhrase;

  @override
  State<TokenLine> createState() => _TokenLineState();
}

class _TokenLineState extends State<TokenLine> {
  late Map<String, ({int startMs, int endMs})?> _sensePlaybackRanges;

  Cue get cue => widget.cue;
  Map<String, LexicalEntry> get profiles => widget.profiles;
  Map<String, LexicalCapabilityProfile> get capabilityProfiles =>
      widget.capabilityProfiles;
  bool get showStyles => widget.showStyles;
  double get fontSize => widget.fontSize;
  String? get fontFamily => widget.fontFamily;
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
  Future<void> Function(DisplayChunk chunk)? get onChunk => widget.onChunk;
  List<PhraseCandidate> get phraseCandidates => widget.phraseCandidates;
  Map<String, LexicalEntryDetails> get phraseEntries => widget.phraseEntries;
  Future<void> Function(PhraseCandidate candidate, Cue cue)? get onPhrase =>
      widget.onPhrase;

  @override
  void initState() {
    super.initState();
    _refreshSensePlaybackRanges();
  }

  @override
  void didUpdateWidget(covariant TokenLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.senseGroups, widget.senseGroups) ||
        !identical(oldWidget.wordTimings, widget.wordTimings)) {
      _refreshSensePlaybackRanges();
    }
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
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: _spans(context)),
    textAlign: TextAlign.center,
  );

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
      duration: const Duration(milliseconds: 280),
      padding: EdgeInsets.symmetric(
        horizontal: capsule ? 10 : 2,
        vertical: capsule ? 4 : 1,
      ),
      decoration: BoxDecoration(
        color: active
            ? primary.withValues(alpha: 0.18)
            : capsule
            ? ListenColors.overlayText.withValues(alpha: 0.08)
            : Colors.transparent,
        border: capsule
            ? Border.all(
                color: active
                    ? primary.withValues(alpha: 0.42)
                    : ListenColors.overlayText.withValues(alpha: 0.18),
              )
            : null,
        borderRadius: BorderRadius.circular(999),
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
        padding: EdgeInsets.symmetric(horizontal: capsule ? 5 : 4),
        child: AnimatedScale(
          key: ValueKey('$keyPrefix-scale-$keyIndex'),
          scale: active && chunkHighlightStyle == 'bounce' ? 1.045 : 1,
          alignment: Alignment.bottomCenter,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
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
                children: phraseTokens
                    .map((token) => _tokenSpan(context, token))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      );
    }
    return spans;
  }

  /// Compare-mode overlay: a small accent caret + dashed tick sitting between
  /// two tokens where the sense-group boundary diverges from the prosodic one.
  InlineSpan _divergenceMarkerSpan(BuildContext context, int tokenIndex) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Tooltip(
            message: AppLocalizations.of(
              context,
            ).text('groupingDivergenceHint'),
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
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        onTap: () => onWord(token, cue),
        child: AnimatedScale(
          scale: current && currentWordStyle == 'bounce'
              ? 1 + currentWordIntensity * 0.22
              : 1,
          alignment: Alignment.bottomCenter,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: Text(token.text, style: style),
        ),
      ),
    );
  }

  String? _effectiveDisplayStatus(String? normalized) {
    if (normalized == null) return null;
    final cap = capabilityProfiles[normalized];
    if (cap != null) return _statusFromProfile(cap);
    return profiles[normalized]?.status;
  }

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
      color: current
          ? Color.lerp(
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
                color: Theme.of(context).colorScheme.primary.withValues(
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

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(padding: const EdgeInsets.only(bottom: 5), child: child),
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
