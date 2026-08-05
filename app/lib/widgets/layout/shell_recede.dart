import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/motion.dart';

/// The "shell recedes" signature action (#46, motion spec demo 3): while
/// media plays and the pointer rests, the chrome (the transport, and the
/// immersive controls) fades away so the room goes dark around the content; any pointer activity — or
/// keyboard focus landing inside the chrome — brings it back.
///
/// [ShellRecede] is the detector: it wraps the whole shell, watches pointer
/// activity through a translucent [Listener] (so watching costs no hit-test
/// changes), and rebuilds its [builder] with the current visibility.
/// [ShellFade] is the presenter: wrap each piece of chrome with it. The pair
/// mirrors the spec's `:hover, :focus-within` reveal — focus holds are
/// reported back through an inherited scope, so a keyboard user's chrome
/// never vanishes under their focus.
class ShellRecede extends StatefulWidget {
  const ShellRecede({
    super.key,
    required this.active,
    required this.builder,
    this.idleDelay = const Duration(seconds: 3),
  });

  /// True while receding is allowed at all — media playing on the workbench.
  /// False forces the shell visible (paused, home screen, no media).
  final bool active;

  /// Rebuilt whenever shell visibility flips.
  final Widget Function(BuildContext context, bool shellVisible) builder;

  /// How long the pointer must rest before the shell recedes. Not a motion
  /// token: this is a patience threshold, not a tempo.
  final Duration idleDelay;

  @override
  State<ShellRecede> createState() => _ShellRecedeState();
}

class _ShellRecedeState extends State<ShellRecede> {
  Timer? _idle;
  bool _pointerResting = false;
  int _focusHolds = 0;

  bool get _shellVisible =>
      !widget.active || !_pointerResting || _focusHolds > 0;

  @override
  void initState() {
    super.initState();
    // Active from the first frame (e.g. playback resumed on open): the idle
    // clock must start without waiting for a pointer to move.
    if (widget.active) _restartIdleClock();
  }

  @override
  void didUpdateWidget(ShellRecede oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    _idle?.cancel();
    if (widget.active) {
      _restartIdleClock();
    } else if (_pointerResting) {
      _pointerResting = false;
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _wake() {
    if (_pointerResting) setState(() => _pointerResting = false);
    if (widget.active) _restartIdleClock();
  }

  void _restartIdleClock() {
    _idle?.cancel();
    _idle = Timer(widget.idleDelay, () {
      if (mounted) setState(() => _pointerResting = true);
    });
  }

  void _holdFocus(bool held) {
    setState(() => _focusHolds += held ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerHover: (_) => _wake(),
    onPointerMove: (_) => _wake(),
    onPointerDown: (_) => _wake(),
    onPointerSignal: (_) => _wake(),
    child: _ShellRecedeScope(
      state: this,
      child: Builder(
        builder: (context) => widget.builder(context, _shellVisible),
      ),
    ),
  );
}

class _ShellRecedeScope extends InheritedWidget {
  const _ShellRecedeScope({required this.state, required super.child});

  final _ShellRecedeState state;

  @override
  bool updateShouldNotify(_ShellRecedeScope oldWidget) =>
      state != oldWidget.state;
}

/// Fades one piece of chrome per the spec: leave accelerating
/// ([ListenMotion.exit]), return settling ([ListenMotion.enter]), both at the
/// base tempo; instant under reduce motion. While hidden the chrome ignores
/// pointers, so the first click after a rest wakes the shell instead of
/// blindly pressing an invisible button. Keyboard focus inside the child
/// holds the shell visible via the enclosing [ShellRecede].
class ShellFade extends StatelessWidget {
  const ShellFade({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ShellRecedeScope>();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (held) => scope?.state._holdFocus(held),
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduceMotion ? Duration.zero : ListenMotion.base,
          curve: visible ? ListenMotion.enter : ListenMotion.exit,
          child: child,
        ),
      ),
    );
  }
}
