import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';

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
