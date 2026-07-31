import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../common/ambient_breath.dart';
import 'following_structure_viewport.dart';

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
    this.expandTooltip = 'Show full sentence',
    this.collapseTooltip = 'Collapse sentence',
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
  final String expandTooltip;
  final String collapseTooltip;

  // ── Optical geometry ──
  // Every inset in this ribbon and its parts is measured against the *rendered
  // subtitle* — the user's own font size, scaled by the video frame — rather
  // than against the app's window grid, so they are deliberately off the
  // `ListenSpacing` ladder (see that class's scope note). Snapping them to
  // 2·4·6·8 would not tidy a rhythm; it would decouple each mark from the glyph
  // it annotates, and at overlay scale that reads immediately. They are named
  // on the widgets that own them, because a ratio one instrument uses is
  // element geometry and would be a fake vocabulary in `lib/theme/`.

  /// Air between two beats in the sequence, trailing-only so the row starts
  /// flush with its container's edge. Wider than the seam between phones because
  /// a beat is a group (label + sound label) and the eye has to see where one
  /// group ends.
  static const _beatSeam = 7.0;

  @override
  Widget build(BuildContext context) {
    final items = _audibleItems();
    if (items.isEmpty && frame.phraseBoundaries.isEmpty) {
      return const SizedBox.shrink();
    }
    final sequence = _sequence(items);

    final content = Semantics(
      label: tooltip ?? title,
      child: Row(
        mainAxisSize: MainAxisSize.max,
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
          const SizedBox(width: ListenSpacing.gap8),
          Expanded(
            child: FollowingStructureViewport(
              activeIndex: sequence.indexWhere((entry) => entry.active),
              spacing: 0,
              expandTooltip: expandTooltip,
              collapseTooltip: collapseTooltip,
              children: sequence.map((entry) => entry.widget).toList(),
            ),
          ),
        ],
      ),
    );

    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }

  List<_SequenceNode> _sequence(List<_AudibleItem> items) {
    final widgets = <_SequenceNode>[];
    var boundaryCursor = 0;
    final boundaries = [...frame.phraseBoundaries]
      ..sort((a, b) => a.at.compareTo(b.at));
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      while (boundaryCursor < boundaries.length &&
          boundaries[boundaryCursor].at <= item.start) {
        if (widgets.isNotEmpty) {
          widgets.add(
            _SequenceNode(
              widget: _PhraseDivider(
                boundary: boundaries[boundaryCursor],
                height: height,
              ),
            ),
          );
        }
        boundaryCursor += 1;
      }
      final active = item.contains(position);
      final isLastBeat = index == items.length - 1;
      widgets.add(
        _SequenceNode(
          active: active,
          widget: Padding(
            padding: EdgeInsets.only(right: isLastBeat ? 0 : _beatSeam),
            child: _AudibleNode(
              item: item,
              active: active,
              fontSize: fontSize,
              height: height,
              onLoopCue: onLoopCue,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<_AudibleItem> _audibleItems() {
    final values = <_AudibleItem>[..._actualConnectedItems()];
    if (frame.informationAnchors.isNotEmpty) {
      for (final anchor in frame.informationAnchors) {
        if (!predicted &&
            !anchor.isAudioSupported &&
            anchor.claimStatus != 'audio_supported') {
          continue;
        }
        final sound = anchor.sound.trim();
        values.add(
          _AudibleItem(
            kind: anchor.isNucleus ? _AudibleKind.nucleus : _AudibleKind.anchor,
            label: sound.isEmpty ? anchor.label : sound,
            caption: sound.isEmpty ? '' : anchor.label,
            start: anchor.start,
            end: anchor.end,
            confidence: anchor.confidence,
            tooltip: _tooltip(
              anchor.isNucleus ? 'Nucleus' : anchorLabel,
              anchor.label,
              anchor.reason,
              display: sound.isEmpty ? anchor.label : sound,
              provenance: _provenance(
                anchor.cues.isEmpty ? anchor.signalSources : anchor.cues,
                anchor.evidenceClass,
                anchor.claimStatus,
              ),
            ),
          ),
        );
      }
      values.addAll(_weakItems());
      values.sort(_audibleSort);
      return values;
    }

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
      final item = _weakItem(group);
      if (item != null) values.add(item);
    }
    values.sort(_audibleSort);
    return values;
  }

  List<_AudibleItem> _actualConnectedItems() {
    if (predicted) return const [];
    final values = <_AudibleItem>[];
    for (final reference in frame.connectedSpeechRefs) {
      final structure = reference.actualStructure;
      if (structure == null ||
          structure.learnerCue.trim().isEmpty ||
          !reference.signalSources.contains('phone_segmental')) {
        continue;
      }
      ListeningHotspot? hotspot;
      for (final value in frame.listeningHotspots) {
        if (value.kind == 'connected_speech' &&
            value.tokenStart == reference.tokenStart &&
            value.tokenEnd == reference.tokenEnd &&
            value.label == reference.label) {
          hotspot = value;
          break;
        }
      }
      if (hotspot == null || hotspot.end <= hotspot.start) continue;
      final family = (reference.family ?? reference.label).replaceAll('_', ' ');
      values.add(
        _AudibleItem(
          kind: _AudibleKind.connected,
          label: structure.learnerCue,
          caption: reference.surfaceText,
          start: hotspot.start,
          end: hotspot.end,
          confidence: reference.confidence,
          tooltip: [
            'Actual audible structure: ${reference.surfaceText}',
            '/${structure.displayIpa}/',
            family,
            'audio supported · phone segmental',
          ].join('\n'),
        ),
      );
    }
    return values;
  }

  List<_AudibleItem> _weakItems() => frame.weakGroups
      .map(_weakItem)
      .whereType<_AudibleItem>()
      .toList(growable: false);

  _AudibleItem? _weakItem(RhythmWeakGroup group) {
    if (!predicted &&
        !group.isAudioSupported &&
        group.claimStatus != 'audio_supported') {
      return null;
    }
    final audibleLabel = _weakGroupSound(group);
    return _AudibleItem(
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
    );
  }

  int _audibleSort(_AudibleItem a, _AudibleItem b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return a.kind.index.compareTo(b.kind.index);
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

  /// Optical geometry (see [RhythmFrameRibbon]): the badge's own inset, one
  /// named value per axis because the two are different decisions. The badge's
  /// height is already pinned to the subtitle row, so the vertical value only
  /// has to centre the label inside that height; the horizontal one is what
  /// keeps the title off the border at any subtitle size.
  static const _badgeInsetX = 7.0;
  static const _badgeInsetY = ListenSpacing.gap4;

  @override
  Widget build(BuildContext context) => Container(
    height: math.max(24.0, height * 0.86),
    padding: const EdgeInsets.symmetric(
      horizontal: _badgeInsetX,
      vertical: _badgeInsetY,
    ),
    decoration: BoxDecoration(
      color: ListenColors.overlaySurface,
      borderRadius: ListenRadii.controlBorder,
      border: Border.all(color: ListenColors.overlayBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.hearing,
          size: math.max(13.0, height * 0.42),
          color: predicted
              ? ListenColors.soundPredicted
              : ListenColors.soundActual,
        ),
        const SizedBox(width: ListenSpacing.gap4),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ListenColors.overlayText,
              fontSize: math.max(10.0, fontSize * 0.82),
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: ListenSpacing.gap4),
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
              color: ListenColors.overlayTextMuted,
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

  /// Optical geometry (see [RhythmFrameRibbon]): this pill is nested *inside*
  /// [_RhythmBadge], which has already spent its own inset, so the pill only
  /// gets the remainder — one notch narrower across, and a hairline down, since
  /// the badge's height is fixed and any real vertical padding here would push
  /// the pill past it.
  static const _pillInsetX = 5.0;
  static const _pillInsetY = 1.0;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: _pillInsetX,
      vertical: _pillInsetY,
    ),
    decoration: BoxDecoration(
      color: ListenColors.soundPredicted.withAlpha(58),
      borderRadius: ListenRadii.tightBorder,
      border: Border.all(color: ListenColors.soundPredicted.withAlpha(160)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: ListenColors.soundPredictedText,
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

  // ── Optical geometry ──
  // See [RhythmFrameRibbon]. A weak syllable is drawn *tighter* than a stressed
  // one on purpose — the rhythm is carried by the spacing as much as by the
  // weight, so these two pairs of values are the shape of the beat itself and
  // cannot be flattened onto one ladder step.

  /// Air on either side of the beat's own skeleton. Tracks the type size so a
  /// stressed beat keeps its room at every subtitle size.
  static double _beatInset(double fontSize, {required bool weak}) =>
      weak ? ListenSpacing.gap2 : math.max(4, fontSize * 0.3);

  /// Air added by the hit target when the beat is tappable, so a click lands on
  /// the beat rather than between two of them. Vertical tracks the row height.
  static double _hitInsetHorizontal({required bool weak}) => weak ? 1 : 3;

  static double _hitInsetVertical(double height) => math.max(2, height * 0.08);

  @override
  Widget build(BuildContext context) {
    final nucleus = item.kind == _AudibleKind.nucleus;
    final connected = item.kind == _AudibleKind.connected;
    final weak = item.kind == _AudibleKind.weak;
    final color = nucleus
        ? ListenColors.soundNucleus
        : weak
        ? ListenColors.overlayText
        : ListenColors.soundActual;
    final opacity = weak
        ? active
              ? 0.68
              : 0.34
        : active
        ? 1.0
        : 0.82;
    final labelSize = weak
        ? math.max(9.0, fontSize * 0.78)
        : math.max(12.0, fontSize * (nucleus ? 1.18 : 1.02));
    // Weak groups keep showing their audible sound shape (item.label), never
    // the written caption — what recedes is still what you hear.
    final meaningLabel = connected || weak
        ? item.label
        : item.caption.isEmpty
        ? item.label
        : item.caption;
    final soundLabel = connected
        ? item.caption
        : item.caption.isEmpty
        ? ''
        : '/${item.label}/';
    final foreground = !weak;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // The glowing rhythm skeleton (#31): a beat bar above each label carries
    // the stress level as height — nucleus tallest, anchors mid, connected
    // low, weak groups nearly flat — and only stressed bars glow, the current
    // beat brightest. Hues keep the existing sound vocabulary untouched; this
    // redesign reorders light, not meaning. The old capsule wash/border is
    // gone — boxes made every beat equally loud (charter principle 5).
    final barFraction = nucleus
        ? 0.56
        : connected
        ? 0.3
        : weak
        ? 0.14
        : 0.42;
    final barHeight = height * barFraction * (active ? 1.12 : 1.0);
    final barWidth = weak
        ? math.max(10.0, labelSize * 1.1)
        : math.max(18.0, labelSize * 1.5);
    final glowing = foreground && (active || nucleus);
    final barBox = AnimatedContainer(
      // Beat-synced emphasis: the fastest step, so it lands within the beat.
      duration: reduceMotion ? Duration.zero : ListenMotion.tap,
      width: barWidth,
      height: barHeight,
      decoration: BoxDecoration(
        color: color.withAlpha(
          weak
              ? (active ? 120 : 70)
              : active
              ? 255
              : nucleus
              ? 230
              : 200,
        ),
        borderRadius: ListenRadii.tightBorder,
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: color.withAlpha(active ? 140 : 90),
                  blurRadius: active ? 12 : 8,
                ),
              ]
            : null,
      ),
    );
    // The current beat breathes at the ambient tempo (#46 signature action):
    // opacity and glow swell together — alive but quiet, never a jump.
    // AmbientBreath itself goes still under reduce motion.
    final bar = active ? AmbientBreath(child: barBox) : barBox;
    // Bars share one baseline (align at their feet) so the skeleton reads as
    // a rhythm silhouette, not floating blocks.
    final skeleton = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height * 0.64,
          child: Align(alignment: Alignment.bottomCenter, child: bar),
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          meaningLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: weak
              ? TextStyle(
                  color: color,
                  fontSize: labelSize,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                )
              : TextStyle(
                  color: ListenColors.overlayText.withAlpha(
                    nucleus ? 242 : 228,
                  ),
                  fontSize: labelSize,
                  height: 1.02,
                  fontWeight: nucleus ? FontWeight.w900 : FontWeight.w800,
                  letterSpacing: 0.2,
                  shadows: active
                      ? [Shadow(color: color.withAlpha(120), blurRadius: 6)]
                      : null,
                ),
        ),
        if (foreground && soundLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              soundLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withAlpha(nucleus ? 235 : 205),
                fontSize: math.max(8.0, fontSize * 0.68),
                height: 1.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.35,
              ),
            ),
          ),
      ],
    );
    final node = AnimatedOpacity(
      // Beat-synced emphasis: the fastest step, so it lands within the beat.
      duration: reduceMotion ? Duration.zero : ListenMotion.tap,
      opacity: opacity,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _beatInset(fontSize, weak: weak),
        ),
        child: skeleton,
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
                    horizontal: _hitInsetHorizontal(weak: weak),
                    vertical: _hitInsetVertical(height),
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

  /// Optical geometry (see [RhythmFrameRibbon]): the divider closes the phrase
  /// on its left, so it sits almost against the beat it follows and gives the
  /// whole gap to the phrase it opens — that asymmetry *is* the boundary. A
  /// symmetric container role would centre the rule between two phrases and lose
  /// which side it belongs to. Only the lead-in is off the ladder; the air on the
  /// opening side is a real gap.
  static const _dividerLeadIn = 1.0;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: boundary.reason,
    child: Container(
      width: 1,
      height: math.max(15, height * 0.58),
      margin: const EdgeInsets.only(
        left: _dividerLeadIn,
        right: ListenSpacing.gap8,
      ),
      color: ListenColors.overlayText.withAlpha(72),
    ),
  );
}

enum _AudibleKind { nucleus, connected, anchor, weak }

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

class _SequenceNode {
  const _SequenceNode({required this.widget, this.active = false});

  final Widget widget;
  final bool active;
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
