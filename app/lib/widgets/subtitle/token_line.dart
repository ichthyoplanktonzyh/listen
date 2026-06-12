import 'package:flutter/material.dart';

import '../../models/timeline.dart';

/// Renders a subtitle [Cue] as a line of style-aware tokens,
/// with clickable words and phrase underlines.
class TokenLine extends StatelessWidget {
  const TokenLine({
    super.key,
    required this.cue,
    required this.profiles,
    required this.showStyles,
    required this.onWord,
    this.phraseCandidates = const [],
    this.phraseProfiles = const {},
    this.onPhrase,
    this.fontSize = 15,
    this.fontFamily,
    this.baseColor,
  });

  final Cue cue;
  final Map<String, Map<String, dynamic>> profiles;
  final bool showStyles;
  final double fontSize;
  final String? fontFamily;
  final Color? baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final List<Map<String, dynamic>> phraseCandidates;
  final Map<String, Map<String, dynamic>> phraseProfiles;
  final Future<void> Function(Map<String, dynamic> candidate, Cue cue)?
      onPhrase;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: _spans(context)),
    textAlign: TextAlign.center,
  );

  List<InlineSpan> _spans(BuildContext context) {
    final candidates = _nonOverlappingPhraseCandidates(phraseCandidates);
    final byStart = {
      for (final candidate in candidates)
        candidate['token_start'] as int: candidate,
    };
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < cue.tokens.length) {
      final candidate = byStart[cue.tokens[cursor].index];
      if (candidate == null) {
        spans.add(_tokenSpan(context, cue.tokens[cursor]));
        cursor += 1;
        continue;
      }
      final end = candidate['token_end'] as int;
      final phraseTokens = <SubtitleToken>[];
      while (cursor < cue.tokens.length && cue.tokens[cursor].index <= end) {
        phraseTokens.add(cue.tokens[cursor]);
        cursor += 1;
      }
      final canonical = candidate['canonical_form'] as String;
      final status =
          (phraseProfiles[canonical]?['entry']
                  as Map<String, dynamic>?)?['status']
              as String?;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: PhraseUnderlineSpan(
            color: _phraseColor(context, status),
            tooltip: candidate['display_form'] as String,
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
    final status = profiles[token.normalized]?['status'] as String?;
    final style = _style(context, status);
    if (!clickable) return TextSpan(text: token.text, style: style);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        onTap: () => onWord(token, cue),
        child: Text(token.text, style: style),
      ),
    );
  }

  Color _phraseColor(BuildContext context, String? status) => switch (status) {
    'unknown_meaning' => Theme.of(context).colorScheme.error,
    'known_not_recognized' => Colors.amber,
    'known_recognized' => Colors.greenAccent,
    _ => Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
  };

  TextStyle _style(BuildContext context, String? status) {
    final base = TextStyle(
      fontSize: fontSize,
      fontFamily: fontFamily,
      color: baseColor,
    );
    if (!showStyles || status == null) return base;
    return switch (status) {
      'unknown_meaning' => base.copyWith(
        color: Theme.of(context).colorScheme.error,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.double,
      ),
      'known_not_recognized' => base.copyWith(
        color: Colors.amber,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
      ),
      'known_recognized' => base.copyWith(
        color: Colors.greenAccent,
        fontWeight: FontWeight.bold,
      ),
      _ => base,
    };
  }
}

/// Select non-overlapping phrases prioritizing longer spans.
List<Map<String, dynamic>> _nonOverlappingPhraseCandidates(
  List<Map<String, dynamic>> values,
) {
  final sorted = [...values]
    ..sort((left, right) {
      final leftLength =
          (left['token_end'] as int) - (left['token_start'] as int);
      final rightLength =
          (right['token_end'] as int) - (right['token_start'] as int);
      return rightLength.compareTo(leftLength);
    });
  final selected = <Map<String, dynamic>>[];
  for (final candidate in sorted) {
    final start = candidate['token_start'] as int;
    final end = candidate['token_end'] as int;
    final overlaps = selected.any(
      (value) =>
          start <= (value['token_end'] as int) &&
          end >= (value['token_start'] as int),
    );
    if (!overlaps) selected.add(candidate);
  }
  selected.sort(
    (left, right) =>
        (left['token_start'] as int).compareTo(right['token_start'] as int),
  );
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
