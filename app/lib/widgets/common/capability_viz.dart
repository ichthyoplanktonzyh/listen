import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
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

/// The compass center hotspot (S2 · #81): the gap-(c) figure, which navigates
/// to the vocabulary gap pane instead of staying on the page.
const compassGapTarget = 'gap';

/// Pure hit test for the compass hotspots, exposed for tests: which target a
/// tap at [position] inside a [size]-square compass lands on, or null for the
/// inert middle ring / outside the circle.
///
/// The quadrants are hit as full 90° wedges (the painter's 8° seams are a
/// visual detail, not a dead zone) from half the radius outward, so the
/// center figure keeps a generous disc of its own. When the backend surfaced
/// no gap count there is no center target and the disc is inert.
String? compassHitTarget(
  double size,
  Offset position, {
  required bool hasGapCenter,
}) {
  final radius = size / 2;
  final delta = position - Offset(radius, radius);
  final distance = delta.distance;
  if (distance > radius) return null;
  if (distance <= radius * 0.5) return hasGapCenter ? compassGapTarget : null;
  // Degrees clockwise from 12 o'clock, matching `_quadrants`.
  final degrees = (math.atan2(delta.dx, -delta.dy) * 180 / math.pi + 360) % 360;
  if (degrees >= 270) return 'listening';
  if (degrees < 90) return 'reading';
  if (degrees < 180) return 'writing';
  return 'speaking';
}

/// Three-state four-quadrant ring for a single entry: one solid arc per
/// channel, colored by its effective assessment. Proportions are dropped at
/// this scale on purpose — an entry has states, not shares.
class CapabilityRing extends StatelessWidget {
  const CapabilityRing({
    super.key,
    required this.assessments,
    this.size = 16,
    this.withTooltip = false,
    this.focusChannel,
  });

  /// Effective assessment per channel key; missing channels read unassessed.
  final Map<String, String> assessments;
  final double size;
  final bool withTooltip;

  /// When set, that channel's quadrant is drawn as the primary lens and the
  /// other three recede — a presentation-only cue so the vocabulary lens's
  /// channel picker always has a visible effect. The underlying assessments
  /// (and the query behind them) are unchanged.
  final String? focusChannel;

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
          focusChannel: focusChannel,
        ),
      ),
    );
    if (!withTooltip) return ring;
    return Tooltip(message: label, child: ring);
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.assessments,
    required this.colors,
    this.focusChannel,
  });

  final Map<String, String> assessments;
  final ColorScheme colors;
  final String? focusChannel;

  @override
  void paint(Canvas canvas, Size size) {
    final mainStroke = size.width * 0.16;
    final rect =
        Offset(mainStroke / 2, mainStroke / 2) &
        Size.square(size.width - mainStroke);
    for (final entry in _quadrants.entries) {
      final assessment = assessments[entry.key] ?? 'unassessed';
      final dim = assessment != 'acquired' && assessment != 'not_acquired';
      // The lens: when a channel is focused the other quadrants recede so the
      // picker's effect is always visible. Purely a presentation cue.
      final unfocused = focusChannel != null && entry.key != focusChannel;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dim ? mainStroke * 0.55 : mainStroke
        ..color = unfocused
            ? capabilityAssessmentColor(
                colors,
                assessment,
              ).withValues(alpha: 0.3)
            : capabilityAssessmentColor(colors, assessment);
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
      oldDelegate.focusChannel != focusChannel ||
      !mapEquals(oldDelegate.assessments, assessments);
}

/// Aggregate compass ring: per quadrant the arc splits by assessment share
/// (thick lit teal, thick amber, thin dim for the unassessed stock), and the
/// center carries the gap-(c) count when the backend surfaced one.
///
/// With [onChannelTap] / [onGapTap] the ring becomes the dashboard's
/// navigation (S2 · #81): a quadrant scrolls to that channel's evidence and
/// the center figure leaves for the vocabulary gap pane. Hovering lights the
/// target it would hit, so "the thing you look at" only becomes "the thing
/// you press" when it says so.
class CapabilityCompass extends StatefulWidget {
  const CapabilityCompass({
    super.key,
    required this.channels,
    this.gapCount,
    this.size = 200,
    this.onChannelTap,
    this.onGapTap,
  });

  final List<CoachChannelSummary> channels;
  final int? gapCount;
  final double size;

  /// Called with a channel key when its quadrant is tapped.
  final ValueChanged<String>? onChannelTap;

  /// Called when the gap-(c) center figure is tapped. Only reachable while
  /// [gapCount] is non-null — there is no honest destination without it.
  final VoidCallback? onGapTap;

  @override
  State<CapabilityCompass> createState() => _CapabilityCompassState();
}

class _CapabilityCompassState extends State<CapabilityCompass> {
  String? _hovered;

  CoachAssessmentSummary _counts(String channel) {
    for (final summary in widget.channels) {
      if (summary.channel == channel) return summary.effectiveAssessments;
    }
    return const CoachAssessmentSummary(
      acquired: 0,
      notAcquired: 0,
      unassessed: 0,
    );
  }

  bool get _interactive =>
      widget.onChannelTap != null || widget.onGapTap != null;

  bool get _hasGapCenter => widget.gapCount != null && widget.onGapTap != null;

  String? _target(Offset local) =>
      compassHitTarget(widget.size, local, hasGapCenter: _hasGapCenter);

  void _handleTap(TapUpDetails details) {
    final target = _target(details.localPosition);
    if (target == null) return;
    if (target == compassGapTarget) {
      widget.onGapTap?.call();
      return;
    }
    widget.onChannelTap?.call(target);
  }

  void _handleHover(PointerHoverEvent event) {
    final target = _target(event.localPosition);
    if (target == _hovered) return;
    setState(() => _hovered = target);
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
    final gapCount = widget.gapCount;
    Widget compass = Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size.square(widget.size),
          painter: _CompassPainter(
            counts: {
              for (final channel in _quadrants.keys) channel: _counts(channel),
            },
            colors: theme.colorScheme,
            highlight: _hovered,
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
    );
    if (_interactive) {
      compass = MouseRegion(
        cursor: _hovered == null ? MouseCursor.defer : SystemMouseCursors.click,
        onHover: _handleHover,
        onExit: (_) {
          if (_hovered != null) setState(() => _hovered = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTap,
          child: compass,
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(dimension: widget.size, child: compass),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.counts,
    required this.colors,
    this.highlight,
  });

  final Map<String, CoachAssessmentSummary> counts;
  final ColorScheme colors;

  /// The hovered hotspot (channel key or [compassGapTarget]): a faint halo,
  /// no motion — an affordance, not an animation.
  final String? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final mainStroke = size.width * 0.062;
    final rect =
        Offset(mainStroke / 2, mainStroke / 2) &
        Size.square(size.width - mainStroke);
    _paintHighlight(canvas, size, rect, mainStroke);
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

  void _paintHighlight(Canvas canvas, Size size, Rect rect, double stroke) {
    final target = highlight;
    if (target == null) return;
    final glow = Paint()..color = colors.primary.withValues(alpha: 0.12);
    if (target == compassGapTarget) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width * 0.25,
        glow,
      );
      return;
    }
    final quadrant = _quadrants[target];
    if (quadrant == null) return;
    final (start, end, _) = quadrant;
    canvas.drawArc(
      rect,
      _radians(start - 90),
      _radians(end - start),
      false,
      glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.4,
    );
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.highlight != highlight ||
      !mapEquals(oldDelegate.counts, counts);
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
    this.onPairTap,
  });

  final List<CoachChannelSummary> channels;
  final double barHeight;

  /// Called with the modality pair a column stands for — `sound`
  /// (listening↔speaking) or `text` (reading↔writing) — so the dashboard can
  /// open both channels' evidence and mark where the gap comes from
  /// (S2 · #81). Null keeps the bars a pure read-out.
  final ValueChanged<String>? onPairTap;

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
            onTap: onPairTap == null ? null : () => onPairTap!('sound'),
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
            onTap: onPairTap == null ? null : () => onPairTap!('text'),
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
    this.onTap,
  });

  final String inChannel, outChannel, gapLabelKey;
  final CoachAssessmentSummary inCounts, outCounts;
  final int unit;
  final double barHeight;
  final Key ghostKey;
  final VoidCallback? onTap;

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
    final column = _column(l, colors, ghostHeight, caption);
    // The bars keep the design doc's deliberate width instead of stretching
    // across whatever the dashboard grants the column.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: onTap == null
            ? column
            : InkWell(
                onTap: onTap,
                borderRadius: ListenRadii.surfaceBorder,
                // Keyboard and screen readers get the same door as the
                // pointer: the pair reads as one button.
                child: Semantics(
                  button: true,
                  label:
                      '${l.text(_channelLabelKeys[inChannel]!)} · '
                      '${l.text(_channelLabelKeys[outChannel]!)}',
                  child: Padding(
                    padding: const EdgeInsets.all(ListenSpacing.gap4),
                    child: column,
                  ),
                ),
              ),
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
  const CapabilityPortrait({
    super.key,
    required this.channels,
    this.gapCount,
    this.onChannelTap,
    this.onGapTap,
    this.onPairTap,
  });

  final List<CoachChannelSummary> channels;
  final int? gapCount;

  /// The three hotspots (S2 · #81). All optional: without them the portrait
  /// is the same read-only picture it was at #47.
  final ValueChanged<String>? onChannelTap;
  final VoidCallback? onGapTap;
  final ValueChanged<String>? onPairTap;

  @override
  Widget build(BuildContext context) {
    final compass = CapabilityCompass(
      channels: channels,
      gapCount: gapCount,
      onChannelTap: onChannelTap,
      onGapTap: onGapTap,
    );
    final bars = CapabilityEchoBars(channels: channels, onPairTap: onPairTap);
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

/// How much of each light the 回声水面 is showing right now (#84 · S7).
///
/// Presentation only, and deliberately **not** an activity enum: the
/// controller's `RealtimeConversationActivity` stays the single source of
/// truth and is mapped onto these levels at the stage
/// (`conversationEchoLevelsOf`). This type only knows about light, so the
/// painter can be exercised without a live conversation.
@immutable
class EchoSurfaceLevels {
  const EchoSurfaceLevels({
    required this.moon,
    required this.learner,
    required this.ripple,
  });

  /// The other voice: light falling from above onto the water (月白).
  final double moon;

  /// Your echo swelling up from below the waterline (信号青). The brightest
  /// moment of the flow — the charter's "your language is the light".
  final double learner;

  /// The thinking ripple spreading out from the waterline. The instrument is
  /// working; it does not pretend to be busy with a spinner.
  final double ripple;

  /// Nothing on the water yet — only the line itself.
  static const still = EchoSurfaceLevels(moon: 0, learner: 0, ripple: 0);

  @override
  bool operator ==(Object other) =>
      other is EchoSurfaceLevels &&
      other.moon == moon &&
      other.learner == learner &&
      other.ripple == ripple;

  @override
  int get hashCode => Object.hash(moon, learner, ripple);

  @override
  String toString() =>
      'EchoSurfaceLevels(moon: $moon, learner: $learner, ripple: $ripple)';
}

/// 回声水面 — the conversation's one big shape (#84 · S7).
///
/// Same lineage as [CapabilityEchoBars]: one baseline, light that came in
/// above it, your echo below it. Here the baseline is a water surface across
/// the middle of the stage, so the top/bottom asymmetry that *is* gap-(c) in
/// the portrait becomes the live conversation's turn-taking.
///
/// Motion follows the charter: envelopes drift at [ListenMotion.ambient],
/// never a bounce, and every level animates. The interruption is the one fast
/// gesture — your teal swell rises within [ListenMotion.tap] (≤90ms) while the
/// moonlight is drawn back down into the water over [ListenMotion.slow]. Under
/// reduce motion the drift stops, every level snaps, and the surface holds a
/// single still frame.
class ConversationEchoSurface extends StatefulWidget {
  const ConversationEchoSurface({
    super.key,
    required this.levels,
    this.height = 260,
  });

  final EchoSurfaceLevels levels;
  final double height;

  @override
  State<ConversationEchoSurface> createState() =>
      _ConversationEchoSurfaceState();
}

class _ConversationEchoSurfaceState extends State<ConversationEchoSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: ListenMotion.ambient,
  );
  late EchoSurfaceLevels _previous = widget.levels;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
      _drift.value = 0;
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void didUpdateWidget(ConversationEchoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levels != widget.levels) _previous = oldWidget.levels;
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final levels = widget.levels;
    final rising = levels.learner > _previous.learner;
    // The interruption budget: your voice takes the surface at tap speed, the
    // moonlight is pulled under on the slow exit. Your side is never the thing
    // that waits.
    final learnerDuration = rising ? ListenMotion.tap : ListenMotion.slow;
    final moonDuration = levels.moon < _previous.moon
        ? ListenMotion.slow
        : ListenMotion.base;

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: _channel(
        levels.moon,
        reduceMotion ? Duration.zero : moonDuration,
        levels.moon < _previous.moon ? ListenMotion.exit : ListenMotion.enter,
        (moon) => _channel(
          levels.learner,
          reduceMotion ? Duration.zero : learnerDuration,
          rising ? ListenMotion.enter : ListenMotion.exit,
          (learner) => _channel(
            levels.ripple,
            reduceMotion ? Duration.zero : ListenMotion.base,
            ListenMotion.move,
            (ripple) => AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => CustomPaint(
                painter: EchoSurfacePainter(
                  levels: EchoSurfaceLevels(
                    moon: moon,
                    learner: learner,
                    ripple: ripple,
                  ),
                  phase: _drift.value,
                  signal: ListenColors.overlaySignal,
                  moonlight: ListenColors.moonWhite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _channel(
    double target,
    Duration duration,
    Curve curve,
    Widget Function(double value) builder,
  ) => TweenAnimationBuilder<double>(
    tween: Tween<double>(end: target),
    duration: duration,
    curve: curve,
    builder: (context, value, _) => builder(value),
  );
}

/// Paints the water surface: the line, the moonlight falling toward it from
/// above, your echo swelling toward it from below, and the thinking ripple.
///
/// Public so tests can read the animated [levels] straight off the frame that
/// was actually painted — the interruption budget is a visual promise, so it
/// is measured on the picture rather than on a controller value.
class EchoSurfacePainter extends CustomPainter {
  const EchoSurfacePainter({
    required this.levels,
    required this.phase,
    required this.signal,
    required this.moonlight,
  });

  final EchoSurfaceLevels levels;

  /// Ambient drift, 0→1 over one [ListenMotion.ambient] cycle. Frozen at 0
  /// under reduce motion, which makes the whole surface a still frame.
  final double phase;

  final Color signal;
  final Color moonlight;

  /// Rest distance from the waterline for each envelope, as a fraction of the
  /// half-height. Presence pulls the envelopes toward the line: the other
  /// voice falls onto the water, your echo rises to meet it.
  static const _rest = <double>[0.30, 0.56, 0.80];
  static const _alphas = <double>[0.9, 0.55, 0.3];
  static const _strokes = <double>[2.6, 1.9, 1.4];

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    // The waterline is always there — it is the room's horizon, brightest in
    // the middle so the eye has an anchor on a shape that spans the screen.
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = moonlight.withValues(alpha: 0.14)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(size.width * 0.3, mid),
      Offset(size.width * 0.7, mid),
      Paint()
        ..color = moonlight.withValues(alpha: 0.24)
        ..strokeWidth = 1,
    );

    _paintRipple(canvas, size, mid);
    for (var i = 0; i < _rest.length; i++) {
      _paintEnvelope(
        canvas,
        size,
        mid,
        index: i,
        level: levels.moon,
        direction: -1,
        color: moonlight,
      );
      _paintEnvelope(
        canvas,
        size,
        mid,
        index: i,
        level: levels.learner,
        direction: 1,
        color: signal,
      );
    }
  }

  void _paintEnvelope(
    Canvas canvas,
    Size size,
    double mid, {
    required int index,
    required double level,
    required double direction,
    required Color color,
  }) {
    if (level <= 0.001) return;
    final half = size.height / 2;
    // Presence = proximity. At rest the envelopes sit far from the line; as
    // the voice takes over they crowd the surface.
    final base = mid + direction * half * _rest[index] * (1 - 0.45 * level);
    // Only low-frequency envelopes, never a high-frequency waveform: the
    // design's own self-falsification called out visual noise as the risk.
    final amplitude = half * (0.03 + 0.11 * level) / (1 + index * 0.45);
    final waves = 1.5 + index * 0.5;
    final drift = phase * 2 * math.pi * (direction > 0 ? 1 : -1);
    final path = Path();
    const samples = 64;
    for (var s = 0; s <= samples; s++) {
      final x = size.width * s / samples;
      final y =
          base +
          math.sin((s / samples) * waves * 2 * math.pi + drift + index) *
              amplitude;
      if (s == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokes[index]
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: (_alphas[index] * level).clamp(0, 1)),
    );
  }

  void _paintRipple(Canvas canvas, Size size, double mid) {
    if (levels.ripple <= 0.001) return;
    final center = Offset(size.width / 2, mid);
    final maxRadius = size.width * 0.34;
    for (final offset in const [0.0, 0.5]) {
      final p = (phase + offset) % 1;
      final radius = maxRadius * (0.2 + 0.8 * p);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 2,
          height: radius * 0.64,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = moonlight.withValues(
            alpha: (0.34 * levels.ripple * (1 - p)).clamp(0, 1),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(EchoSurfacePainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.phase != phase ||
      oldDelegate.signal != signal ||
      oldDelegate.moonlight != moonlight;
}

/// The 回声水面 frozen into a single static bar — the debrief's closing shape
/// (#86 · S9).
///
/// Lineage, deliberately: [CapabilityEchoBars] draws one column per modality
/// pair with the reception channel above a baseline and the production channel
/// below it, and repeats the reception height below as a dashed ghost so the
/// unlit part of the ghost *is* gap-(c). [ConversationEchoSurface] turns that
/// same baseline into the live stage's waterline. When the conversation ends
/// the water stops moving and收窄 back into the portrait's shape — one
/// column, the 说 channel: the light that came in above the line, your echo
/// below it.
///
/// Why this is a sibling of [CapabilityEchoBars] rather than a literal reuse:
/// that widget reads [CoachChannelSummary] — *portrait* counts of acquired /
/// not-acquired / unassessed words across the whole language. This bar counts
/// *this conversation's* turns. Feeding turn counts into an assessment widget
/// would dress conversation facts as portrait judgments, which is exactly the
/// 呈现≠语义 line the C wave is not allowed to cross. So the form is shared
/// and the semantics are not.
///
/// Static by construction: no controller, no ambient drift, nothing to reduce
/// under reduce-motion. The stage's motion has ended; this is its residue.
class ConversationEchoTally extends StatelessWidget {
  const ConversationEchoTally({
    super.key,
    required this.moonTurns,
    required this.learnerTurns,
    required this.learnerOutputTurns,
    this.barHeight = 64,
  });

  /// Turns the other voice took — 月白, the light that came in.
  final int moonTurns;

  /// Turns you took, whatever became of them. Drawn as the dashed ghost.
  final int learnerTurns;

  /// Of those, the ones that came back as learner output (a completed local
  /// transcript). Drawn lit, in signal teal. The unlit remainder of the ghost
  /// is what this conversation did not return — drawn, not computed away.
  final int learnerOutputTurns;

  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final unit = math.max(moonTurns, learnerTurns);
    double height(int count) => unit == 0 ? 0 : barHeight * count / unit;
    return Semantics(
      label:
          'The other voice took $moonTurns turns; you took $learnerTurns, '
          'and $learnerOutputTurns of yours came back as learner output.',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: barHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    key: const ValueKey('conversation-tally-moon'),
                    height: height(moonTurns),
                    color: ListenColors.moonWhite.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Container(
                height: 1.2,
                color: ListenColors.moonWhite.withValues(alpha: 0.24),
              ),
            ),
            SizedBox(
              height: barHeight,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Container(
                        key: const ValueKey('conversation-tally-learner'),
                        height: height(learnerOutputTurns),
                        color: ListenColors.overlaySignal,
                      ),
                    ],
                  ),
                  if (height(learnerTurns) > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SizedBox(
                        key: const ValueKey('conversation-tally-ghost'),
                        height: height(learnerTurns),
                        child: CustomPaint(
                          painter: _DashedRectPainter(
                            color: ListenColors.overlaySignal.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
