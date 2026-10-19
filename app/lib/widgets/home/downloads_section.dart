import 'package:flutter/material.dart';

import '../../controllers/downloads_controller.dart';
import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/api_failure_disclosure.dart';

/// The downloads shelf on the library page: media that is on this machine but
/// not in the Personal Library.
///
/// It exists because that state had no home. Acquisition registers a download
/// as Temporary Material, which neither library listing includes, so a
/// downloaded episode was visible only on the feed row it came from — and the
/// disk filled up with files the app would not admit to having.
///
/// The section states what it is rather than implying membership: these are
/// files, kept material is elsewhere, and keeping still happens where it
/// always did — in the workbench, on purpose. Two actions, because there are
/// only two things to want here: open it, or take the space back.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({
    super.key,
    required this.entries,
    required this.failure,
    required this.onOpen,
    required this.onDelete,
  });

  /// Null while the first load is in flight; empty when nothing is downloaded.
  final List<DownloadedMedia>? entries;

  /// Set when the shelf could not be built. An empty list with a failure is a
  /// broken surface, not an empty one.
  final ApiFailure? failure;

  final void Function(DownloadedMedia entry) onOpen;

  /// Deletes the file. The caller confirms first — this widget only asks.
  final void Function(DownloadedMedia entry) onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rows = entries;
    // Nothing loaded and nothing wrong: the section has nothing to say yet,
    // and an empty heading would be a claim about an unknown.
    if (rows == null && failure == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.text('downloadsSectionTitle'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (rows != null && rows.isNotEmpty) ...[
              const SizedBox(width: ListenSpacing.gap8),
              Text(
                '${rows.length}',
                style: text.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l.text('downloadsSectionSubtitle'),
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: ListenSpacing.gap12),
        if (failure != null)
          ApiFailureNotice(
            message: l.text('downloadsSectionFailed'),
            failure: failure,
          )
        else if (rows!.isEmpty)
          Text(
            l.text('downloadsSectionEmpty'),
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          )
        else
          for (final entry in rows) ...[
            _DownloadRow(
              entry: entry,
              onOpen: () => onOpen(entry),
              onDelete: () => onDelete(entry),
            ),
            const SizedBox(height: ListenSpacing.gap8),
          ],
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final DownloadedMedia entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final duration = entry.durationMs;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: ListenPadding.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              entry.media.kind == 'video'
                  ? Icons.movie_outlined
                  : Icons.headphones_outlined,
              size: ListenIconSize.control,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: ListenSpacing.gap2),
                  Text(
                    duration == null
                        ? entry.path
                        : '${formatDuration(Duration(milliseconds: duration))} · ${entry.path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ListenSpacing.gap12),
            FilledButton.tonal(
              onPressed: onOpen,
              child: Text(l.text('libraryOpenAction')),
            ),
            const SizedBox(width: ListenSpacing.gap4),
            IconButton(
              onPressed: onDelete,
              tooltip: l.text('downloadsDeleteAction'),
              icon: Icon(
                Icons.delete_outline,
                size: ListenIconSize.control,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
