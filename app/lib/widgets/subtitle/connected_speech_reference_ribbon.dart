import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';

class ConnectedSpeechReferenceRibbon extends StatelessWidget {
  const ConnectedSpeechReferenceRibbon({
    super.key,
    required this.references,
    required this.title,
    this.currentTokenIndex,
    this.fontSize = 11,
    this.height = 26,
    this.tooltip,
  });

  final List<RhythmConnectedSpeechRef> references;
  final String title;
  final int? currentTokenIndex;
  final double fontSize;
  final double height;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final rules = references
        .where((reference) => reference.signalSources.contains('text_prior'))
        .toList(growable: false);
    if (rules.isEmpty) return const SizedBox.shrink();

    final content = Semantics(
      label: tooltip ?? title,
      child: SizedBox(
        height: math.max(28, height * 1.18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConnectedBadge(title: title, fontSize: fontSize, height: height),
            const SizedBox(width: 7),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reference in rules)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _ConnectedRuleChip(
                          reference: reference,
                          selected: _containsCurrentToken(reference),
                          fontSize: fontSize,
                          height: height,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
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
  Widget build(BuildContext context) => Container(
    height: math.max(24, height * 0.92),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF153A38).withAlpha(220),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFF6DD6C3).withAlpha(105)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.route_outlined,
          size: math.max(13, height * 0.48),
          color: const Color(0xFF6DD6C3),
        ),
        const SizedBox(width: 5),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withAlpha(230),
            fontSize: math.max(9, fontSize * 0.86),
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ConnectedRuleChip extends StatelessWidget {
  const _ConnectedRuleChip({
    required this.reference,
    required this.selected,
    required this.fontSize,
    required this.height,
  });

  final RhythmConnectedSpeechRef reference;
  final bool selected;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final surface = reference.surfaceText.trim().isEmpty
        ? reference.label
        : reference.surfaceText;
    final expected = reference.expectedDisplayIpa.trim();
    final connected = reference.defaultDisplayIpa.trim();
    final pronunciation = connected.isEmpty
        ? reference.label
        : expected.isEmpty
        ? '/$connected/'
        : '/$expected/ → /$connected/';
    final tooltipLines = <String>[
      surface,
      pronunciation,
      if (reference.hint.trim().isNotEmpty) reference.hint.trim(),
      if (reference.family?.trim().isNotEmpty == true)
        reference.family!.replaceAll('_', ' '),
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: BoxConstraints(
          minHeight: math.max(22, height * 0.82),
          maxWidth: math.max(150, height * 7.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6DD6C3).withAlpha(65)
              : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? const Color(0xFF6DD6C3).withAlpha(185)
                : Colors.white.withAlpha(35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              surface,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(225),
                fontSize: math.max(9, fontSize * 0.82),
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                pronunciation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFA7F3E8),
                  fontSize: math.max(8, fontSize * 0.76),
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
