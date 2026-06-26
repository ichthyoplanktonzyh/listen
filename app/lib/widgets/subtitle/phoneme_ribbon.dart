import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';

class PhonemeRibbon extends StatelessWidget {
  const PhonemeRibbon({
    super.key,
    required this.phones,
    required this.position,
    this.fontSize = 12.0,
    this.height = 28.0,
    this.gap = 1.0,
    this.style = 'window',
    this.syllables = const [],
    this.prosodicPhrases = const [],
    this.findings = const [],
  });

  final List<DetectedPhone> phones;
  final Duration position;
  final double fontSize;
  final double height;
  final double gap;
  final String style;
  final List<SoundSyllable> syllables;
  final List<SoundProsodicPhrase> prosodicPhrases;
  final List<PhonemeRibbonFinding> findings;

  @override
  Widget build(BuildContext context) {
    if (phones.isEmpty) return const SizedBox.shrink();

    final totalMs = _totalDuration();
    if (totalMs <= 0) return const SizedBox.shrink();

    final currentIdx = _currentIndex();
    final markers = _RibbonMarkers.from(
      syllables: syllables,
      prosodicPhrases: prosodicPhrases,
      findings: findings,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        final fullReadableWidth =
            phones.length * _readableCellWidth + gap * (phones.length - 1);
        final canShowFull = fullReadableWidth <= maxWidth;

        return SizedBox(
          height: height * 1.35,
          child: canShowFull
              ? _FullRibbon(
                  phones: phones,
                  widths: _fullCellWidths(maxWidth, totalMs),
                  currentIdx: currentIdx,
                  height: height,
                  fontSize: fontSize,
                  gap: gap,
                  wave: style == 'wave',
                  markers: markers,
                )
              : _WindowRibbon(
                  phones: phones,
                  currentIdx: currentIdx,
                  height: height,
                  fontSize: fontSize,
                  gap: gap,
                  maxWidth: maxWidth,
                  markers: markers,
                ),
        );
      },
    );
  }

  double get _readableCellWidth => math.max(18.0, fontSize * 1.7);

  int _currentIndex() {
    var best = 0;
    var bestDist = double.infinity;
    final posMs = position.inMilliseconds;
    for (var i = 0; i < phones.length; i++) {
      if (posMs >= phones[i].start.inMilliseconds &&
          posMs < phones[i].end.inMilliseconds) {
        return i;
      }
      final mid =
          (phones[i].start.inMilliseconds + phones[i].end.inMilliseconds) ~/ 2;
      final d = (posMs - mid).abs().toDouble();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  double _totalDuration() {
    if (phones.isEmpty) return 0;
    final first = phones.first.start.inMilliseconds;
    final last = phones.last.end.inMilliseconds;
    return (last - first).toDouble();
  }

  List<double> _fullCellWidths(double maxWidth, double totalMs) {
    final available =
        maxWidth - gap * (phones.length - 1).clamp(0, phones.length);
    final base = _readableCellWidth;
    final extra = math.max(0.0, available - base * phones.length);
    return [
      for (final phone in phones)
        base +
            extra *
                ((phone.end.inMilliseconds - phone.start.inMilliseconds) /
                    totalMs),
    ];
  }
}

class _RibbonMarkers {
  const _RibbonMarkers({
    required this.syllableStarts,
    required this.phraseStarts,
    required this.findingsByPhone,
  });

  factory _RibbonMarkers.from({
    required List<SoundSyllable> syllables,
    required List<SoundProsodicPhrase> prosodicPhrases,
    required List<PhonemeRibbonFinding> findings,
  }) {
    final syllableStarts = <int>{};
    for (final syllable in syllables) {
      if (syllable.phones.isNotEmpty) syllableStarts.add(syllable.phones.first);
    }
    final phraseStarts = <int>{};
    for (final phrase in prosodicPhrases) {
      if (phrase.syllables.isEmpty) continue;
      final syllableIndex = phrase.syllables.first;
      if (syllableIndex >= 0 && syllableIndex < syllables.length) {
        final syllable = syllables[syllableIndex];
        if (syllable.phones.isNotEmpty) phraseStarts.add(syllable.phones.first);
      }
    }
    phraseStarts.remove(0);
    syllableStarts.remove(0);
    return _RibbonMarkers(
      syllableStarts: syllableStarts,
      phraseStarts: phraseStarts,
      findingsByPhone: _findingsByPhone(findings),
    );
  }

  final Set<int> syllableStarts;
  final Set<int> phraseStarts;
  final Map<int, List<PhonemeRibbonFinding>> findingsByPhone;

  bool phraseBefore(int phoneIndex) => phraseStarts.contains(phoneIndex);
  bool syllableBefore(int phoneIndex) => syllableStarts.contains(phoneIndex);
  List<PhonemeRibbonFinding> findingsFor(int phoneIndex) =>
      findingsByPhone[phoneIndex] ?? const [];

  static Map<int, List<PhonemeRibbonFinding>> _findingsByPhone(
    List<PhonemeRibbonFinding> findings,
  ) {
    final values = <int, List<PhonemeRibbonFinding>>{};
    for (final finding in findings) {
      for (var index = finding.phoneStart; index <= finding.phoneEnd; index++) {
        values.putIfAbsent(index, () => []).add(finding);
      }
    }
    return values;
  }
}

class _FullRibbon extends StatelessWidget {
  const _FullRibbon({
    required this.phones,
    required this.widths,
    required this.currentIdx,
    required this.height,
    required this.fontSize,
    required this.gap,
    required this.wave,
    required this.markers,
  });

  final List<DetectedPhone> phones;
  final List<double> widths;
  final int currentIdx;
  final double height;
  final double fontSize;
  final double gap;
  final bool wave;
  final _RibbonMarkers markers;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (var i = 0; i < phones.length; i++) ...[
        if (i > 0) _PhoneSeparator(markers: markers, phoneIndex: i, gap: gap),
        _PhoneCell(
          phone: phones[i],
          width: widths[i],
          height: height,
          fontSize: fontSize,
          isCurrent: i == currentIdx,
          elevated: wave,
          findings: markers.findingsFor(i),
        ),
      ],
    ],
  );
}

class _WindowRibbon extends StatelessWidget {
  const _WindowRibbon({
    required this.phones,
    required this.currentIdx,
    required this.height,
    required this.fontSize,
    required this.gap,
    required this.maxWidth,
    required this.markers,
  });

  final List<DetectedPhone> phones;
  final int currentIdx;
  final double height;
  final double fontSize;
  final double gap;
  final double maxWidth;
  final _RibbonMarkers markers;

  @override
  Widget build(BuildContext context) {
    final cellWidth = _windowCellWidth();
    final count = _visibleCount(cellWidth);
    final start = _windowStart(count);
    final end = start + count;
    final visiblePhones = phones.sublist(start, end);
    final hasLeft = start > 0;
    final hasRight = end < phones.length;

    return _edgeFade(
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < visiblePhones.length; i++) ...[
            if (i > 0)
              _PhoneSeparator(
                markers: markers,
                phoneIndex: start + i,
                gap: gap,
              ),
            _PhoneCell(
              phone: visiblePhones[i],
              width: cellWidth,
              height: height,
              fontSize: fontSize,
              isCurrent: start + i == currentIdx,
              elevated: false,
              findings: markers.findingsFor(start + i),
            ),
          ],
        ],
      ),
      fadeLeft: hasLeft,
      fadeRight: hasRight,
    );
  }

  double _windowCellWidth() {
    final target = math.max(22.0, fontSize * 2.25);
    if (maxWidth >= target * 3 + gap * 2) return target;
    return math.max(14.0, (maxWidth - gap * 2) / 3);
  }

  int _visibleCount(double cellWidth) {
    var count = ((maxWidth + gap) / (cellWidth + gap)).floor();
    count = count.clamp(1, phones.length).toInt();
    if (count > 1 && count.isEven) count -= 1;
    return math.max(1, count);
  }

  int _windowStart(int count) {
    if (count >= phones.length) return 0;
    final stride = math.max(1, count - 2);
    final page = currentIdx ~/ stride;
    final start = page * stride;
    return start.clamp(0, phones.length - count).toInt();
  }

  Widget _edgeFade(
    Widget child, {
    required bool fadeLeft,
    required bool fadeRight,
  }) {
    if (!fadeLeft && !fadeRight) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [
          fadeLeft ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          fadeRight ? Colors.transparent : Colors.black,
        ],
        stops: const [0, 0.08, 0.92, 1],
      ).createShader(rect),
      child: child,
    );
  }
}

class _PhoneSeparator extends StatelessWidget {
  const _PhoneSeparator({
    required this.markers,
    required this.phoneIndex,
    required this.gap,
  });

  final _RibbonMarkers markers;
  final int phoneIndex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (markers.phraseBefore(phoneIndex)) {
      return Container(
        width: math.max(5.0, gap * 4),
        height: 22,
        alignment: Alignment.center,
        child: Container(width: 1.4, color: Colors.white.withAlpha(190)),
      );
    }
    if (markers.syllableBefore(phoneIndex)) {
      return SizedBox(width: math.max(4.0, gap * 3));
    }
    return SizedBox(width: gap);
  }
}

class _PhoneCell extends StatelessWidget {
  const _PhoneCell({
    required this.phone,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.isCurrent,
    required this.elevated,
    required this.findings,
  });

  final DetectedPhone phone;
  final double width;
  final double height;
  final double fontSize;
  final bool isCurrent;
  final bool elevated;
  final List<PhonemeRibbonFinding> findings;

  @override
  Widget build(BuildContext context) {
    final color = _phoneColor(phone.symbol);
    final confidence = phone.confidence ?? 0.8;
    final alpha = isCurrent ? 1.0 : (0.3 + confidence * 0.3).clamp(0.2, 0.6);
    final targetHeight = isCurrent
        ? height * (elevated ? 1.16 : 1.08)
        : height * 0.86;
    final textFontSize = math.min(fontSize, math.max(8.0, width * 0.56));

    final marker = _FindingMarker.from(findings);
    final cell = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: width,
      height: targetHeight,
      decoration: BoxDecoration(
        color: color.withAlpha((alpha * 255).round()),
        borderRadius: BorderRadius.circular(3),
        border: isCurrent
            ? Border.all(color: Colors.white.withAlpha(210), width: 1.2)
            : null,
        boxShadow: isCurrent && elevated
            ? [
                BoxShadow(
                  color: color.withAlpha(80),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (width >= 14)
            Center(
              child: Text(
                phone.displayIpa,
                style: TextStyle(
                  fontSize: textFontSize,
                  color: isCurrent ? Colors.white : Colors.white70,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                  height: 1.0,
                ),
                overflow: TextOverflow.clip,
                maxLines: 1,
              ),
            ),
          if (marker != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: marker.strong ? 3.0 : 2.0,
                margin: const EdgeInsets.only(left: 3, right: 3, bottom: 2),
                decoration: BoxDecoration(
                  color: marker.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
    if (marker == null) return cell;
    return Tooltip(message: marker.tooltip, child: cell);
  }

  static Color _phoneColor(String symbol) {
    final s = symbol.toUpperCase();
    if (_vowels.contains(s)) return const Color(0xFF5B8DEF);
    if (_approximants.contains(s)) return const Color(0xFF7BC47F);
    return const Color(0xFFE8935A);
  }

  static const _vowels = {
    'AA',
    'AE',
    'AH',
    'AO',
    'AW',
    'AX',
    'AY',
    'EH',
    'ER',
    'EY',
    'IH',
    'IY',
    'OW',
    'OY',
    'UH',
    'UW',
  };

  static const _approximants = {'W', 'Y', 'R', 'L', 'HH'};
}

class _FindingMarker {
  const _FindingMarker({
    required this.strong,
    required this.color,
    required this.tooltip,
  });

  static _FindingMarker? from(List<PhonemeRibbonFinding> findings) {
    final detected = findings.where((value) => value.detectedInAudio).toList();
    final selected = detected.isNotEmpty ? detected : findings;
    final finding = selected.isEmpty ? null : selected.first;
    if (finding == null) return null;
    final confidence = (finding.confidence * 100).round();
    return _FindingMarker(
      strong: finding.detectedInAudio,
      color: finding.detectedInAudio
          ? const Color(0xFFFFD166)
          : const Color(0xFFB8E1FF).withAlpha(185),
      tooltip: '${finding.findingType} · ${finding.status} · $confidence%',
    );
  }

  final bool strong;
  final Color color;
  final String tooltip;
}
