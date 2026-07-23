import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

enum PhonemeRibbonLane { text, sound }

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
    this.lane = PhonemeRibbonLane.text,
    this.tooltip,
    this.onLoopFinding,
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
  final PhonemeRibbonLane lane;
  final String? tooltip;
  final ValueChanged<PhonemeRibbonFinding>? onLoopFinding;

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
        final leadingWidth = lane == PhonemeRibbonLane.sound
            ? _SoundRibbonShell.leadingWidth(height)
            : 0.0;
        final ribbonMaxWidth = maxWidth - leadingWidth;
        if (ribbonMaxWidth <= 0) return const SizedBox.shrink();
        final fullReadableWidth =
            phones.length * _readableCellWidth + gap * (phones.length - 1);
        final canShowFull = fullReadableWidth <= ribbonMaxWidth;

        final ribbon = SizedBox(
          height: height * 1.35,
          child: canShowFull
              ? _FullRibbon(
                  phones: phones,
                  widths: _fullCellWidths(ribbonMaxWidth, totalMs),
                  currentIdx: currentIdx,
                  height: height,
                  fontSize: fontSize,
                  gap: gap,
                  wave: style == 'wave',
                  markers: markers,
                  lane: lane,
                  onLoopFinding: onLoopFinding,
                )
              : _WindowRibbon(
                  phones: phones,
                  currentIdx: currentIdx,
                  height: height,
                  fontSize: fontSize,
                  gap: gap,
                  maxWidth: ribbonMaxWidth,
                  markers: markers,
                  lane: lane,
                  onLoopFinding: onLoopFinding,
                ),
        );
        if (lane == PhonemeRibbonLane.text) {
          return tooltip == null
              ? ribbon
              : Tooltip(message: tooltip!, child: ribbon);
        }
        final decorated = _SoundRibbonShell(height: height, child: ribbon);
        return tooltip == null
            ? decorated
            : Tooltip(message: tooltip!, child: decorated);
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

class SoundPatternUnavailableRibbon extends StatelessWidget {
  const SoundPatternUnavailableRibbon({
    super.key,
    required this.message,
    this.tooltip,
    this.fontSize = 11,
    this.height = 24,
  });

  final String message;
  final String? tooltip;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: tooltip ?? message,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq,
              size: math.max(12, height * 0.52),
              color: ListenColors.overlayTextFaint,
            ),
            const SizedBox(width: ListenSpacing.gap4),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ListenColors.overlayTextMuted,
                  fontSize: fontSize,
                  height: 1.0,
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
    required this.lane,
    this.onLoopFinding,
  });

  final List<DetectedPhone> phones;
  final List<double> widths;
  final int currentIdx;
  final double height;
  final double fontSize;
  final double gap;
  final bool wave;
  final _RibbonMarkers markers;
  final PhonemeRibbonLane lane;
  final ValueChanged<PhonemeRibbonFinding>? onLoopFinding;

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
          lane: lane,
          onLoopFinding: onLoopFinding,
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
    required this.lane,
    this.onLoopFinding,
  });

  final List<DetectedPhone> phones;
  final int currentIdx;
  final double height;
  final double fontSize;
  final double gap;
  final double maxWidth;
  final _RibbonMarkers markers;
  final PhonemeRibbonLane lane;
  final ValueChanged<PhonemeRibbonFinding>? onLoopFinding;

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
              lane: lane,
              onLoopFinding: onLoopFinding,
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
        child: Container(
          width: 1.4,
          color: ListenColors.overlayText.withAlpha(190),
        ),
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
    required this.lane,
    this.onLoopFinding,
  });

  final DetectedPhone phone;
  final double width;
  final double height;
  final double fontSize;
  final bool isCurrent;
  final bool elevated;
  final List<PhonemeRibbonFinding> findings;
  final PhonemeRibbonLane lane;
  final ValueChanged<PhonemeRibbonFinding>? onLoopFinding;

  @override
  Widget build(BuildContext context) {
    final color = _phoneColor(phone.symbol, lane);
    final confidence = phone.confidence ?? 0.8;
    final alpha = isCurrent ? 1.0 : (0.3 + confidence * 0.3).clamp(0.2, 0.6);
    final targetHeight = isCurrent
        ? height * (elevated ? 1.16 : 1.08)
        : height * 0.86;
    final textFontSize = math.min(fontSize, math.max(8.0, width * 0.56));

    final marker = _FindingMarker.from(findings);
    final cell = AnimatedContainer(
      // Beat-synced emphasis: the fastest step, so it lands within the phone.
      duration: ListenMotion.tap,
      curve: ListenMotion.enter,
      width: width,
      height: targetHeight,
      decoration: BoxDecoration(
        color: color.withAlpha((alpha * 255).round()),
        borderRadius: BorderRadius.all(
          lane == PhonemeRibbonLane.sound
              ? ListenRadii.control
              : ListenRadii.tight,
        ),
        border: isCurrent
            ? Border.all(
                color: ListenColors.overlayText.withAlpha(210),
                width: 1.2,
              )
            : lane == PhonemeRibbonLane.sound
            ? Border.all(
                color: ListenColors.overlayText.withAlpha(48),
                width: 0.8,
              )
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
                // IPA glyphs render in the dedicated phonetics face (#32).
                style: ListenType.ipa.copyWith(
                  fontSize: textFontSize,
                  color: isCurrent
                      ? ListenColors.overlayText
                      : ListenColors.overlayTextMuted,
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
                  borderRadius: ListenRadii.tightBorder,
                ),
              ),
            ),
        ],
      ),
    );
    if (marker == null) return cell;
    final interactive = onLoopFinding == null
        ? cell
        : Semantics(
            button: true,
            label: marker.tooltip,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onLoopFinding!(marker.finding),
                child: cell,
              ),
            ),
          );
    return Tooltip(message: marker.tooltip, child: interactive);
  }

  static Color _phoneColor(String symbol, PhonemeRibbonLane lane) {
    final s = symbol.toUpperCase();
    if (lane == PhonemeRibbonLane.sound) {
      if (_vowels.contains(s)) return ListenColors.phonemeSoundVowel;
      if (_approximants.contains(s)) {
        return ListenColors.phonemeSoundApproximant;
      }
      return ListenColors.phonemeSoundConsonant;
    }
    if (_vowels.contains(s)) return ListenColors.phonemeTextVowel;
    if (_approximants.contains(s)) {
      return ListenColors.phonemeTextApproximant;
    }
    return ListenColors.phonemeTextConsonant;
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
    required this.finding,
  });

  static _FindingMarker? from(List<PhonemeRibbonFinding> findings) {
    final detected = findings.where((value) => value.detectedInAudio).toList();
    final selected = detected.isNotEmpty ? detected : findings;
    final finding = selected.isEmpty ? null : selected.first;
    if (finding == null) return null;
    return _FindingMarker(
      strong: finding.detectedInAudio,
      color: finding.detectedInAudio
          ? ListenColors.soundActual
          : ListenColors.soundCitation.withAlpha(185),
      tooltip: finding.learnerTooltip,
      finding: finding,
    );
  }

  final bool strong;
  final Color color;
  final String tooltip;
  final PhonemeRibbonFinding finding;
}

class _SoundRibbonShell extends StatelessWidget {
  const _SoundRibbonShell({required this.height, required this.child});

  final double height;
  final Widget child;

  static double leadingWidth(double height) => math.max(12, height * 0.46) + 5;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        Icons.graphic_eq,
        size: math.max(12, height * 0.46),
        color: ListenColors.overlayTextMuted,
      ),
      const SizedBox(width: ListenSpacing.gap4),
      Flexible(child: child),
    ],
  );
}
