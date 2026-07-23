import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';

/// The unified waiting language (#46): the mutual-wave mark breathing at the
/// ambient tempo — never a decorative spinner (charter principle 5, motion
/// spec "wordmark 呼吸").
///
/// Waiting is presence, not motion: the mark holds still and breathes
/// (opacity 0.72 → 1 over one [ListenMotion.ambient] cycle, ease-in-out),
/// which reads as "the product is alive and working" without grabbing
/// attention the way a spinner does. Under reduce motion the breath stops and
/// the mark simply shows (motion spec: ambient breathing halts, controls stay
/// visible).
///
/// Two forms:
/// - [ListenLoading] — panel-level waiting: centered mark plus an optional
///   one-line label. Replaces `Center(child: CircularProgressIndicator())`.
/// - [ListenLoading.inline] — control-level waiting: the bare mark at icon
///   size. Replaces the `strokeWidth: 2` mini spinners inside buttons, list
///   rows and status cells.
///
/// `loading_discipline_test.dart` pins the "no bare spinners" rule.
class ListenLoading extends StatefulWidget {
  const ListenLoading({super.key, this.label, this.size = 30})
    : _inline = false;

  /// Icon-sized waiting for inline contexts (buttons, status cells).
  const ListenLoading.inline({super.key, this.size = 18})
    : label = null,
      _inline = true;

  /// Optional one-line explanation under the mark. Null shows the mark alone;
  /// the semantics label falls back to the localized "loading".
  final String? label;

  /// Height of the breathing mark.
  final double size;

  final bool _inline;

  @override
  State<ListenLoading> createState() => _ListenLoadingState();
}

class _ListenLoadingState extends State<ListenLoading>
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
    // Reduce motion: the breath stops, the mark stays (motion spec).
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mark = FadeTransition(
      opacity: _breath,
      child: ListenWordmark(size: widget.size, withText: false),
    );
    final child = widget._inline || widget.label == null
        ? mark
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                widget.label!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
    return Semantics(
      label: widget.label ?? l.text('loading'),
      liveRegion: !widget._inline,
      child: ExcludeSemantics(child: child),
    );
  }
}
