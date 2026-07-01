import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';
import '../../models/types.dart';

typedef RhythmCueLoopCallback =
    void Function(Duration start, Duration end, String label);

/// Renders Reference C as a perceptual foreground/background structure.
///
/// The default surface deliberately omits diagnostic categories such as
/// compression spans and hotspots. Learners see the foreground sound shapes
/// worth catching — often a vowel nucleus plus nearby consonant edges — with
/// weak groups receding between them. Detailed phone evidence remains an
/// expandable L4 surface owned by the overlay.
class RhythmFrameRibbon extends StatelessWidget {
  const RhythmFrameRibbon({
    super.key,
    required this.frame,
    required this.position,
    required this.title,
    required this.anchorLabel,
    required this.weakGroupLabel,
    required this.compressionLabel,
    required this.hotspotLabel,
    this.pronunciation,
    this.fontSize = 12.0,
    this.height = 30.0,
    this.tooltip,
    this.onLoopCue,
    this.predicted = false,
    this.predictedLabel,
  });

  final RhythmFrame frame;
  final PronunciationAnalysis? pronunciation;
  final Duration position;
  final String title;
  final String anchorLabel;
  final String weakGroupLabel;

  /// Kept in the constructor because these labels still describe details in
  /// imported frames. They are intentionally not first-class visual lanes.
  final String compressionLabel;
  final String hotspotLabel;
  final double fontSize;
  final double height;
  final String? tooltip;
  final RhythmCueLoopCallback? onLoopCue;

  /// True when the frame has no audio-backed signal source, i.e. it is a
  /// text-prior prediction and must not read as measured audio.
  final bool predicted;
  final String? predictedLabel;

  @override
  Widget build(BuildContext context) {
    final items = _audibleItems();
    if (items.isEmpty && frame.phraseBoundaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Semantics(
      label: tooltip ?? title,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RhythmBadge(
            title: title,
            confidence: frame.quality.rhythmConfidence,
            height: height,
            fontSize: fontSize,
            predicted: predicted,
            predictedLabel: predictedLabel,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _sequence(items),
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

  List<Widget> _sequence(List<_AudibleItem> items) {
    final widgets = <Widget>[];
    var boundaryCursor = 0;
    final boundaries = [...frame.phraseBoundaries]
      ..sort((a, b) => a.at.compareTo(b.at));
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      while (boundaryCursor < boundaries.length &&
          boundaries[boundaryCursor].at <= item.start) {
        if (widgets.isNotEmpty) {
          widgets.add(
            _PhraseDivider(
              boundary: boundaries[boundaryCursor],
              height: height,
            ),
          );
        }
        boundaryCursor += 1;
      }
      widgets.add(
        Padding(
          padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 7),
          child: _AudibleNode(
            item: item,
            active: item.contains(position),
            fontSize: fontSize,
            height: height,
            onLoopCue: onLoopCue,
          ),
        ),
      );
    }
    return widgets;
  }

  List<_AudibleItem> _audibleItems() {
    final values = <_AudibleItem>[];
    final anchorTokens = <int>{};
    for (final anchor in frame.stressAnchors) {
      if (!predicted &&
          !anchor.isAudioSupported &&
          anchor.claimStatus != 'audio_supported') {
        continue;
      }
      if (anchor.tokenIndex != null) anchorTokens.add(anchor.tokenIndex!);
      final nucleus =
          anchor.isNucleus ||
          frame.nuclei.any(
            (value) =>
                value.tokenIndex != null &&
                value.tokenIndex == anchor.tokenIndex,
          );
      final audibleLabel = _audibleSoundShape(anchor.tokenIndex, anchor.label);
      values.add(
        _AudibleItem(
          kind: nucleus ? _AudibleKind.nucleus : _AudibleKind.anchor,
          label: audibleLabel,
          caption: audibleLabel == anchor.label ? '' : anchor.label,
          start: anchor.start,
          end: anchor.end,
          confidence: anchor.confidence,
          tooltip: _tooltip(
            nucleus ? 'Nucleus' : anchorLabel,
            anchor.label,
            anchor.reason,
            display: audibleLabel,
            provenance: _provenance(
              anchor.prominenceCues,
              anchor.evidenceClass,
              anchor.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final nucleus in frame.nuclei) {
      if (!predicted &&
          !_hasAudioCue(nucleus.cues) &&
          nucleus.claimStatus != 'audio_supported') {
        continue;
      }
      if (nucleus.tokenIndex != null &&
          anchorTokens.contains(nucleus.tokenIndex)) {
        continue;
      }
      final audibleLabel = _audibleSoundShape(
        nucleus.tokenIndex,
        nucleus.label,
      );
      values.add(
        _AudibleItem(
          kind: _AudibleKind.nucleus,
          label: audibleLabel,
          caption: audibleLabel == nucleus.label ? '' : nucleus.label,
          start: nucleus.start,
          end: nucleus.end,
          confidence: nucleus.confidence,
          tooltip: _tooltip(
            'Nucleus',
            nucleus.label,
            nucleus.reason,
            display: audibleLabel,
            provenance: _provenance(
              nucleus.cues,
              nucleus.evidenceClass,
              nucleus.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final group in frame.weakGroups) {
      if (!predicted &&
          !group.isAudioSupported &&
          group.claimStatus != 'audio_supported') {
        continue;
      }
      final audibleLabel = _weakGroupSound(group);
      values.add(
        _AudibleItem(
          kind: _AudibleKind.weak,
          label: audibleLabel,
          caption: audibleLabel == group.label ? '' : group.label,
          start: group.start,
          end: group.end,
          confidence: group.confidence,
          tooltip: _tooltip(
            weakGroupLabel,
            group.label,
            group.reason,
            display: audibleLabel,
            provenance: _provenance(
              group.signalSources,
              group.evidenceClass,
              group.claimStatus,
            ),
          ),
        ),
      );
    }
    values.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.kind.index.compareTo(b.kind.index);
    });
    return values;
  }

  String _audibleSoundShape(int? tokenIndex, String fallback) {
    if (tokenIndex == null || pronunciation == null) return fallback;
    WordPronunciation? word;
    for (final value in pronunciation!.words) {
      if (value.tokenIndex == tokenIndex) {
        word = value;
        break;
      }
    }
    if (word == null || word.variants.isEmpty) return fallback;
    final variant = word.variants.first;
    final phones = variant.phonemes
        .where((phone) => _phoneDisplay(phone).isNotEmpty)
        .toList(growable: false);
    if (phones.isNotEmpty) {
      final stressedVowel = phones.indexWhere(
        (phone) => (phone.stress ?? 0) > 0 && _isVowelPhone(phone),
      );
      final firstVowel = phones.indexWhere(_isVowelPhone);
      final nucleusIndex = stressedVowel >= 0 ? stressedVowel : firstVowel;
      if (nucleusIndex >= 0) {
        var start = nucleusIndex;
        while (start > 0 && !_isVowelPhone(phones[start - 1])) {
          start -= 1;
        }
        var end = nucleusIndex;
        while (end + 1 < phones.length && !_isVowelPhone(phones[end + 1])) {
          end += 1;
        }
        final shape = phones
            .sublist(start, end + 1)
            .map(_phoneDisplay)
            .join()
            .trim();
        if (shape.isNotEmpty) return shape;
      }

      final consonantEdge = _phoneDisplay(phones.first).trim();
      if (consonantEdge.isNotEmpty) return consonantEdge;
    }

    // Some providers carry stress only in the compact IPA string. Preserve the
    // marked syllable rather than inventing an observed phone.
    final marked = RegExp(r"[ˈˌ]([^\s.]+)").firstMatch(variant.displayIpa);
    return marked?.group(1)?.trim().isNotEmpty == true
        ? marked!.group(1)!.trim()
        : fallback;
  }

  String _phoneDisplay(PronunciationPhoneme phone) =>
      (phone.displayIpa ?? phone.symbol).trim();

  bool _isVowelPhone(PronunciationPhoneme phone) {
    final symbol = phone.symbol.trim().toUpperCase().replaceAll(
      RegExp(r'\d+$'),
      '',
    );
    return const {
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
    }.contains(symbol);
  }

  String _weakGroupSound(RhythmWeakGroup group) {
    final matching = frame.connectedSpeechRefs.where((reference) {
      final start = reference.tokenStart;
      final end = reference.tokenEnd ?? start;
      final groupStart = group.tokenStart;
      final groupEnd = group.tokenEnd ?? groupStart;
      if (start == null ||
          end == null ||
          groupStart == null ||
          groupEnd == null) {
        return false;
      }
      return start <= groupEnd && end >= groupStart;
    });
    for (final reference in matching) {
      final ipa = reference.defaultDisplayIpa.trim();
      if (ipa.isNotEmpty) return ipa;
    }
    return group.label;
  }

  String _tooltip(
    String kind,
    String label,
    String detail, {
    required String display,
    String? provenance,
  }) {
    final trimmed = detail.trim();
    final lines = <String>['$kind: $label', if (display != label) '/$display/'];
    if (trimmed.isNotEmpty) lines.add(trimmed);
    if (provenance != null && provenance.trim().isNotEmpty) {
      lines.add(provenance);
    }
    return lines.join('\n');
  }

  String _provenance(
    List<String> signalSources,
    String evidenceClass,
    String claimStatus,
  ) {
    final status = claimStatus.replaceAll('_', ' ');
    final evidence = evidenceClass.replaceAll('_', ' ');
    final sources = signalSources.isEmpty
        ? 'no signal source'
        : signalSources.map((value) => value.replaceAll('_', ' ')).join(', ');
    return '$status · $evidence · $sources';
  }
}

class _RhythmBadge extends StatelessWidget {
  const _RhythmBadge({
    required this.title,
    required this.confidence,
    required this.height,
    required this.fontSize,
    this.predicted = false,
    this.predictedLabel,
  });

  final String title;
  final double confidence;
  final double height;
  final double fontSize;
  final bool predicted;
  final String? predictedLabel;

  @override
  Widget build(BuildContext context) => Container(
    height: math.max(24.0, height * 0.86),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF1E2746).withAlpha(190),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: Colors.white.withAlpha(38)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.hearing,
          size: math.max(13.0, height * 0.42),
          color: predicted ? const Color(0xFFFFA94D) : const Color(0xFFFFD166),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(220),
              fontSize: math.max(10.0, fontSize * 0.82),
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 5),
        if (predicted && predictedLabel != null)
          Flexible(
            child: _PredictedPill(label: predictedLabel!, fontSize: fontSize),
          )
        else
          Text(
            _formatPercent(confidence),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(135),
              fontSize: math.max(8.0, fontSize * 0.68),
              height: 1.0,
            ),
          ),
      ],
    ),
  );
}

class _PredictedPill extends StatelessWidget {
  const _PredictedPill({required this.label, required this.fontSize});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFFFA94D).withAlpha(58),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0xFFFFA94D).withAlpha(160)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFFFFC98A),
        fontSize: math.max(8.0, fontSize * 0.66),
        height: 1.0,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _AudibleNode extends StatelessWidget {
  const _AudibleNode({
    required this.item,
    required this.active,
    required this.fontSize,
    required this.height,
    this.onLoopCue,
  });

  final _AudibleItem item;
  final bool active;
  final double fontSize;
  final double height;
  final RhythmCueLoopCallback? onLoopCue;

  @override
  Widget build(BuildContext context) {
    final nucleus = item.kind == _AudibleKind.nucleus;
    final weak = item.kind == _AudibleKind.weak;
    final color = nucleus
        ? const Color(0xFFFF8FB7)
        : weak
        ? Colors.white
        : const Color(0xFFFFD166);
    final opacity = weak
        ? active
              ? 0.68
              : 0.34
        : active
        ? 1.0
        : 0.82;
    final labelSize = weak
        ? math.max(9.0, fontSize * 0.78)
        : math.max(12.0, fontSize * (nucleus ? 1.3 : 1.12));
    final node = AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: opacity,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: active && !weak ? 1.08 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (nucleus)
              Container(
                width: math.max(15, labelSize * 1.35),
                height: 2,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(color: color.withAlpha(120), blurRadius: 5),
                  ],
                ),
              ),
            Text(
              weak ? item.label : '/${item.label}/',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: labelSize,
                height: 1,
                fontWeight: weak ? FontWeight.w400 : FontWeight.w800,
                letterSpacing: weak ? 0.2 : 0.5,
                shadows: active && !weak
                    ? [Shadow(color: color.withAlpha(150), blurRadius: 7)]
                    : null,
              ),
            ),
            if (item.caption.isNotEmpty)
              Text(
                item.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withAlpha(weak ? 105 : 155),
                  fontSize: math.max(7.0, fontSize * 0.58),
                  height: 1.05,
                ),
              ),
          ],
        ),
      ),
    );
    final interactive = onLoopCue == null
        ? node
        : Semantics(
            button: true,
            label: item.tooltip,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onLoopCue!(
                  item.start,
                  item.end,
                  item.caption.isEmpty ? item.label : item.caption,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: weak ? 1 : 3,
                    vertical: math.max(2, height * 0.08),
                  ),
                  child: node,
                ),
              ),
            ),
          );
    return Tooltip(message: item.tooltip, child: interactive);
  }
}

class _PhraseDivider extends StatelessWidget {
  const _PhraseDivider({required this.boundary, required this.height});

  final RhythmPhraseBoundary boundary;
  final double height;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: boundary.reason,
    child: Container(
      width: 1,
      height: math.max(15, height * 0.58),
      margin: const EdgeInsets.only(left: 1, right: 8),
      color: Colors.white.withAlpha(72),
    ),
  );
}

enum _AudibleKind { nucleus, anchor, weak }

class _AudibleItem {
  const _AudibleItem({
    required this.kind,
    required this.label,
    required this.caption,
    required this.start,
    required this.end,
    required this.confidence,
    required this.tooltip,
  });

  final _AudibleKind kind;
  final String label;
  final String caption;
  final Duration start;
  final Duration end;
  final double confidence;
  final String tooltip;

  bool contains(Duration value) => value >= start && value < end;
}

String _formatPercent(double value) =>
    '${(value.clamp(0.0, 1.0) * 100).round()}%';

bool _hasAudioCue(List<String> values) => values.any(
  (value) =>
      value == 'timing' ||
      value == 'energy' ||
      value == 'pitch' ||
      value == 'phone_segmental',
);
