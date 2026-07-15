import 'package:flutter/material.dart';

import '../../controllers/reading_diff_controller.dart';
import '../../localization.dart';
import '../../models/reading_diff.dart';

/// Read-listen pairing card (Phase 3.13 Slice 4). Presents both sides'
/// reduced outcomes over the same source segment plus a possibilities-worded
/// explanation. Missing sides show as "not assessed" — never as failure.
class ReadingDiffDialog extends StatelessWidget {
  const ReadingDiffDialog({
    super.key,
    required this.controller,
    required this.onOpenReadingTask,
    required this.onOpenListeningCheck,
  });

  final ReadingDiffController controller;
  final VoidCallback onOpenReadingTask;
  final VoidCallback onOpenListeningCheck;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final colors = Theme.of(context).colorScheme;
      final state = controller.state;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.compare_arrows, color: colors.primary),
            const SizedBox(width: 8),
            Text(l.text('readingDiffTitle')),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: state.loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.error != null)
                      Text(
                        state.error!,
                        style: TextStyle(color: colors.error, fontSize: 12),
                      ),
                    _sideRow(
                      context,
                      icon: Icons.chrome_reader_mode_outlined,
                      label: l.text('readingDiffRead'),
                      side: state.read,
                      onOpen: onOpenReadingTask,
                      openLabel: l.text('readingDiffOpenReading'),
                    ),
                    const SizedBox(height: 8),
                    _sideRow(
                      context,
                      icon: Icons.hearing_outlined,
                      label: l.text('readingDiffListen'),
                      side: state.listen,
                      onOpen: onOpenListeningCheck,
                      openLabel: l.text('readingDiffOpenListening'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l.text(state.explanationKey),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l.text('readingTaskClose')),
          ),
        ],
      );
    },
  );

  Widget _sideRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required DiffSide side,
    required VoidCallback onOpen,
    required String openLabel,
  }) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final (outcomeKey, color) = switch (side.outcome) {
      SideOutcome.yes => ('outcomeYes', Colors.green.shade700),
      SideOutcome.partial => ('outcomePartial', Colors.orange.shade800),
      SideOutcome.no => ('outcomeNo', colors.error),
      SideOutcome.unassessed => ('outcomeUnassessed', colors.onSurfaceVariant),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(
          l.text(outcomeKey),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: onOpen,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: Text(openLabel, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
