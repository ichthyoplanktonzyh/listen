import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';
import '../common/menu_rows.dart';

/// The session header's retention affordance for the current media.
///
/// Two shapes, one control:
///
/// * Temporary Material (opened/scanned, never explicitly kept) shows a Keep
///   entry with two choices — the default "keep a copy" into the managed
///   store, and the secondary "keep as reference" that retains without
///   copying. The default is the copy; the reference is never first.
/// * Personal Library material shows its retained state and offers the
///   unretain action, which changes membership only.
///
/// In-flight operations render as the unified waiting mark ([ListenLoading])
/// and refuse re-entry; success and failure feedback lands on the status line
/// through the coordinator, never as an exception here.
class RetentionMenu extends StatelessWidget {
  const RetentionMenu({
    super.key,
    required this.player,
    required this.onKeepCopy,
    required this.onKeepReference,
    required this.onUnretain,
  });

  final PlayerController player;
  final VoidCallback onKeepCopy;
  final VoidCallback onKeepReference;
  final VoidCallback onUnretain;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        if (player.mediaPath == null) return const SizedBox.shrink();
        if (player.retentionInFlight) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
            child: ListenLoading.inline(),
          );
        }
        final retained = player.mediaRetained == true;
        return PopupMenuButton<String>(
          key: const Key('retention-menu'),
          tooltip: retained
              ? l.text('retentionRetainedLabel')
              : l.text('retentionKeepAction'),
          onSelected: (value) {
            switch (value) {
              case 'keep-copy':
                onKeepCopy();
              case 'keep-reference':
                onKeepReference();
              case 'unretain':
                onUnretain();
            }
          },
          itemBuilder: (context) => retained
              ? [
                  PopupMenuItem(
                    value: 'unretain',
                    child: ListenMenuRow(
                      icon: Icons.remove_circle_outline,
                      title: l.text('retentionUnkeepAction'),
                    ),
                  ),
                ]
              : [
                  PopupMenuItem(
                    value: 'keep-copy',
                    child: ListenMenuRow(
                      icon: Icons.content_copy_outlined,
                      title: l.text('retentionKeepCopyAction'),
                      subtitle: l.text('retentionKeepCopyHint'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'keep-reference',
                    child: ListenMenuRow(
                      icon: Icons.link_outlined,
                      title: l.text('retentionReferenceAction'),
                      subtitle: l.text('retentionReferenceHint'),
                    ),
                  ),
                ],
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: retained
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: ListenRadii.controlBorder,
              border: Border.all(
                color: retained
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: ListenPadding.row,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    retained
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_border_outlined,
                    size: ListenIconSize.control,
                    color: retained
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: ListenSpacing.gap6),
                  Text(
                    retained
                        ? l.text('retentionRetainedLabel')
                        : l.text('retentionKeepAction'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: retained
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: ListenIconSize.control,
                    color: retained
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
