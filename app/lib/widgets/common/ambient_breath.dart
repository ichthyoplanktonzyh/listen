import 'package:flutter/material.dart';

import '../../theme/motion.dart';

/// The ambient breath (#46, motion spec): opacity 0.72 → 1 → 0.72 across one
/// [ListenMotion.ambient] cycle, ease-in-out — "alive but quiet". The one
/// breathing gesture the whole app shares: the loading mark and the rhythm
/// ribbon's current beat both draw from here so the product breathes at a
/// single tempo.
///
/// Under reduce motion the breath stops and the child holds still at full
/// presence (motion spec: ambient breathing halts).
class AmbientBreath extends StatefulWidget {
  const AmbientBreath({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBreath> createState() => _AmbientBreathState();
}

class _AmbientBreathState extends State<AmbientBreath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    // One full breath spans the ambient duration: half out, half back.
    _controller = AnimationController(
      vsync: this,
      duration: ListenMotion.ambient * 0.5,
    );
    _breath = _controller.drive(
      Tween(begin: 0.72, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _breath, child: widget.child);
}
