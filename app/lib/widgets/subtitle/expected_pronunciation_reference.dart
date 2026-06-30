import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/types.dart';

class ExpectedPronunciationReference extends StatelessWidget {
  const ExpectedPronunciationReference({
    super.key,
    required this.analysis,
    required this.title,
    this.currentTokenIndex,
    this.fontSize = 11,
    this.height = 24,
    this.tooltip,
  });

  final PronunciationAnalysis analysis;
  final String title;
  final int? currentTokenIndex;
  final double fontSize;
  final double height;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final fallback = analysis.displayIpa.trim();
    if (items.isEmpty && fallback.isEmpty) return const SizedBox.shrink();

    final content = Container(
      constraints: BoxConstraints(minHeight: math.max(22.0, height)),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withAlpha(185),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withAlpha(34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.record_voice_over,
            size: math.max(12.0, height * 0.45),
            color: const Color(0xFFB8E1FF),
          ),
          const SizedBox(width: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(170),
              fontSize: math.max(9.0, fontSize * 0.85),
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: items.isEmpty
                ? _FallbackText(text: fallback, fontSize: fontSize)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _PronunciationChip(
                              item: item,
                              active: item.tokenIndex == currentTokenIndex,
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
      color: Colors.white.withAlpha(210),
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
            ? const Color(0xFFB8E1FF).withAlpha(225)
            : Colors.white.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active
              ? Colors.white.withAlpha(150)
              : Colors.white.withAlpha(42),
        ),
      ),
      child: Text(
        item.ipa,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? Colors.black.withAlpha(220) : Colors.white70,
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
