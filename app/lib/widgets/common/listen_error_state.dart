import 'package:flutter/material.dart';

import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// The unified error language (#46): two container forms, one voice.
///
/// - [ListenErrorState] — the panel's body failed to load: mirrors
///   `ListenEmptyState` geometry (glyph, one sentence, optional recovery
///   action) so empty and failed read as siblings, with the glyph in the
///   error role marking which sibling this is.
/// - [ListenErrorNotice] — a step inside a living flow failed: a quiet
///   inline surface (`errorContainer`) that sits in the panel's normal flow
///   instead of hijacking it.
///
/// Only the *form* is owned here; the error hues themselves are theme roles
/// and belong to the #22 contrast pass. Errors state facts — they don't
/// shout, blink, or moralize (charter principle 5).
class ListenErrorState extends StatelessWidget {
  const ListenErrorState({super.key, required this.message, this.action});

  /// What failed — shown verbatim, so callers pass an already-localized (or
  /// backend-provided) message.
  final String message;

  /// Optional recovery action, usually a retry button.
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
            // `illustration` for the same reason as [ListenEmptyState]: the
            // glyph is what marks which sibling state this is, with no label
            // beside it. The two must stay the same step — the whole point of
            // mirroring their geometry is that empty and failed read as one
            // language, and a size difference would be the loudest thing on
            // either screen.
            Icon(
              Icons.error_outline,
              size: ListenIconSize.illustration,
              color: colors.error,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurface),
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

/// Inline error container: error surface, small glyph, the message — nothing
/// else. Replaces bare red `Text(error)` lines so flow-level failures share
/// one form.
class ListenErrorNotice extends StatelessWidget {
  const ListenErrorNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap12,
          vertical: ListenSpacing.gap8,
        ),
        child: Row(
          children: [
            // `control`, not `illustration`: here the glyph leads a row and
            // labels the sentence next to it, which is the default step's job.
            Icon(
              Icons.error_outline,
              size: ListenIconSize.control,
              color: colors.onErrorContainer,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
