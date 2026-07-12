import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../utils/format_duration.dart';

/// Home media library grouped by triage queue (Phase 3.5 Slice 5).
///
/// Queues are pure suggestions derived from [MediaLibraryEntry.triageQueue]:
/// golden targets float to the top of the intensive group, familiar material
/// feeds the extensive group when the supply toggle is on, and explicit user
/// pins/defers always win. Ignoring the grouping changes nothing — every row
/// opens and plays exactly like any other media (P3/P5 red lines), and copy
/// stays expectation management, never a verdict.
class MediaLibrarySection extends StatelessWidget {
  const MediaLibrarySection({
    super.key,
    required this.entries,
    required this.familiarSupplyEnabled,
    required this.onOpen,
    required this.onStartExtensive,
    required this.onStartIntensive,
    required this.onSetIntent,
    required this.onToggleFamiliarSupply,
  });

  /// Null while the first load is in flight; empty when the library is empty.
  final List<MediaLibraryEntry>? entries;
  final bool familiarSupplyEnabled;
  final void Function(MediaLibraryEntry entry) onOpen;
  final void Function(MediaLibraryEntry entry) onStartExtensive;
  final void Function(MediaLibraryEntry entry) onStartIntensive;
  final void Function(MediaLibraryEntry entry, String? intent) onSetIntent;
  final void Function(bool enabled) onToggleFamiliarSupply;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loaded = entries;
    if (loaded == null) return const SizedBox.shrink();
    final groups = _groupEntries(loaded);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.text('mediaLibrary'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: l.text('settings'),
              icon: Icon(
                Icons.tune_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onSelected: (value) {
                if (value == 'familiar_supply') {
                  onToggleFamiliarSupply(!familiarSupplyEnabled);
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'familiar_supply',
                  checked: familiarSupplyEnabled,
                  child: Text(l.text('familiarSuggestionsToggle')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (loaded.isEmpty)
          Text(
            l.text('mediaLibraryEmpty'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final group in groups) ...[
            _QueueHeader(queue: group.queue, count: group.entries.length),
            const SizedBox(height: 6),
            for (final entry in group.entries) ...[
              _MediaRow(
                entry: entry,
                familiarSupplyEnabled: familiarSupplyEnabled,
                onOpen: () => onOpen(entry),
                onStartExtensive: () => onStartExtensive(entry),
                onStartIntensive: () => onStartIntensive(entry),
                onSetIntent: (intent) => onSetIntent(entry, intent),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// Groups by derived queue, ordered intensive → extensive → deferred →
  /// unsorted, with golden targets pinned to the top of their group. Empty
  /// groups are omitted entirely.
  List<_QueueGroup> _groupEntries(List<MediaLibraryEntry> loaded) {
    final byQueue = <String?, List<MediaLibraryEntry>>{};
    for (final entry in loaded) {
      byQueue
          .putIfAbsent(
            entry.triageQueue(familiarSupply: familiarSupplyEnabled),
            () => [],
          )
          .add(entry);
    }
    final groups = <_QueueGroup>[];
    for (final queue in const [
      TriageQueue.intensive,
      TriageQueue.extensive,
      TriageQueue.deferred,
      TriageQueue.graduated,
      null,
    ]) {
      final members = byQueue[queue];
      if (members == null || members.isEmpty) continue;
      // Stable sort: golden targets first, server order (recency) otherwise.
      final golden = members.where((entry) => entry.isGoldenTarget).toList();
      final rest = members.where((entry) => !entry.isGoldenTarget).toList();
      groups.add(_QueueGroup(queue: queue, entries: [...golden, ...rest]));
    }
    return groups;
  }
}

class _QueueGroup {
  const _QueueGroup({required this.queue, required this.entries});

  final String? queue;
  final List<MediaLibraryEntry> entries;
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.queue, required this.count});

  final String? queue;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final (label, icon) = switch (queue) {
      TriageQueue.intensive => (l.text('queueIntensive'), Icons.headphones_outlined),
      TriageQueue.extensive => (l.text('queueExtensive'), Icons.play_circle_outline),
      TriageQueue.deferred => (l.text('queueDeferred'), Icons.snooze_outlined),
      TriageQueue.graduated => (l.text('queueGraduated'), Icons.check_circle_outline),
      _ => (l.text('queueUnsorted'), Icons.help_outline),
    };
    return Row(
      children: [
        Icon(icon, size: 15, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.entry,
    required this.familiarSupplyEnabled,
    required this.onOpen,
    required this.onStartExtensive,
    required this.onStartIntensive,
    required this.onSetIntent,
  });

  final MediaLibraryEntry entry;
  final bool familiarSupplyEnabled;
  final VoidCallback onOpen;
  final VoidCallback onStartExtensive;
  final VoidCallback onStartIntensive;
  final void Function(String? intent) onSetIntent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final fit = entry.fit;
    final duration = entry.media.durationMs;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Icon(
                entry.media.kind == 'audio'
                    ? Icons.audiotrack_outlined
                    : Icons.movie_outlined,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (duration != null && duration > 0)
                          Text(
                            formatDuration(Duration(milliseconds: duration)),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        if (fit != null) ...[
                          _MiniFitChip(
                            label: l.text('contentFitMeaning'),
                            fit: fit.meaning.fit,
                          ),
                          _MiniFitChip(
                            label: l.text('contentFitSound'),
                            fit: fit.sound.fit,
                          ),
                        ],
                        if (entry.isGoldenTarget)
                          _Badge(
                            icon: Icons.headphones_outlined,
                            label: l.text('goldenTargetBadge'),
                            color: colors.primary,
                          ),
                        if (entry.familiarMaterial && familiarSupplyEnabled)
                          _Badge(
                            icon: Icons.replay_outlined,
                            label: l.text('familiarRelistenBadge'),
                            color: colors.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: onStartExtensive,
                child: Text(l.text('startExtensiveAction')),
              ),
              TextButton(
                onPressed: onStartIntensive,
                child: Text(l.text('startIntensiveAction')),
              ),
              PopupMenuButton<String>(
                tooltip: l.text('moreActions'),
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                onSelected: (value) =>
                    onSetIntent(value == 'clear' ? null : value),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: 'pin_extensive',
                    checked: entry.triageIntent == 'pin_extensive',
                    child: Text(l.text('pinExtensiveAction')),
                  ),
                  CheckedPopupMenuItem(
                    value: 'pin_intensive',
                    checked: entry.triageIntent == 'pin_intensive',
                    child: Text(l.text('pinIntensiveAction')),
                  ),
                  CheckedPopupMenuItem(
                    value: 'defer',
                    checked: entry.triageIntent == 'defer',
                    child: Text(l.text('deferMediaAction')),
                  ),
                  if (entry.triageIntent != null)
                    PopupMenuItem(
                      value: 'clear',
                      child: Text(l.text('clearTriageAction')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact per-row rendition of the fit chips from the content fit card:
/// same band vocabulary (`fit_*` keys), smaller footprint. Bands only —
/// never raw densities (invariant 18).
class _MiniFitChip extends StatelessWidget {
  const _MiniFitChip({required this.label, required this.fit});

  final String label;
  final String fit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              l.text('fit_$fit'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
