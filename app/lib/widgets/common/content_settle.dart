import 'package:flutter/material.dart';

import '../../theme/motion.dart';

/// The "content settles in" signature action (#46, motion spec demo 4):
/// entering content fades in while rising 8px into place —
/// [ListenMotion.base] · [ListenMotion.enter], decelerate, no overshoot.
///
/// Wrap a panel and give [settleKey] the identity of what's on stage (e.g.
/// the selected channel): when the key changes, the new content settles in
/// again. Under reduce motion the content simply appears.
class ContentSettle extends StatefulWidget {
  const ContentSettle({super.key, this.settleKey, required this.child});

  /// Identity of the content on stage; a change re-runs the settle. Null
  /// settles only on first build.
  final Object? settleKey;

  final Widget child;

  /// How far entering content rises (spec: fade + 8px up).
  static const rise = 8.0;

  @override
  State<ContentSettle> createState() => _ContentSettleState();
}

class _ContentSettleState extends State<ContentSettle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _settle;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: ListenMotion.base);
    _settle = _controller.drive(CurveTween(curve: ListenMotion.enter));
    _controller.forward();
  }

  @override
  void didUpdateWidget(ContentSettle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settleKey != oldWidget.settleKey) {
      // Reduce motion: content appears, already settled.
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _settle,
    child: AnimatedBuilder(
      animation: _settle,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, ContentSettle.rise * (1 - _settle.value)),
        child: child,
      ),
      child: widget.child,
    ),
  );
}
