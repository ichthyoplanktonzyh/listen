import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';

/// The tools that have no other home, collected into one quiet overflow at
/// the foot of the rail.
///
/// This is what is left of the shell app bar. That bar carried five menus,
/// and four of them were copies: "content" repeated the native File menu, the
/// listen page's two primary cards and the transport's open button;
/// "learning" repeated the native Learning menu and the sidebar's own
/// vocabulary and review; settings repeated the rail's own footer; the
/// wordmark repeated the rail's header forty pixels below it. The subtitle
/// menu was the honest one — and it was media-scoped, so on every standing
/// destination it rendered as a row of dead items.
///
/// What survived is genuinely homeless: the asset centres, and the
/// diagnostics and data actions. They are tools, not destinations, so they do
/// not become rail entries — they sit beside settings, which is the other
/// thing at the foot that is not a place you can be.
class ShellToolsMenu extends StatelessWidget {
  const ShellToolsMenu({
    super.key,
    required this.onOpenLearningAssets,
    required this.onOpenLearningResources,
    required this.onExportLogs,
    required this.onExportVocabulary,
    required this.onImportVocabulary,
    required this.onImportWordList,
  });

  final VoidCallback onOpenLearningAssets;
  final VoidCallback onOpenLearningResources;
  final VoidCallback onExportLogs;
  final VoidCallback onExportVocabulary;
  final VoidCallback onImportVocabulary;
  final VoidCallback onImportWordList;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: l.text('shellTools'),
      position: PopupMenuPosition.over,
      onSelected: (value) {
        switch (value) {
          case 'learning-assets':
            onOpenLearningAssets();
          case 'learning-resources':
            onOpenLearningResources();
          case 'logs':
            onExportLogs();
          case 'export-vocabulary':
            onExportVocabulary();
          case 'import-vocabulary':
            onImportVocabulary();
          case 'import-word-list':
            onImportWordList();
        }
      },
      itemBuilder: (_) => [
        ListenMenuHeader(label: l.text('shellToolsCenters')),
        PopupMenuItem(
          value: 'learning-assets',
          child: ListenMenuRow(
            icon: Icons.local_library_outlined,
            title: l.text('learningAssets'),
          ),
        ),
        PopupMenuItem(
          value: 'learning-resources',
          child: ListenMenuRow(
            icon: Icons.storage_outlined,
            title: l.text('resources'),
          ),
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('dataManagement')),
        PopupMenuItem(
          value: 'export-vocabulary',
          child: ListenMenuRow(
            icon: Icons.download_outlined,
            title: l.text('exportAssets'),
          ),
        ),
        PopupMenuItem(
          value: 'import-vocabulary',
          child: ListenMenuRow(
            icon: Icons.upload_outlined,
            title: l.text('importAssets'),
          ),
        ),
        PopupMenuItem(
          value: 'import-word-list',
          child: ListenMenuRow(
            icon: Icons.playlist_add_outlined,
            title: l.text('importWordList'),
          ),
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('diagnostics')),
        PopupMenuItem(
          value: 'logs',
          child: ListenMenuRow(
            icon: Icons.bug_report_outlined,
            title: l.text('exportLogs'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap12,
          vertical: ListenSpacing.gap8,
        ),
        child: Row(
          children: [
            Icon(
              Icons.more_horiz,
              size: ListenIconSize.control,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Text(
                l.text('shellTools'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
