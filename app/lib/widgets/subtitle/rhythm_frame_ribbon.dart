import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timeline.dart';

typedef RhythmCueLoopCallback =
    void Function(Duration start, Duration end, String label);

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
    this.fontSize = 12.0,
    this.height = 30.0,
    this.tooltip,
    this.onLoopCue,
  });

  final RhythmFrame frame;
  final Duration position;
  final String title;
  final String anchorLabel;
  final String weakGroupLabel;
  final String compressionLabel;
  final String hotspotLabel;
  final double fontSize;
  final double height;
  final String? tooltip;
  final RhythmCueLoopCallback? onLoopCue;

  @override
  Widget build(BuildContext context) {
    final items = _items();
    if (items.isEmpty && frame.phraseBoundaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Semantics(
      label: tooltip ?? title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          if (!maxWidth.isFinite || maxWidth <= 0) {
            return const SizedBox.shrink();
          }
          final timeline = _TimelineRange.from(
            items: items,
            boundaries: frame.phraseBoundaries,
          );
          final leadingWidth = math.min(
            math.max(74.0, height * 3.0),
            maxWidth * 0.34,
          );
          final timelineWidth = math.max(0.0, maxWidth - leadingWidth - 8);
          final chipHeight = math.max(18.0, height * 0.52);
          final laneHeight = math.max(8.0, height * 0.24);
          final labels = _labelItems(items);

          return SizedBox(
            height: height * 1.42,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: leadingWidth,
                  child: _RhythmBadge(
                    title: title,
                    confidence: frame.quality.rhythmConfidence,
                    height: height,
                    fontSize: fontSize,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: timelineWidth,
                        height: laneHeight,
                        child: _RhythmTimeline(
                          items: items,
                          boundaries: frame.phraseBoundaries,
                          range: timeline,
                          position: position,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: chipHeight,
                        child: labels.isEmpty
                            ? _QuietConfidence(
                                confidence: frame.quality.rhythmConfidence,
                                fontSize: fontSize,
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final item in labels)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 5,
                                        ),
                                        child: _RhythmChip(
                                          item: item,
                                          position: position,
                                          fontSize: fontSize,
                                          height: chipHeight,
                                          onLoopCue: onLoopCue,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }

  List<_RhythmItem> _items() {
    final values = <_RhythmItem>[];
    for (final nucleus in frame.nuclei) {
      values.add(
        _RhythmItem(
          kind: 'Nucleus',
          label: nucleus.label,
          start: nucleus.start,
          end: nucleus.end,
          confidence: nucleus.confidence,
          color: const Color(0xFFFF7DA8),
          priority: 0,
          tooltip: _tooltip(
            'Nucleus',
            nucleus.label,
            nucleus.reason,
            provenance: _provenance(
              nucleus.cues,
              nucleus.evidenceClass,
              nucleus.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final anchor in frame.stressAnchors) {
      values.add(
        _RhythmItem(
          kind: anchorLabel,
          label: anchor.label,
          start: anchor.start,
          end: anchor.end,
          confidence: anchor.confidence,
          color: const Color(0xFFFFD166),
          priority: anchor.importance == 'primary' ? 1 : 2,
          tooltip: _tooltip(
            anchorLabel,
            anchor.label,
            anchor.reason,
            provenance: _provenance(
              anchor.prominenceCues,
              anchor.evidenceClass,
              anchor.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final group in frame.weakGroups) {
      values.add(
        _RhythmItem(
          kind: weakGroupLabel,
          label: group.label,
          start: group.start,
          end: group.end,
          confidence: group.confidence,
          color: const Color(0xFF9BE7A2),
          priority: 3,
          tooltip: _tooltip(
            weakGroupLabel,
            group.label,
            group.reason,
            provenance: _provenance(
              group.signalSources,
              group.evidenceClass,
              group.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final span in frame.compressionSpans) {
      values.add(
        _RhythmItem(
          kind: compressionLabel,
          label: span.label,
          start: span.start,
          end: span.end,
          confidence: span.confidence,
          color: const Color(0xFFFF9F6E),
          priority: 4,
          tooltip: _tooltip(
            compressionLabel,
            span.label,
            span.reason,
            provenance: _provenance(
              span.signalSources,
              span.evidenceClass,
              span.claimStatus,
            ),
          ),
        ),
      );
    }
    for (final hotspot in frame.listeningHotspots) {
      values.add(
        _RhythmItem(
          kind: hotspotLabel,
          label: hotspot.label,
          start: hotspot.start,
          end: hotspot.end,
          confidence: hotspot.confidence,
          color: const Color(0xFF8FD3FF),
          priority: 5,
          tooltip: _tooltip(
            hotspotLabel,
            hotspot.label,
            hotspot.hint,
            provenance: _provenance(
              hotspot.signalSources,
              hotspot.evidenceClass,
              hotspot.claimStatus,
            ),
          ),
        ),
      );
    }
    values.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.priority.compareTo(b.priority);
    });
    return values;
  }

  List<_RhythmItem> _labelItems(List<_RhythmItem> items) {
    final active = items.where((item) => item.contains(position)).toList();
    final rest = items.where((item) => !item.contains(position)).toList();
    active.sort((a, b) => a.priority.compareTo(b.priority));
    return [...active, ...rest].take(8).toList(growable: false);
  }

  String _tooltip(
    String kind,
    String label,
    String detail, {
    String? provenance,
  }) {
    final trimmed = detail.trim();
    final lines = <String>['$kind: $label'];
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
  });

  final String title;
  final double confidence;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    height: math.max(24.0, height * 0.86),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF1E2746).withAlpha(210),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: Colors.white.withAlpha(45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.multiline_chart,
          size: math.max(13.0, height * 0.42),
          color: const Color(0xFFFFD166),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(230),
              fontSize: math.max(10.0, fontSize * 0.82),
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          _formatPercent(confidence),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withAlpha(155),
            fontSize: math.max(8.0, fontSize * 0.68),
            height: 1.0,
          ),
        ),
      ],
    ),
  );
}

class _RhythmTimeline extends StatelessWidget {
  const _RhythmTimeline({
    required this.items,
    required this.boundaries,
    required this.range,
    required this.position,
  });

  final List<_RhythmItem> items;
  final List<RhythmPhraseBoundary> boundaries;
  final _TimelineRange range;
  final Duration position;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0 || range.durationMs <= 0) {
        return const SizedBox.shrink();
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            for (final item in items)
              Positioned(
                left: range.leftFor(item.start, width),
                top: 0,
                bottom: 0,
                width: range.widthFor(item.start, item.end, width),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: item.color.withAlpha(
                      item.contains(position) ? 245 : 185,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            for (final boundary in boundaries)
              Positioned(
                left: range.leftFor(boundary.at, width),
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: Colors.white.withAlpha(155)),
              ),
            if (range.contains(position))
              Positioned(
                left: range.leftFor(position, width),
                top: 0,
                bottom: 0,
                width: 2,
                child: const ColoredBox(color: Colors.white),
              ),
          ],
        ),
      );
    },
  );
}

class _RhythmChip extends StatelessWidget {
  const _RhythmChip({
    required this.item,
    required this.position,
    required this.fontSize,
    required this.height,
    this.onLoopCue,
  });

  final _RhythmItem item;
  final Duration position;
  final double fontSize;
  final double height;
  final RhythmCueLoopCallback? onLoopCue;

  @override
  Widget build(BuildContext context) {
    final active = item.contains(position);
    final chip = Container(
      constraints: BoxConstraints(
        minWidth: math.max(58.0, fontSize * 4.8),
        maxWidth: math.max(96.0, fontSize * 9.2),
      ),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: item.color.withAlpha(active ? 230 : 135),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: active
              ? Colors.white.withAlpha(190)
              : item.color.withAlpha(160),
        ),
      ),
      child: Text(
        '${item.label} ${_formatPercent(item.confidence)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.black.withAlpha(active ? 240 : 215),
          fontSize: math.max(9.0, fontSize * 0.82),
          height: 1.0,
          fontWeight: active ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
    final interactive = onLoopCue == null
        ? chip
        : Semantics(
            button: true,
            label: item.tooltip,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onLoopCue!(item.start, item.end, item.label),
                child: chip,
              ),
            ),
          );
    return Tooltip(message: item.tooltip, child: interactive);
  }
}

class _QuietConfidence extends StatelessWidget {
  const _QuietConfidence({required this.confidence, required this.fontSize});

  final double confidence;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Text(
    _formatPercent(confidence),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white.withAlpha(145),
      fontSize: math.max(9.0, fontSize * 0.8),
      height: 1.0,
    ),
  );
}

class _RhythmItem {
  const _RhythmItem({
    required this.kind,
    required this.label,
    required this.start,
    required this.end,
    required this.confidence,
    required this.color,
    required this.priority,
    required this.tooltip,
  });

  final String kind;
  final String label;
  final Duration start;
  final Duration end;
  final double confidence;
  final Color color;
  final int priority;
  final String tooltip;

  bool contains(Duration position) => position >= start && position < end;
}

class _TimelineRange {
  const _TimelineRange({required this.startMs, required this.endMs});

  factory _TimelineRange.from({
    required List<_RhythmItem> items,
    required List<RhythmPhraseBoundary> boundaries,
  }) {
    var startMs = 0;
    var endMs = 1;
    if (items.isNotEmpty) {
      startMs = items.first.start.inMilliseconds;
      endMs = items.first.end.inMilliseconds;
      for (final item in items.skip(1)) {
        startMs = math.min(startMs, item.start.inMilliseconds);
        endMs = math.max(endMs, item.end.inMilliseconds);
      }
    }
    for (final boundary in boundaries) {
      startMs = math.min(startMs, boundary.at.inMilliseconds);
      endMs = math.max(endMs, boundary.at.inMilliseconds);
    }
    if (endMs <= startMs) endMs = startMs + 1;
    return _TimelineRange(startMs: startMs, endMs: endMs);
  }

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  bool contains(Duration value) {
    final ms = value.inMilliseconds;
    return ms >= startMs && ms <= endMs;
  }

  double leftFor(Duration value, double width) {
    final ratio = (value.inMilliseconds - startMs) / durationMs;
    return (ratio * width).clamp(0.0, math.max(0.0, width - 1)).toDouble();
  }

  double widthFor(Duration start, Duration end, double width) {
    final raw =
        (end.inMilliseconds - start.inMilliseconds) / durationMs * width;
    return raw.clamp(3.0, width).toDouble();
  }
}

String _formatPercent(double value) =>
    '${(value.clamp(0.0, 1.0) * 100).round()}%';
