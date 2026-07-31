import 'package:flutter/material.dart';

import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

/// The unified empty-state language (#46): a quiet icon, one sentence, and —
/// when the panel has one — a recovery action.
///
/// Empty is a state, not an apology: the icon names what would live here, the
/// sentence says why it's absent, the action (optional) offers the next step.
/// Everything stays muted (charter principle 5 — the empty panel must not
/// shout), so the icon and text both sit in `onSurfaceVariant` territory and
/// nothing animates.
///
/// Replaces the bare `Center(child: Text(...))` scattered across panels so
/// every "nothing here yet" reads as one voice.
class ListenEmptyState extends StatelessWidget {
  const ListenEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  /// What would live here — always an outlined/muted glyph, never a filled
  /// alarm icon.
  final IconData icon;

  /// One sentence: why the panel is empty (and implicitly, what would fill
  /// it).
  final String message;

  /// Optional recovery action (e.g. an open/search button). Widgets, not
  /// callbacks, so call sites keep their existing button idioms.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ListenSpacing.gap24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              // `illustration`, the one permitted big icon: this glyph is the
              // only thing naming what would live here, so it carries meaning
              // on its own rather than labelling a control beside it — exactly
              // the case ListenIconSize reserves the step for. It stays quiet
              // through colour (55% of `onSurfaceVariant`), not through size;
              // at `chrome` it read as a toolbar button that had lost its row.
              size: ListenIconSize.illustration,
              color: colors.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: ListenSpacing.gap12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
