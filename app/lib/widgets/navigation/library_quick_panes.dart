import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Shared shell for the lightweight library panes: a titled list fed by the
/// media library, with an explicit empty state and refresh affordance.
class _LibraryPaneShell extends StatelessWidget {
  const _LibraryPaneShell({
    required this.title,
    required this.entries,
    required this.emptyLabel,
    required this.onReload,
    required this.itemBuilder,
  });

  final String title;
  final List<MediaLibraryEntry>? entries;
  final String emptyLabel;
  final VoidCallback onReload;
  final Widget Function(BuildContext, MediaLibraryEntry) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final loaded = entries;

    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap16,
              vertical: ListenSpacing.gap12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.text('sidebarMyResources'),
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh, size: ListenIconSize.control),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: loaded == null || loaded.isEmpty
                ? _EmptyState(label: emptyLabel, onReload: onReload)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: ListenSpacing.gap8,
                    ),
                    itemCount: loaded.length,
                    itemBuilder: (context, index) =>
                        itemBuilder(context, loaded[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label, required this.onReload});

  final String label;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: ListenIconSize.illustration,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap12),
          OutlinedButton.icon(
            onPressed: onReload,
            icon: const Icon(Icons.refresh, size: ListenIconSize.inline),
            label: Text(l.text('sidebarMyResources')),
          ),
        ],
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: ListenRadii.surfaceBorder,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap16,
          vertical: ListenSpacing.gap8,
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_outline,
              size: ListenIconSize.control,
              color: scheme.primary,
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: ListenSpacing.gap2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight history list: media library rows sorted by most recent update.
/// (Offline used to be a sibling pane here; it is a filter on the content
/// home's library section now, since both read the same media library.)
class HistoryPane extends StatelessWidget {
  const HistoryPane({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onReload,
  });

  final List<MediaLibraryEntry>? entries;
  final ValueChanged<MediaLibraryEntry> onOpen;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = [...?entries]
      ..sort((a, b) => b.media.updatedAtMs.compareTo(a.media.updatedAtMs));

    return _LibraryPaneShell(
      title: l.text('sidebarHistory'),
      entries: history,
      emptyLabel: l.text('historyEmpty'),
      onReload: onReload,
      itemBuilder: (context, entry) {
        final updated = DateTime.fromMillisecondsSinceEpoch(
          entry.media.updatedAtMs,
        );
        final local = updated.toLocal();
        final date =
            '${local.year}-${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')}';
        return _LibraryRow(
          title: entry.media.title,
          subtitle: date,
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}
