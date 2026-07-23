import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../localization.dart';
import '../../models/listening.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/listen_empty_state.dart';
import '../common/listen_error_state.dart';

class ListeningInboxPanel extends StatelessWidget {
  const ListeningInboxPanel({
    super.key,
    required this.controller,
    required this.onRefresh,
    required this.onReplay,
    required this.onProcess,
  });

  final ExtensiveListeningController controller;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ListeningInboxItem item) onReplay;
  final Future<void> Function(ListeningInboxItem item, String resolution)
  onProcess;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final items = controller.items;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Icon(
                  controller.active ? Icons.hearing : Icons.hearing_disabled,
                  size: 18,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    controller.active
                        ? l.text('extensiveListeningActive')
                        : l.text('extensiveListeningIdle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l.text('refresh'),
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(onRefresh()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListenErrorNotice(message: controller.error!),
            ),
          Expanded(
            child: items.isEmpty
                ? ListenEmptyState(
                    icon: Icons.inbox_outlined,
                    message: l.text('listeningInboxEmpty'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ListenSpacing.gap8),
                    itemBuilder: (context, index) => _InboxTile(
                      item: items[index],
                      onReplay: () => unawaited(onReplay(items[index])),
                      onProcess: (resolution) =>
                          unawaited(onProcess(items[index], resolution)),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.onReplay,
    required this.onProcess,
  });

  final ListeningInboxItem item;
  final VoidCallback onReplay;
  final ValueChanged<String> onProcess;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final start = item.playbackStartMs == null
        ? null
        : formatDuration(Duration(milliseconds: item.playbackStartMs!));
    final end = item.playbackEndMs == null
        ? null
        : formatDuration(Duration(milliseconds: item.playbackEndMs!));
    final subtitle = start == null || end == null ? null : '$start-$end';
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: ListenRadii.controlBorder),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bookmark_added_outlined, size: 18),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    item.label ?? item.subtitleSnapshot,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Text(
              item.subtitleSnapshot,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.contextBefore != null || item.contextAfter != null) ...[
              const SizedBox(height: ListenSpacing.gap6),
              Text(
                [
                  if (item.contextBefore != null) item.contextBefore!,
                  if (item.contextAfter != null) item.contextAfter!,
                ].join(' / '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
            const SizedBox(height: ListenSpacing.gap8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: l.text('replay'),
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay),
                ),
                IconButton(
                  tooltip: l.text('saveToReview'),
                  onPressed: () => onProcess('review_item'),
                  icon: const Icon(Icons.add_task),
                ),
                IconButton(
                  tooltip: l.text('microIntensive'),
                  onPressed: () => onProcess('micro_intensive'),
                  icon: const Icon(Icons.fact_check_outlined),
                ),
                IconButton(
                  tooltip: l.text('favoriteSegment'),
                  onPressed: () => onProcess('favorite'),
                  icon: const Icon(Icons.star_border),
                ),
                IconButton(
                  tooltip: l.text('dismissInboxItem'),
                  onPressed: () => onProcess('dismissed'),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
