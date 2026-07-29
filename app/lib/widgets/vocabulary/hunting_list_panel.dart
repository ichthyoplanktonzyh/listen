import 'package:flutter/material.dart';

import '../../controllers/hunting_controller.dart';
import '../../localization.dart';
import '../../models/practice.dart';
import '../../theme/spacing.dart';

class HuntingListPanel extends StatelessWidget {
  const HuntingListPanel({
    super.key,
    required this.controller,
    required this.onRefresh,
    required this.onPromoteCandidate,
    required this.onArchiveTarget,
    this.onOpenEntry,
  });

  final HuntingController controller;
  final Future<void> Function() onRefresh;
  final Future<void> Function(HuntingCandidate candidate) onPromoteCandidate;
  final Future<void> Function(HuntingTarget target) onArchiveTarget;
  final ValueChanged<String>? onOpenEntry;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final state = controller.state;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.text('huntingList'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: ListenSpacing.gap2),
                      Text(
                        l
                            .text('huntingTargetCount')
                            .replaceAll('{count}', '${state.targets.length}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l.text('refresh'),
                  onPressed: state.busy ? null : () => onRefresh(),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: l.text('close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (state.busy) const LinearProgressIndicator(minHeight: 2),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                _SectionLabel(l.text('huntingActiveTargets')),
                if (state.targets.isEmpty)
                  _EmptyCard(text: l.text('huntingNoTargets'))
                else
                  for (final target in state.targets)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.gps_fixed),
                        title: Text(target.targetSnapshot),
                        subtitle: Text(
                          l.text(
                            target.sourceKind == 'review_candidate'
                                ? 'huntingSourceReview'
                                : target.sourceKind == 'listening_inbox'
                                ? 'huntingSourceInbox'
                                : 'huntingSourceManual',
                          ),
                        ),
                        onTap: onOpenEntry == null
                            ? null
                            : () => onOpenEntry!(target.lexicalEntryId),
                        trailing: IconButton(
                          tooltip: l.text('huntingArchive'),
                          onPressed: state.busy
                              ? null
                              : () => onArchiveTarget(target),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ),
                    ),
                const SizedBox(height: ListenSpacing.gap12),
                _SectionLabel(l.text('huntingReviewCandidates')),
                if (state.candidates.isEmpty)
                  _EmptyCard(text: l.text('huntingNoCandidates'))
                else
                  for (final candidate in state.candidates)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.hearing_outlined),
                        title: Text(candidate.targetSnapshot),
                        subtitle: Text(
                          l
                              .text('huntingFailureCount')
                              .replaceAll(
                                '{count}',
                                '${candidate.failureCount}',
                              ),
                        ),
                        onTap: onOpenEntry == null
                            ? null
                            : () => onOpenEntry!(candidate.lexicalEntryId),
                        trailing: FilledButton.tonal(
                          onPressed:
                              state.busy ||
                                  state.containsLexicalEntry(
                                    candidate.lexicalEntryId,
                                  )
                              ? null
                              : () => onPromoteCandidate(candidate),
                          child: Text(l.text('huntingAdd')),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
