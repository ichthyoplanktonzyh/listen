import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';
import '../../theme/listen_theme.dart';

/// Presents Reference B as annotations on the sentence rather than as a list of
/// detached rule cards. The transcript remains the visual baseline; arcs,
/// labels and IPA deltas explain what connected speech commonly does to it.
class ConnectedSpeechReferenceRibbon extends StatelessWidget {
  const ConnectedSpeechReferenceRibbon({
    super.key,
    required this.references,
    required this.title,
    this.tokens = const [],
    this.currentTokenIndex,
    this.fontSize = 11,
    this.height = 26,
    this.tooltip,
  });

  final List<RhythmConnectedSpeechRef> references;
  final List<SubtitleToken> tokens;
  final String title;
  final int? currentTokenIndex;
  final double fontSize;
  final double height;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final rules =
        references
            .where(
              (reference) => reference.signalSources.contains('text_prior'),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byStart = (a.tokenStart ?? 1 << 30).compareTo(
              b.tokenStart ?? 1 << 30,
            );
            if (byStart != 0) return byStart;
            return (b.tokenEnd ?? b.tokenStart ?? -1).compareTo(
              a.tokenEnd ?? a.tokenStart ?? -1,
            );
          });
    if (rules.isEmpty) return const SizedBox.shrink();

    final annotations = _annotations(rules);
    final content = Semantics(
      label: tooltip ?? title,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ConnectedBadge(title: title, fontSize: fontSize, height: height),
          const SizedBox(width: 9),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: math.max(5, fontSize * 0.55),
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  for (final annotation in annotations)
                    annotation.rule == null
                        ? _PlainSentenceText(
                            text: annotation.text,
                            fontSize: fontSize,
                          )
                        : _ConnectedAnnotation(
                            reference: annotation.rule!,
                            surface: annotation.text,
                            selected: _containsCurrentToken(annotation.rule!),
                            fontSize: fontSize,
                            height: height,
                          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }

  List<_SentenceAnnotation> _annotations(List<RhythmConnectedSpeechRef> rules) {
    if (tokens.isEmpty) {
      return [
        for (final rule in rules)
          _SentenceAnnotation(
            text: rule.surfaceText.trim().isEmpty
                ? rule.label
                : rule.surfaceText.trim(),
            rule: rule,
          ),
      ];
    }

    final values = <_SentenceAnnotation>[];
    var tokenCursor = 0;
    var ruleCursor = 0;
    while (tokenCursor < tokens.length) {
      while (ruleCursor < rules.length &&
          (rules[ruleCursor].tokenEnd ?? rules[ruleCursor].tokenStart ?? -1) <
              tokens[tokenCursor].index) {
        ruleCursor += 1;
      }
      final rule = ruleCursor < rules.length ? rules[ruleCursor] : null;
      final start = rule?.tokenStart;
      if (rule == null || start == null || start != tokens[tokenCursor].index) {
        final plain = StringBuffer(tokens[tokenCursor].text);
        tokenCursor += 1;
        while (tokenCursor < tokens.length) {
          final nextRuleStart = ruleCursor < rules.length
              ? rules[ruleCursor].tokenStart
              : null;
          if (nextRuleStart == tokens[tokenCursor].index) break;
          plain.write(tokens[tokenCursor].text);
          tokenCursor += 1;
        }
        final text = plain.toString();
        if (text.trim().isNotEmpty) {
          values.add(_SentenceAnnotation(text: text));
        }
        continue;
      }

      final end = rule.tokenEnd ?? start;
      final annotated = StringBuffer();
      while (tokenCursor < tokens.length && tokens[tokenCursor].index <= end) {
        annotated.write(tokens[tokenCursor].text);
        tokenCursor += 1;
      }
      final surface = annotated.toString().trim();
      values.add(
        _SentenceAnnotation(
          text: surface.isEmpty ? rule.surfaceText : surface,
          rule: rule,
        ),
      );
      ruleCursor += 1;
      while (ruleCursor < rules.length &&
          (rules[ruleCursor].tokenStart ?? 1 << 30) <= end) {
        ruleCursor += 1;
      }
    }
    return values;
  }

  bool _containsCurrentToken(RhythmConnectedSpeechRef reference) {
    final current = currentTokenIndex;
    final start = reference.tokenStart;
    if (current == null || start == null) return false;
    final end = reference.tokenEnd ?? start;
    return current >= start && current <= end;
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge({
    required this.title,
    required this.fontSize,
    required this.height,
  });

  final String title;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.route_outlined,
        size: math.max(13, height * 0.48),
        color: ListenColors.soundConnected,
      ),
      const SizedBox(width: 5),
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ListenColors.overlayTextMuted,
          fontSize: math.max(9, fontSize * 0.82),
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ConnectedAnnotation extends StatelessWidget {
  const _ConnectedAnnotation({
    required this.reference,
    required this.surface,
    required this.selected,
    required this.fontSize,
    required this.height,
  });

  final RhythmConnectedSpeechRef reference;
  final String surface;
  final bool selected;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final expected = reference.expectedDisplayIpa.trim();
    final connected = reference.defaultDisplayIpa.trim();
    final pronunciation = connected.isEmpty
        ? reference.label
        : expected.isEmpty
        ? '/$connected/'
        : '/$expected/ → /$connected/';
    final ruleLabel = _ruleLabel(reference);
    final tooltipLines = <String>[
      surface,
      pronunciation,
      if (reference.hint.trim().isNotEmpty) reference.hint.trim(),
      if (reference.family?.trim().isNotEmpty == true)
        reference.family!.replaceAll('_', ' '),
    ];
    final accent = selected
        ? ListenColors.soundConnectedStrong
        : ListenColors.soundConnected;

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Semantics(
        label: tooltipLines.join(', '),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ruleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent.withAlpha(selected ? 255 : 205),
                  fontSize: math.max(8, fontSize * 0.68),
                  height: 1,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              CustomPaint(
                foregroundPainter: _SpeechMarkPainter(
                  color: accent.withAlpha(selected ? 245 : 190),
                  emphasized: selected,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    math.max(3, fontSize * 0.3),
                    math.max(4, height * 0.16),
                    math.max(3, fontSize * 0.3),
                    3,
                  ),
                  child: Text(
                    surface,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ListenColors.overlayText.withAlpha(
                        selected ? 250 : 220,
                      ),
                      fontSize: math.max(10, fontSize),
                      height: 1,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(
                pronunciation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent.withAlpha(selected ? 235 : 170),
                  fontSize: math.max(8, fontSize * 0.7),
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeechMarkPainter extends CustomPainter {
  const _SpeechMarkPainter({required this.color, required this.emphasized});

  final Color color;
  final bool emphasized;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 2 || size.height <= 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = emphasized ? 2.2 : 1.5
      ..strokeCap = StrokeCap.round;
    final arc = Path()
      ..moveTo(2, size.height * 0.28)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.12,
        size.width - 2,
        size.height * 0.28,
      );
    canvas.drawPath(arc, paint);
    canvas.drawLine(
      Offset(2, size.height - 1),
      Offset(size.width - 2, size.height - 1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpeechMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.emphasized != emphasized;
}

class _PlainSentenceText extends StatelessWidget {
  const _PlainSentenceText({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: math.max(10, fontSize * 0.86)),
    child: Text(
      text.trim(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: ListenColors.overlayTextFaint,
        fontSize: math.max(10, fontSize),
        height: 1,
      ),
    ),
  );
}

class _SentenceAnnotation {
  const _SentenceAnnotation({required this.text, this.rule});

  final String text;
  final RhythmConnectedSpeechRef? rule;
}

String _ruleLabel(RhythmConnectedSpeechRef reference) {
  final family = reference.family?.trim().replaceAll('_', ' ') ?? '';
  if (family.isNotEmpty) return family;
  final label = reference.label.trim();
  return label.isEmpty ? 'connected speech' : label;
}
