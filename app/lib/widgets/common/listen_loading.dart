import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';
import 'ambient_breath.dart';

/// The unified waiting language (#46): the mutual-wave mark breathing at the
/// ambient tempo — never a decorative spinner (charter principle 5, motion
/// spec "wordmark 呼吸").
///
/// Waiting is presence, not motion: the mark holds still and breathes
/// ([AmbientBreath]), which reads as "the product is alive and working"
/// without grabbing attention the way a spinner does. Under reduce motion
/// the breath stops and the mark simply shows.
///
/// Two forms:
/// - [ListenLoading] — panel-level waiting: centered mark plus an optional
///   one-line label. Replaces `Center(child: CircularProgressIndicator())`.
/// - [ListenLoading.inline] — control-level waiting: the bare mark at icon
///   size. Replaces the `strokeWidth: 2` mini spinners inside buttons, list
///   rows and status cells.
///
/// `loading_discipline_test.dart` pins the "no bare spinners" rule.
class ListenLoading extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mark = AmbientBreath(
      child: ListenWordmark(size: size, withText: false),
    );
    final child = _inline || label == null
        ? mark
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
    return Semantics(
      label: label ?? l.text('loading'),
      liveRegion: !_inline,
      child: ExcludeSemantics(child: child),
    );
  }
}
