import 'package:flutter/material.dart';

import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';

/// Renders a subtitle [Cue] as a line of style-aware tokens,
/// with clickable words and phrase underlines.
class TokenLine extends StatelessWidget {
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
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(DisplayChunk chunk)? onChunk;
  final List<PhraseCandidate> phraseCandidates;
  final Map<String, LexicalEntryDetails> phraseEntries;
  final Future<void> Function(PhraseCandidate candidate, Cue cue)? onPhrase;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: _spans(context)),
    textAlign: TextAlign.center,
  );

  List<InlineSpan> _spans(BuildContext context) {
    final partition = chunkPartition;
    if (partition == null || partition.chunks.isEmpty) {
      return _spansForTokens(context, cue.tokens);
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
      final active = chunk.index == currentChunkIndex;
      final capsule = chunkDisplayStyle == 'capsule';
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: capsule ? 5 : 4),
            child: AnimatedScale(
              key: ValueKey('chunk-scale-${chunk.index}'),
              scale: active && chunkHighlightStyle == 'bounce' ? 1.045 : 1,
              alignment: Alignment.bottomCenter,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: onChunk == null ? null : () => onChunk!(chunk),
                child: AnimatedContainer(
                  key: ValueKey('chunk-container-${chunk.index}'),
                  duration: const Duration(milliseconds: 280),
                  padding: EdgeInsets.symmetric(
                    horizontal: capsule ? 10 : 2,
                    vertical: capsule ? 4 : 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.18)
                        : capsule
                        ? ListenColors.overlayText.withValues(alpha: 0.08)
                        : Colors.transparent,
                    border: capsule
                        ? Border.all(
                            color: active
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.42)
                                : ListenColors.overlayText.withValues(
                                    alpha: 0.18,
                                  ),
                          )
                        : null,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: active && chunkHighlightStyle == 'glow'
                        ? [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.34),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Text.rich(
                    TextSpan(children: _spansForTokens(context, chunkTokens)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return spans;
  }

  List<InlineSpan> _spansForTokens(
    BuildContext context,
    List<SubtitleToken> tokens,
  ) {
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
    final senseGroupStarts = <int>{
      for (final sg in senseGroups)
        if (sg.groupIndex > 0) sg.startTokenIndex,
    };
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < tokens.length) {
      if (senseGroupStarts.contains(tokens[cursor].index)) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SizedBox(
                width: 1,
                height: fontSize * 0.9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
        );
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
      final status = _statusFromProfile(phraseDetails?.capabilityProfile)
          ?? phraseDetails?.entry.status;
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
