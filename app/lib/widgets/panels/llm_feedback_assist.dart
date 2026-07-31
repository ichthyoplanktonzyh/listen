import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Free-text LLM feedback block for the output-task studios (Speaking and
/// Writing). Unlike the Reading judgment assist there are no per-point
/// verdicts: the provider sees the full source context and answers like a
/// teacher, in prose. Hosts hide it entirely (via [visible]) when no capable
/// provider is configured; the feedback is ephemeral and never becomes
/// learning evidence.
class LlmFeedbackAssist extends StatelessWidget {
  const LlmFeedbackAssist({
    super.key,
    required this.visible,
    required this.feedback,
    required this.busy,
    required this.keyPrefix,
    required this.onRequest,
  });

  final bool visible;
  final String? feedback;
  final bool busy;

  /// Studio-specific test-key namespace, e.g. `speaking-task`.
  final String keyPrefix;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final feedback = this.feedback;
    return Padding(
      padding: const EdgeInsets.only(top: ListenSpacing.gap12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: ListenSpacing.gap8),
          if (feedback == null)
            OutlinedButton.icon(
              key: ValueKey('$keyPrefix-request-ai'),
              onPressed: busy ? null : onRequest,
              icon: const Icon(
                Icons.auto_awesome_outlined,
                size: ListenIconSize.control,
              ),
              label: Text(l.text('llmFeedbackRequest')),
            )
          else ...[
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: ListenIconSize.inline,
                  color: colors.tertiary,
                ),
                const SizedBox(width: ListenSpacing.gap6),
                Text(
                  l.text('llmFeedbackTitle'),
                  style: ListenType.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap2),
            Text(
              l.text('llmFeedbackNote'),
              style: ListenType.caption.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: ListenSpacing.gap8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: ListenRadii.controlBorder,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  feedback,
                  key: ValueKey('$keyPrefix-ai-feedback-text'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
