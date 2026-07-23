import 'package:flutter/material.dart';

import '../../controllers/reading_diff_controller.dart';
import '../../localization.dart';
import '../../models/reading_diff.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../common/listen_loading.dart';

/// In-scene read/listen comparison. It is an outcome card, not a blocking
/// decision, so it stays in the task scene and never opens a dialog.
class ReadingDiffPanel extends StatelessWidget {
  const ReadingDiffPanel({
    super.key,
    required this.controller,
    required this.onOpenReadingTask,
    required this.onOpenListeningCheck,
    required this.onClose,
  });

  final ReadingDiffController controller;
  final VoidCallback onOpenReadingTask;
  final VoidCallback onOpenListeningCheck;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final colors = Theme.of(context).colorScheme;
      final state = controller.state;
      return Material(
        color: colors.surface,
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('reading-diff-back'),
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Icon(Icons.compare_arrows, color: colors.primary),
                    const SizedBox(width: ListenSpacing.gap8),
                    Text(
                      l.text('readingDiffTitle'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: state.loading
                      ? const ListenLoading()
                      : ListView(
                          padding: const EdgeInsets.all(32),
                          shrinkWrap: true,
                          children: [
                            if (state.error != null)
                              Text(
                                state.error!,
                                style: TextStyle(color: colors.error),
                              ),
                            _sideCard(
                              context,
                              icon: Icons.chrome_reader_mode_outlined,
                              label: l.text('readingDiffRead'),
                              side: state.read,
                              onOpen: onOpenReadingTask,
                              openLabel: l.text('readingDiffOpenReading'),
                            ),
                            const SizedBox(height: ListenSpacing.gap12),
                            _sideCard(
                              context,
                              icon: Icons.hearing_outlined,
                              label: l.text('readingDiffListen'),
                              side: state.listen,
                              onOpen: onOpenListeningCheck,
                              openLabel: l.text('readingDiffOpenListening'),
                            ),
                            const SizedBox(height: ListenSpacing.gap16),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: ListenRadii.surfaceBorder,
                              ),
                              child: Text(
                                l.text(state.explanationKey),
                                style: ListenType.emphasis.copyWith(
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _sideCard(
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
      SideOutcome.yes => ('outcomeYes', colors.verdictCovered),
      SideOutcome.partial => ('outcomePartial', colors.verdictPartial),
      SideOutcome.no => ('outcomeNo', colors.error),
      SideOutcome.unassessed => ('outcomeUnassessed', colors.onSurfaceVariant),
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              l.text(outcomeKey),
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(width: ListenSpacing.gap12),
            OutlinedButton(onPressed: onOpen, child: Text(openLabel)),
          ],
        ),
      ),
    );
  }
}
