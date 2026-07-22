import 'package:flutter/material.dart';

import '../../localization.dart';

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
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (feedback == null)
            OutlinedButton.icon(
              key: ValueKey('$keyPrefix-request-ai'),
              onPressed: busy ? null : onRequest,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(l.text('llmFeedbackRequest')),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: colors.tertiary),
                const SizedBox(width: 6),
                Text(
                  l.text('llmFeedbackTitle'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l.text('llmFeedbackNote'),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
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
