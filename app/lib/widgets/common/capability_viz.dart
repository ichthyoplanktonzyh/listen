import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// The capability portrait's graphic language (issue #47), shared by the
/// coach dashboard and every vocabulary-entry scale so the two read as one
/// system. Owner-approved direction (design-notes/listen-capability-viz.html):
/// compass ring for the aggregate overview, echo bars for per-channel detail,
/// and the three-state mini ring at entry scales. Rendering only — analysis
/// data and evidence gating stay untouched, and gap annotations juxtapose
/// existing counts instead of deriving new metrics in the frontend.
///
/// Shared 2x2 semantics: sound (listening↔speaking) left, text
/// (reading↔writing) right; reception up, production down. gap-(c) — words
/// recognized on a reception channel but not yet produced — lives inside each
/// column, so the asymmetry between the lit top and the dim bottom *is* the
/// gap, at every scale.
///
/// Quadrant layout in degrees from 12 o'clock, clockwise, with 8° seams at
/// the compass cross. `anchorAtEnd` gathers the acquired light toward
/// 12 o'clock on reception channels and 6 o'clock on production channels.
const _quadrants = <String, (double, double, bool)>{
  'listening': (274, 356, true),
  'reading': (4, 86, false),
  'writing': (94, 176, true),
  'speaking': (184, 266, false),
};

const _channelLabelKeys = <String, String>{
  'listening': 'capabilityListening',
  'reading': 'capabilityReading',
  'speaking': 'capabilitySpeaking',
  'writing': 'capabilityWriting',
};

/// Shared color for a capability channel's effective assessment. Acquired is
/// the signal teal (owner decision: the portrait glows with the same light as
/// content), the practice target is amber — a target, not a failure red — and
/// unassessed stays dimmed but present.
Color capabilityAssessmentColor(ColorScheme colors, String assessment) =>
    switch (assessment) {
      'acquired' => colors.primary,
      'not_acquired' => colors.secondary,
      _ => colors.onSurfaceVariant.withValues(alpha: 0.45),
    };

/// Flattens a capability profile into per-channel effective assessments;
/// a missing profile honestly reads unassessed on every channel.
Map<String, String> capabilityProfileAssessments(
  LexicalCapabilityProfile? profile,
) => {
  'listening': profile?.listening.effectiveAssessment ?? 'unassessed',
  'reading': profile?.reading.effectiveAssessment ?? 'unassessed',
  'speaking': profile?.speaking.effectiveAssessment ?? 'unassessed',
  'writing': profile?.writing.effectiveAssessment ?? 'unassessed',
};

/// The dashboard's gap-(c) headline count comes from the existing cross-modal
/// review suggestion (its evidence count is the backend's join); when the
/// suggestion is absent there is no honest number to show, so callers render
/// the ring without a center figure instead of synthesizing one.
int? crossModalGapCount(CoachDashboard dashboard) {
  for (final suggestion in dashboard.suggestions) {
    if (suggestion.id == 'cross-modal-review') return suggestion.evidenceCount;
  }
  return null;
}

/// Pure segment maths for the compass ring, exposed for tests: returns
/// (startDeg, sweepDeg, assessment) triples inside the channel's quadrant.
/// With zero counts the whole quadrant reads unassessed.
List<(double, double, String)> compassSegments(
  String channel,
  int acquired,
  int notAcquired,
  int unassessed,
) {
  final (start, end, anchorAtEnd) = _quadrants[channel]!;
  final span = end - start;
  final total = acquired + notAcquired + unassessed;
  if (total == 0) return [(start, span, 'unassessed')];
  var states = [
    ('acquired', acquired),
    ('not_acquired', notAcquired),
    ('unassessed', unassessed),
  ];
  // Along the arc the acquired segment sits at the anchor.
  if (anchorAtEnd) states = states.reversed.toList(growable: false);
  final segments = <(double, double, String)>[];
  var cursor = start;
  for (final (state, count) in states) {
    if (count == 0) continue;
    final sweep = span * count / total;
    segments.add((cursor, sweep, state));
    cursor += sweep;
  }
  return segments;
}

double _radians(double degrees) => degrees * math.pi / 180;

/// Three-state four-quadrant ring for a single entry: one solid arc per
/// channel, colored by its effective assessment. Proportions are dropped at
/// this scale on purpose — an entry has states, not shares.
class CapabilityRing extends StatelessWidget {
  const CapabilityRing({
    super.key,
    required this.assessments,
    this.size = 16,
    this.withTooltip = false,
  });

  /// Effective assessment per channel key; missing channels read unassessed.
  final Map<String, String> assessments;
  final double size;
  final bool withTooltip;

  String _describe(AppLocalizations l) => _quadrants.keys
      .map(
        (channel) =>
            '${l.text(_channelLabelKeys[channel]!)}: '
            '${l.text(assessments[channel] ?? 'unassessed')}',
      )
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = _describe(l);
    final ring = Semantics(
      label: label,
      child: CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          assessments: assessments,
          colors: Theme.of(context).colorScheme,
        ),
      ),
    );
    if (!withTooltip) return ring;
    return Tooltip(message: label, child: ring);
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.assessments, required this.colors});

  final Map<String, String> assessments;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final mainStroke = size.width * 0.16;
    final rect =
        Offset(mainStroke / 2, mainStroke / 2) &
        Size.square(size.width - mainStroke);
    for (final entry in _quadrants.entries) {
      final assessment = assessments[entry.key] ?? 'unassessed';
      final dim = assessment != 'acquired' && assessment != 'not_acquired';
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dim ? mainStroke * 0.55 : mainStroke
        ..color = capabilityAssessmentColor(colors, assessment);
      final (start, end, _) = entry.value;
      canvas.drawArc(
        rect,
        _radians(start - 90),
        _radians(end - start),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      !mapEquals(oldDelegate.assessments, assessments);
}

/// Aggregate compass ring: per quadrant the arc splits by assessment share
/// (thick lit teal, thick amber, thin dim for the unassessed stock), and the
/// center carries the gap-(c) count when the backend surfaced one.
class CapabilityCompass extends StatelessWidget {
  const CapabilityCompass({
    super.key,
    required this.channels,
    this.gapCount,
    this.size = 200,
  });

  final List<CoachChannelSummary> channels;
  final int? gapCount;
  final double size;

  CoachAssessmentSummary _counts(String channel) {
    for (final summary in channels) {
      if (summary.channel == channel) return summary.effectiveAssessments;
    }
    return const CoachAssessmentSummary(
      acquired: 0,
      notAcquired: 0,
      unassessed: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tooltip = _quadrants.keys
        .map((channel) {
          final counts = _counts(channel);
          return '${l.text(_channelLabelKeys[channel]!)} · '
              '${l.text('coachAssessmentAcquired')} ${counts.acquired} · '
              '${l.text('coachAssessmentNotAcquired')} ${counts.notAcquired} · '
              '${l.text('coachAssessmentUnassessed')} ${counts.unassessed}';
        })
        .join('\n');
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _CompassPainter(
                counts: {
                  for (final channel in _quadrants.keys)
                    channel: _counts(channel),
                },
                colors: theme.colorScheme,
              ),
            ),
            if (gapCount != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$gapCount',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l.text('capabilityGapCenterLabel'),
                    textAlign: TextAlign.center,
                    style: ListenType.caption.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({required this.counts, required this.colors});

  final Map<String, CoachAssessmentSummary> counts;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final mainStroke = size.width * 0.062;
    final rect =
        Offset(mainStroke / 2, mainStroke / 2) &
        Size.square(size.width - mainStroke);
    for (final entry in counts.entries) {
      final summary = entry.value;
      for (final (start, sweep, state) in compassSegments(
        entry.key,
        summary.acquired,
        summary.notAcquired,
        summary.unassessed,
      )) {
        final dim = state == 'unassessed';
        // At aggregate scale the unassessed stock is a large area, so it dims
        // all the way to the hairline color — present, never competing with
        // the light (the tooltip carries its exact number).
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = dim ? mainStroke * 0.4 : mainStroke
          ..color = dim
              ? colors.outlineVariant
              : capabilityAssessmentColor(colors, state);
        canvas.drawArc(
          rect,
          _radians(start - 90),
          _radians(sweep),
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.colors != colors || !mapEquals(oldDelegate.counts, counts);
}

/// Echo bars: per modality column the reception channel grows up from the
/// baseline and the production channel grows down, so "the light that came
/// in" and "your echo" mirror each other. The reception channel's acquired
/// height is repeated below the baseline as a dashed ghost — the unlit part
/// of the ghost is the gap, drawn rather than computed.
class CapabilityEchoBars extends StatelessWidget {
  const CapabilityEchoBars({
    super.key,
    required this.channels,
    this.barHeight = 96,
  });

  final List<CoachChannelSummary> channels;
  final double barHeight;

  CoachAssessmentSummary _counts(String channel) {
    for (final summary in channels) {
      if (summary.channel == channel) return summary.effectiveAssessments;
    }
    return const CoachAssessmentSummary(
      acquired: 0,
      notAcquired: 0,
      unassessed: 0,
    );
  }

  int _total(CoachAssessmentSummary counts) =>
      counts.acquired + counts.notAcquired + counts.unassessed;

  @override
  Widget build(BuildContext context) {
    // One shared scale across all four channels keeps the bars honest.
    final unit = _quadrants.keys
        .map((channel) => _total(_counts(channel)))
        .fold(0, math.max);
    return Row(
      children: [
        Expanded(
          child: _EchoColumn(
            inChannel: 'listening',
            outChannel: 'speaking',
            inCounts: _counts('listening'),
            outCounts: _counts('speaking'),
            unit: unit,
            barHeight: barHeight,
            gapLabelKey: 'capabilityEchoSound',
            ghostKey: const ValueKey('echo-ghost-sound'),
          ),
        ),
        const SizedBox(width: ListenSpacing.gap24),
        Expanded(
          child: _EchoColumn(
            inChannel: 'reading',
            outChannel: 'writing',
            inCounts: _counts('reading'),
            outCounts: _counts('writing'),
            unit: unit,
            barHeight: barHeight,
            gapLabelKey: 'capabilityEchoText',
            ghostKey: const ValueKey('echo-ghost-text'),
          ),
        ),
      ],
    );
  }
}

class _EchoColumn extends StatelessWidget {
  const _EchoColumn({
    required this.inChannel,
    required this.outChannel,
    required this.inCounts,
    required this.outCounts,
    required this.unit,
    required this.barHeight,
    required this.gapLabelKey,
    required this.ghostKey,
  });

  final String inChannel, outChannel, gapLabelKey;
  final CoachAssessmentSummary inCounts, outCounts;
  final int unit;
  final double barHeight;
  final Key ghostKey;

  double _height(int count) => unit == 0 ? 0 : barHeight * count / unit;

  String _channelLine(AppLocalizations l, String channel, int acquired) =>
      '${l.text(_channelLabelKeys[channel]!)} · $acquired';

  String _tooltip(
    AppLocalizations l,
    String channel,
    CoachAssessmentSummary counts,
  ) =>
      '${l.text(_channelLabelKeys[channel]!)} · '
      '${l.text('coachAssessmentAcquired')} ${counts.acquired} · '
      '${l.text('coachAssessmentNotAcquired')} ${counts.notAcquired} · '
      '${l.text('coachAssessmentUnassessed')} ${counts.unassessed}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final ghostHeight = _height(inCounts.acquired);
    final caption = ListenType.caption.copyWith(color: colors.onSurfaceVariant);
    // The bars keep the design doc's deliberate width instead of stretching
    // across whatever the dashboard grants the column.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: _column(l, colors, ghostHeight, caption),
      ),
    );
  }

  Widget _column(
    AppLocalizations l,
    ColorScheme colors,
    double ghostHeight,
    TextStyle caption,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_channelLine(l, inChannel, inCounts.acquired), style: caption),
        const SizedBox(height: ListenSpacing.gap4),
        Tooltip(
          message: _tooltip(l, inChannel, inCounts),
          child: SizedBox(
            height: barHeight,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _segment(colors, 'unassessed', inCounts.unassessed),
                _segment(colors, 'not_acquired', inCounts.notAcquired),
                _segment(colors, 'acquired', inCounts.acquired),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Container(height: 1.2, color: colors.outlineVariant),
        ),
        Tooltip(
          message: _tooltip(l, outChannel, outCounts),
          child: SizedBox(
            height: barHeight,
            width: double.infinity,
            child: Stack(
              children: [
                Column(
                  children: [
                    _segment(colors, 'acquired', outCounts.acquired),
                    _segment(colors, 'not_acquired', outCounts.notAcquired),
                    _segment(colors, 'unassessed', outCounts.unassessed),
                  ],
                ),
                if (ghostHeight > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SizedBox(
                      key: ghostKey,
                      height: ghostHeight,
                      child: CustomPaint(
                        painter: _DashedRectPainter(color: colors.secondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(_channelLine(l, outChannel, outCounts.acquired), style: caption),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l
              .text(gapLabelKey)
              .replaceFirst('{inN}', '${inCounts.acquired}')
              .replaceFirst('{outN}', '${outCounts.acquired}'),
          style: ListenType.caption.copyWith(color: colors.secondary),
        ),
      ],
    );
  }

  // Large-area unassessed segments dim to the hairline color (see the
  // compass painter's note); lit states keep the shared assessment colors.
  Widget _segment(ColorScheme colors, String state, int count) => Container(
    height: _height(count),
    color: state == 'unassessed'
        ? colors.outlineVariant
        : capabilityAssessmentColor(colors, state),
  );
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    const dash = 4.0;
    final path = Path()..addRect(Offset.zero & size);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The dashboard's portrait section: compass overview beside the echo-bar
/// channel detail, stacking on narrow layouts.
class CapabilityPortrait extends StatelessWidget {
  const CapabilityPortrait({super.key, required this.channels, this.gapCount});

  final List<CoachChannelSummary> channels;
  final int? gapCount;

  @override
  Widget build(BuildContext context) {
    final compass = CapabilityCompass(channels: channels, gapCount: gapCount);
    final bars = CapabilityEchoBars(channels: channels);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= ListenBreakpoints.capabilityPortraitSideBySide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                compass,
                const SizedBox(width: ListenSpacing.gap24),
                Expanded(child: bars),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: compass),
                const SizedBox(height: ListenSpacing.gap16),
                bars,
              ],
            ),
    );
  }
}
