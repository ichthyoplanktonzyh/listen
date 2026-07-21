import 'package:flutter/material.dart';

import '../../localization.dart';

class PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayerAppBar({
    super.key,
    required this.onOpenSubtitleResources,
    required this.onOpenVocabulary,
    required this.onOpenReview,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onImportPrimarySubtitle,
    required this.onGeneratePrimarySubtitles,
    required this.onSearchPrimarySubtitles,
    required this.onImportSecondarySubtitle,
    required this.onGenerateSecondarySubtitles,
    required this.onSearchSecondarySubtitles,
    required this.onImportEmbeddedSubtitle,
    required this.onOpenSettings,
    required this.onExportLogs,
    required this.onExportVocabulary,
    required this.onImportVocabulary,
    required this.onImportWordList,
    required this.onArchiveMedia,
    required this.onOpenTranscriptionCenter,
    required this.onOpenPhoneticAnalysisCenter,
    required this.onOpenLearningAssets,
    required this.onOpenLearningResources,
  });

  final VoidCallback onOpenSubtitleResources;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onImportPrimarySubtitle;
  final VoidCallback onGeneratePrimarySubtitles;
  final VoidCallback onSearchPrimarySubtitles;
  final VoidCallback onImportSecondarySubtitle;
  final VoidCallback onGenerateSecondarySubtitles;
  final VoidCallback onSearchSecondarySubtitles;
  final VoidCallback onImportEmbeddedSubtitle;
  final VoidCallback onOpenSettings;
  final VoidCallback onExportLogs;
  final VoidCallback onExportVocabulary;
  final VoidCallback onImportVocabulary;
  final VoidCallback onImportWordList;
  final VoidCallback onArchiveMedia;
  final VoidCallback onOpenTranscriptionCenter;
  final VoidCallback onOpenPhoneticAnalysisCenter;
  final VoidCallback onOpenLearningAssets;
  final VoidCallback onOpenLearningResources;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      titleSpacing: 20,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          const Text('listen', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      shape: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      actions: [
        _ToolbarMenuButton(
          tooltip: l.text('contentActions'),
          icon: Icons.folder_open_outlined,
          label: l.text('contentActions'),
          onSelected: (value) {
            if (value == 'open-media') onOpenMedia();
            if (value == 'open-online') onOpenOnline();
            if (value == 'archive-media') onArchiveMedia();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'open-media',
              child: _MenuRow(
                icon: Icons.video_file_outlined,
                title: l.text('openMedia'),
                subtitle: l.text('localSource'),
              ),
            ),
            PopupMenuItem(
              value: 'open-online',
              child: _MenuRow(
                icon: Icons.language_outlined,
                title: l.text('openUrl'),
                subtitle: l.text('onlineSource'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'archive-media',
              child: _MenuRow(
                icon: Icons.archive_outlined,
                title: l.text('archiveMedia'),
              ),
            ),
          ],
        ),
        _ToolbarMenuButton(
          tooltip: l.text('subtitleActions'),
          icon: Icons.subtitles_outlined,
          label: l.text('subtitleActions'),
          onSelected: (value) {
            if (value == 'primary-import') onImportPrimarySubtitle();
            if (value == 'primary-generate') onGeneratePrimarySubtitles();
            if (value == 'primary-search') onSearchPrimarySubtitles();
            if (value == 'secondary-import') onImportSecondarySubtitle();
            if (value == 'secondary-generate') onGenerateSecondarySubtitles();
            if (value == 'secondary-search') onSearchSecondarySubtitles();
            if (value == 'embedded') onImportEmbeddedSubtitle();
          },
          itemBuilder: (_) => [
            _MenuHeader(label: l.text('primarySubtitle')),
            PopupMenuItem(
              value: 'primary-import',
              child: _MenuRow(
                icon: Icons.upload_file_outlined,
                title: l.text('importSubtitleHint'),
              ),
            ),
            PopupMenuItem(
              value: 'primary-generate',
              child: _MenuRow(
                icon: Icons.auto_fix_high_outlined,
                title: l.text('generateSubtitles'),
              ),
            ),
            PopupMenuItem(
              value: 'primary-search',
              child: _MenuRow(
                icon: Icons.search_outlined,
                title: l.text('openSubtitles'),
              ),
            ),
            const PopupMenuDivider(),
            _MenuHeader(label: l.text('secondarySubtitle')),
            PopupMenuItem(
              value: 'secondary-import',
              child: _MenuRow(
                icon: Icons.upload_file_outlined,
                title: l.text('importSubtitleHint'),
              ),
            ),
            PopupMenuItem(
              value: 'secondary-generate',
              child: _MenuRow(
                icon: Icons.auto_fix_high_outlined,
                title: l.text('generateSubtitles'),
              ),
            ),
            PopupMenuItem(
              value: 'secondary-search',
              child: _MenuRow(
                icon: Icons.search_outlined,
                title: l.text('openSubtitles'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'embedded',
              child: _MenuRow(
                icon: Icons.closed_caption_outlined,
                title: l.text('importEmbeddedText'),
              ),
            ),
          ],
        ),
        _ToolbarMenuButton(
          tooltip: l.text('learningActions'),
          icon: Icons.school_outlined,
          label: l.text('learningActions'),
          onSelected: (value) {
            if (value == 'subtitle-resources') onOpenSubtitleResources();
            if (value == 'vocabulary') onOpenVocabulary();
            if (value == 'review') onOpenReview();
            if (value == 'learning-assets') onOpenLearningAssets();
            if (value == 'learning-resources') onOpenLearningResources();
            if (value == 'transcription') onOpenTranscriptionCenter();
            if (value == 'phonetic-analysis') onOpenPhoneticAnalysisCenter();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'subtitle-resources',
              child: _MenuRow(
                icon: Icons.inventory_2_outlined,
                title: l.text('subtitleResources'),
                subtitle: l.text('subtitleResourceSummary'),
              ),
            ),
            PopupMenuItem(
              value: 'vocabulary',
              child: _MenuRow(
                icon: Icons.menu_book_outlined,
                title: l.text('vocabulary'),
                subtitle: l.text('vocabularySummary'),
              ),
            ),
            PopupMenuItem(
              value: 'review',
              child: _MenuRow(
                icon: Icons.headphones_outlined,
                title: l.text('review'),
                subtitle: l.text('audioFirstReview'),
              ),
            ),
            PopupMenuItem(
              value: 'learning-assets',
              child: _MenuRow(
                icon: Icons.local_library_outlined,
                title: l.text('learningAssets'),
              ),
            ),
            PopupMenuItem(
              value: 'learning-resources',
              child: _MenuRow(
                icon: Icons.storage_outlined,
                title: l.text('resources'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'transcription',
              child: _MenuRow(
                icon: Icons.record_voice_over_outlined,
                title: l.text('transcriptionCenter'),
              ),
            ),
            PopupMenuItem(
              value: 'phonetic-analysis',
              child: _MenuRow(
                icon: Icons.graphic_eq,
                title: l.text('phoneticAnalysisCenter'),
              ),
            ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: l.text('moreActions'),
          onSelected: (value) {
            if (value == 'logs') onExportLogs();
            if (value == 'export-vocabulary') onExportVocabulary();
            if (value == 'import-vocabulary') onImportVocabulary();
            if (value == 'import-word-list') onImportWordList();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'logs',
              child: _MenuRow(
                icon: Icons.bug_report_outlined,
                title: l.text('exportLogs'),
              ),
            ),
            PopupMenuItem(
              value: 'export-vocabulary',
              child: _MenuRow(
                icon: Icons.download_outlined,
                title: l.text('exportAssets'),
              ),
            ),
            PopupMenuItem(
              value: 'import-vocabulary',
              child: _MenuRow(
                icon: Icons.upload_outlined,
                title: l.text('importAssets'),
              ),
            ),
            PopupMenuItem(
              value: 'import-word-list',
              child: _MenuRow(
                icon: Icons.playlist_add_outlined,
                title: l.text('importWordList'),
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: l.text('settings'),
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _ToolbarMenuButton extends StatelessWidget {
  const _ToolbarMenuButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final PopupMenuItemSelected<String> onSelected;
  final PopupMenuItemBuilder<String> itemBuilder;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tooltip,
    onSelected: onSelected,
    itemBuilder: itemBuilder,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    ),
  );
}

class _MenuHeader extends PopupMenuItem<String> {
  _MenuHeader({required String label})
    : super(
        enabled: false,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
