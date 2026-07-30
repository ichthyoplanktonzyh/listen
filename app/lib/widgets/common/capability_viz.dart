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

const _zeroCounts = CoachAssessmentSummary(
  acquired: 0,
  notAcquired: 0,
  unassessed: 0,
);

/// One channel's counts out of a dashboard's list. A channel the backend did
/// not send reads all-zero rather than vanishing from the 2x2.
CoachAssessmentSummary _summaryFor(
  List<CoachChannelSummary> channels,
  String channel,
) {
  for (final summary in channels) {
    if (summary.channel == channel) return summary.effectiveAssessments;
  }
  return _zeroCounts;
}

/// The four quadrant channels' counts, in quadrant order.
List<CoachAssessmentSummary> _quadrantCounts(
  List<CoachChannelSummary> channels,
) => [for (final key in _quadrants.keys) _summaryFor(channels, key)];

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

/// The state a segment carries when it stands for the part of the shared
/// scale a channel has not been assessed on. It is drawn as a dashed empty
/// track, never as fill: ink is reserved for what has actually been measured.
const capabilityUnmeasured = 'unmeasured';

/// The shared scale behind both the compass and the echo bars: the largest
/// *assessed* count (acquired + not acquired) across the given channels.
///
/// Deliberately excludes `unassessed`. A user's library is mostly words
/// nobody has looked at yet, so scaling by the three-state total made every
/// graphic draw "what we do not know" at full size and squeezed the measured
/// evidence into a hairline. Scaling by the assessed total means a lit shape
/// says "this much has been measured, and this much of it is acquired".
int capabilityAssessedUnit(Iterable<CoachAssessmentSummary> counts) => counts
    .map((summary) => summary.acquired + summary.notAcquired)
    .fold(0, math.max);

/// Pure segment maths for the compass ring, exposed for tests: returns
/// (startDeg, sweepDeg, state) triples inside the channel's quadrant.
///
/// [unit] is the shared scale from [capabilityAssessedUnit]. The acquired and
/// not-acquired sweeps are proportional to it, and whatever is left of the
/// quadrant is one [capabilityUnmeasured] segment. With nothing assessed
/// anywhere — or nothing assessed on this channel — the whole quadrant reads
/// unmeasured.
List<(double, double, String)> compassSegments(
  String channel,
  int acquired,
  int notAcquired,
  int unit,
) {
  final (start, end, anchorAtEnd) = _quadrants[channel]!;
  final span = end - start;
  final assessed = acquired + notAcquired;
  if (unit <= 0 || assessed == 0) return [(start, span, capabilityUnmeasured)];
  var states = [
    ('acquired', acquired),
    ('not_acquired', notAcquired),
    (capabilityUnmeasured, math.max(unit - assessed, 0)),
  ];
  // Along the arc the acquired segment sits at the anchor.
  if (anchorAtEnd) states = states.reversed.toList(growable: false);
  final segments = <(double, double, String)>[];
  var cursor = start;
  for (final (state, count) in states) {
    if (count == 0) continue;
    final sweep = span * count / unit;
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

  CoachAssessmentSummary _counts(String channel) =>
      _summaryFor(widget.channels, channel);

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
    final unit = capabilityAssessedUnit(counts.values);
    for (final entry in counts.entries) {
      final summary = entry.value;
      for (final (start, sweep, state) in compassSegments(
        entry.key,
        summary.acquired,
        summary.notAcquired,
        unit,
      )) {
        if (state == capabilityUnmeasured) {
          // The unmeasured remainder costs no ink: a dashed hairline track
          // marks how far the shared scale reaches, and the tooltip carries
          // the exact unassessed number.
          _strokeDashed(
            canvas,
            Path()..addArc(rect, _radians(start - 90), _radians(sweep)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = mainStroke * 0.4
              ..color = colors.outlineVariant,
          );
          continue;
        }
        canvas.drawArc(
          rect,
          _radians(start - 90),
          _radians(sweep),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = mainStroke
            ..color = capabilityAssessmentColor(colors, state),
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
///
/// The bars are scaled by [capabilityAssessedUnit], so a full bar means "the
/// most-assessed channel" rather than "the size of your library". The words
/// nobody has assessed yet are the dashed trough behind the fill plus a
/// number in the caption — they are stated, not drawn at full size.
///
/// A bar is a gauge, not a field of color: [barWidth] keeps it narrow so four
/// channels' worth of eight integers costs a few hundred square points of ink
/// instead of filling the panel. Reading the shape must not cost the eye more
/// than reading the numbers would.
class CapabilityEchoBars extends StatelessWidget {
  const CapabilityEchoBars({
    super.key,
    required this.channels,
    this.barHeight = 96,
    this.barWidth = 28,
    this.onPairTap,
  });

  final List<CoachChannelSummary> channels;
  final double barHeight;

  /// The gauge's width. Deliberately narrow: widening this trades legibility
  /// for saturated area, which is the failure mode this widget exists to
  /// avoid.
  final double barWidth;

  /// Called with the modality pair a column stands for — `sound`
  /// (listening↔speaking) or `text` (reading↔writing) — so the dashboard can
  /// open both channels' evidence and mark where the gap comes from
  /// (S2 · #81). Null keeps the bars a pure read-out.
  final ValueChanged<String>? onPairTap;

  CoachAssessmentSummary _counts(String channel) =>
      _summaryFor(channels, channel);

  @override
  Widget build(BuildContext context) {
    // One shared scale across all four channels keeps the bars comparable,
    // and it counts only what has been assessed — see [capabilityAssessedUnit].
    final unit = capabilityAssessedUnit(_quadrantCounts(channels));
    if (unit == 0) {
      // Nothing has been assessed on any channel. A bar drawn here would be
      // four empty troughs pretending to be a reading; say so instead.
      final colors = Theme.of(context).colorScheme;
      return Text(
        AppLocalizations.of(context).text('capabilityEchoUnassessed'),
        key: const ValueKey('echo-bars-empty'),
        style: ListenType.body.copyWith(color: colors.onSurfaceVariant),
      );
    }
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
            barWidth: barWidth,
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
            barWidth: barWidth,
            gapLabelKey: 'capabilityEchoText',
            ghostKey: const ValueKey('echo-ghost-text'),
            onTap: onPairTap == null ? null : () => onPairTap!('text'),
          ),
        ),
      ],
    );
  }
}

class _EchoColumn extends StatefulWidget {
  const _EchoColumn({
    required this.inChannel,
    required this.outChannel,
    required this.inCounts,
    required this.outCounts,
    required this.unit,
    required this.barHeight,
    required this.barWidth,
    required this.gapLabelKey,
    required this.ghostKey,
    this.onTap,
  });

  final String inChannel, outChannel, gapLabelKey;
  final CoachAssessmentSummary inCounts, outCounts;
  final int unit;
  final double barHeight, barWidth;
  final Key ghostKey;
  final VoidCallback? onTap;

  @override
  State<_EchoColumn> createState() => _EchoColumnState();
}

class _EchoColumnState extends State<_EchoColumn> {
  /// The mirror's own furniture: the hairline baseline and the air around it.
  /// Element geometry, not spacing between siblings.
  static const _baselineThickness = 1.2;
  static const _baselineInset = 2.0;

  /// The column's own affordance: hovering lifts the whole pair so the door
  /// announces itself instead of needing a caption to explain it.
  bool _hovered = false;

  double _height(int count) =>
      widget.unit == 0 ? 0 : widget.barHeight * count / widget.unit;

  /// Reception bar + baseline + production bar. Known up front so the labels
  /// beside the gauge can align to the same mirror without an intrinsic pass.
  double get _mirrorHeight =>
      widget.barHeight * 2 + _baselineInset * 2 + _baselineThickness;

  String _channelLine(
    AppLocalizations l,
    String channel,
    CoachAssessmentSummary counts,
  ) => '${l.text(_channelLabelKeys[channel]!)} · ${counts.acquired}';

  /// The unassessed stock left the graphic; it comes back as a number so no
  /// information is lost with the ink.
  String _unassessedLine(AppLocalizations l, CoachAssessmentSummary counts) =>
      '${l.text('coachAssessmentUnassessed')} ${counts.unassessed}';

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
    final ghostHeight = _height(widget.inCounts.acquired);
    final caption = ListenType.caption.copyWith(color: colors.onSurfaceVariant);
    final column = _column(l, colors, ghostHeight, caption);
    final onTap = widget.onTap;
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
                // InkWell already carries SystemMouseCursors.click; this adds
                // the visible lift at the shared hover tempo.
                onHover: (hovering) {
                  if (hovering != _hovered) {
                    setState(() => _hovered = hovering);
                  }
                },
                borderRadius: ListenRadii.surfaceBorder,
                // Keyboard and screen readers get the same door as the
                // pointer: the pair reads as one button.
                child: Semantics(
                  button: true,
                  label:
                      '${l.text(_channelLabelKeys[widget.inChannel]!)} · '
                      '${l.text(_channelLabelKeys[widget.outChannel]!)}',
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : ListenMotion.hover,
                    curve: ListenMotion.move,
                    padding: const EdgeInsets.all(ListenSpacing.gap4),
                    decoration: BoxDecoration(
                      borderRadius: ListenRadii.surfaceBorder,
                      color: colors.primary.withValues(
                        alpha: _hovered ? 0.1 : 0,
                      ),
                    ),
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
        // The gauge keeps the mirror; the labels stand beside it. Moving the
        // captions out of the stack is what lets the bar be narrow without
        // squeezing the text.
        SizedBox(
          height: _mirrorHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: widget.barWidth,
                child: _mirror(l, colors, ghostHeight),
              ),
              const SizedBox(width: ListenSpacing.gap12),
              Expanded(
                child: Column(
                  // Each channel's reading sits against its own half of the
                  // mirror: reception up top, production down below.
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _readout(l, widget.inChannel, widget.inCounts, caption),
                    _readout(l, widget.outChannel, widget.outCounts, caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(
          l
              .text(widget.gapLabelKey)
              .replaceFirst('{inN}', '${widget.inCounts.acquired}')
              .replaceFirst('{outN}', '${widget.outCounts.acquired}'),
          style: ListenType.caption.copyWith(color: colors.secondary),
        ),
      ],
    );
  }

  Widget _mirror(AppLocalizations l, ColorScheme colors, double ghostHeight) =>
      Column(
        children: [
          Tooltip(
            message: _tooltip(l, widget.inChannel, widget.inCounts),
            child: _trough(
              colors,
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _segment(colors, 'not_acquired', widget.inCounts.notAcquired),
                  _segment(colors, 'acquired', widget.inCounts.acquired),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: _baselineInset),
            child: Container(
              height: _baselineThickness,
              color: colors.outlineVariant,
            ),
          ),
          Tooltip(
            message: _tooltip(l, widget.outChannel, widget.outCounts),
            child: _trough(
              colors,
              Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        _segment(colors, 'acquired', widget.outCounts.acquired),
                        _segment(
                          colors,
                          'not_acquired',
                          widget.outCounts.notAcquired,
                        ),
                      ],
                    ),
                  ),
                  if (ghostHeight > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SizedBox(
                        key: widget.ghostKey,
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
        ],
      );

  Widget _readout(
    AppLocalizations l,
    String channel,
    CoachAssessmentSummary counts,
    TextStyle caption,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_channelLine(l, channel, counts), style: caption),
      Text(_unassessedLine(l, counts), style: caption),
    ],
  );

  /// The bar's full extent on the shared scale, drawn as a dashed empty slot.
  /// What has not been assessed is a boundary, not a filled area — the ink
  /// inside it is exactly what has been measured.
  Widget _trough(ColorScheme colors, Widget child) => SizedBox(
    height: widget.barHeight,
    width: double.infinity,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _DashedRectPainter(color: colors.outlineVariant)),
        child,
      ],
    ),
  );

  // Only the two assessed states are drawn; they keep the shared assessment
  // colors so a bar reads the same as a compass quadrant.
  Widget _segment(ColorScheme colors, String state, int count) => Container(
    height: _height(count),
    color: capabilityAssessmentColor(colors, state),
  );
}

/// Strokes [path] as a dashed line. The one dashing routine behind every
/// "outlined, not filled" shape in this file — ghosts, troughs and the
/// compass's unmeasured arcs all draw the same absence the same way.
void _strokeDashed(Canvas canvas, Path path, Paint paint, {double dash = 4}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
      distance += dash * 2;
    }
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _strokeDashed(
      canvas,
      Path()..addRect(Offset.zero & size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The widest three-state total across the given channels — the lexical
/// library the portrait is drawn against.
///
/// Every channel reports on the same words, so this is a max rather than a
/// sum: adding the four channels' totals would invent a library four times
/// the real one. Presentation reads existing counts; it never derives a new
/// metric.
int capabilityLibrarySize(Iterable<CoachAssessmentSummary> counts) => counts
    .map(
      (summary) => summary.acquired + summary.notAcquired + summary.unassessed,
    )
    .fold(0, math.max);

/// The dashboard's portrait section: compass overview beside the echo-bar
/// channel detail, stacking on narrow layouts.
///
/// Under both graphics sits one caption-sized readout of the shared scale
/// ("Assessed 8 of 208"). The graphics answer *shape* — within what has been
/// measured, this is how the four channels stand — and the line answers *how
/// much has been measured*. Neither has to distort itself to carry the
/// other's job: a nearly-full ring cannot read as "you are nearly done" while
/// the line says only 8 of 208 words have been looked at.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >=
                  ListenBreakpoints.capabilityPortraitSideBySide
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
        ),
        _scaleLine(context),
      ],
    );
  }

  /// How much of the library the shapes above were drawn from. Without it a
  /// well-filled ring built on eight assessed words would read as progress.
  Widget _scaleLine(BuildContext context) {
    final counts = _quadrantCounts(channels);
    final library = capabilityLibrarySize(counts);
    if (library == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: ListenSpacing.gap12),
      child: Text(
        AppLocalizations.of(context)
            .text('capabilityAssessedScale')
            .replaceFirst('{n}', '${capabilityAssessedUnit(counts)}')
            .replaceFirst('{total}', '$library'),
        style: ListenType.caption.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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
