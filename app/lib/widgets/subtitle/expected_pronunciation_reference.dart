import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import 'following_structure_viewport.dart';

class ExpectedPronunciationReference extends StatelessWidget {
  const ExpectedPronunciationReference({
    super.key,
    required this.analysis,
    required this.title,
    this.currentTokenIndex,
    this.fontSize = 11,
    this.height = 24,
    this.tooltip,
    this.expandTooltip = 'Show full sentence',
    this.collapseTooltip = 'Collapse sentence',
  });

  final PronunciationAnalysis analysis;
  final String title;
  final int? currentTokenIndex;
  final double fontSize;
  final double height;
  final String? tooltip;
  final String expandTooltip;
  final String collapseTooltip;

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final fallback = analysis.displayIpa.trim();
    if (items.isEmpty && fallback.isEmpty) return const SizedBox.shrink();

    final content = Container(
      constraints: BoxConstraints(minHeight: math.max(22.0, height)),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ListenColors.overlaySurfaceSoft,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ListenColors.overlayBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            Icons.record_voice_over,
            size: math.max(12.0, height * 0.45),
            color: ListenColors.soundCitation,
          ),
          const SizedBox(width: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ListenColors.overlayTextMuted,
              fontSize: math.max(9.0, fontSize * 0.85),
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: items.isEmpty
                ? _FallbackText(text: fallback, fontSize: fontSize)
                : FollowingStructureViewport(
                    activeIndex: items.indexWhere(
                      (item) => item.tokenIndex == currentTokenIndex,
                    ),
                    spacing: 4,
                    expandTooltip: expandTooltip,
                    collapseTooltip: collapseTooltip,
                    children: [
                      for (final item in items)
                        _PronunciationChip(
                          item: item,
                          active: item.tokenIndex == currentTokenIndex,
                          fontSize: fontSize,
                          height: height,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    final semantic = Semantics(label: tooltip ?? title, child: content);
    return tooltip == null
        ? semantic
        : Tooltip(message: tooltip!, child: semantic);
  }

  List<_PronunciationItem> _items() {
    final values = <_PronunciationItem>[];
    for (final word in analysis.words) {
      if (word.variants.isEmpty) continue;
      final ipa = word.variants.first.displayIpa.trim();
      if (ipa.isEmpty) continue;
      values.add(
        _PronunciationItem(
          tokenIndex: word.tokenIndex,
          word: word.text,
          ipa: ipa,
        ),
      );
    }
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
    return values;
  }
}

class _FallbackText extends StatelessWidget {
  const _FallbackText({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: ListenColors.overlayText,
      fontSize: math.max(9.0, fontSize),
      height: 1.0,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _PronunciationChip extends StatelessWidget {
  const _PronunciationChip({
    required this.item,
    required this.active,
    required this.fontSize,
    required this.height,
  });

  final _PronunciationItem item;
  final bool active;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      constraints: BoxConstraints(
        minWidth: math.max(34.0, fontSize * 3.2),
        maxWidth: math.max(82.0, fontSize * 8.2),
      ),
      height: math.max(18.0, height * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? ListenColors.soundCitation.withAlpha(225)
            : ListenColors.overlayText.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active
              ? ListenColors.overlayText.withAlpha(150)
              : ListenColors.overlayText.withAlpha(42),
        ),
      ),
      child: Text(
        item.ipa,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active
              ? ListenColors.overlayInk
              : ListenColors.overlayTextMuted,
          fontSize: math.max(9.0, fontSize),
          height: 1.0,
          fontWeight: active ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
    return Tooltip(message: '${item.word}: ${item.ipa}', child: chip);
  }
}

class _PronunciationItem {
  const _PronunciationItem({
    required this.tokenIndex,
    required this.word,
    required this.ipa,
  });

  final int tokenIndex;
  final String word;
  final String ipa;
}
