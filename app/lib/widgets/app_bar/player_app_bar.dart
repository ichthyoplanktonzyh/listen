import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';
import 'app_bar_capabilities.dart';

class PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayerAppBar({
    super.key,
    required this.capabilities,
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

  final AppBarCapabilities capabilities;
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _bar(context, constraints.maxWidth >= ListenBreakpoints.appBarLabels),
  );

  Widget _bar(BuildContext context, bool showLabels) {
    final l = AppLocalizations.of(context);

    // Items that act on the loaded media are disabled the moment the menu
    // opens, with the reason in the subtitle slot — mirroring how
    // ContentChannelAvailability carries a reason instead of offering a
    // clickable promise (#24).
    PopupMenuItem<String> mediaGatedItem({
      required String value,
      required IconData icon,
      required String title,
    }) => PopupMenuItem(
      value: value,
      enabled: capabilities.canActOnMedia,
      child: _MenuRow(
        icon: icon,
        title: title,
        enabled: capabilities.canActOnMedia,
        subtitle: capabilities.canActOnMedia
            ? null
            : l.text('statusOpenMediaAndCoreFirst'),
      ),
    );

    return AppBar(
      titleSpacing: 20,
      title: const ListenWordmark(),
      shape: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      actions: [
        _ToolbarMenuButton(
          showLabel: showLabels,
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
            mediaGatedItem(
              value: 'archive-media',
              icon: Icons.archive_outlined,
              title: l.text('archiveMedia'),
            ),
          ],
        ),
        _ToolbarMenuButton(
          showLabel: showLabels,
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
            mediaGatedItem(
              value: 'primary-import',
              icon: Icons.upload_file_outlined,
              title: l.text('importSubtitleHint'),
            ),
            mediaGatedItem(
              value: 'primary-generate',
              icon: Icons.auto_fix_high_outlined,
              title: l.text('generateSubtitles'),
            ),
            mediaGatedItem(
              value: 'primary-search',
              icon: Icons.search_outlined,
              title: l.text('openSubtitles'),
            ),
            const PopupMenuDivider(),
            _MenuHeader(label: l.text('secondarySubtitle')),
            mediaGatedItem(
              value: 'secondary-import',
              icon: Icons.upload_file_outlined,
              title: l.text('importSubtitleHint'),
            ),
            mediaGatedItem(
              value: 'secondary-generate',
              icon: Icons.auto_fix_high_outlined,
              title: l.text('generateSubtitles'),
            ),
            mediaGatedItem(
              value: 'secondary-search',
              icon: Icons.search_outlined,
              title: l.text('openSubtitles'),
            ),
            const PopupMenuDivider(),
            mediaGatedItem(
              value: 'embedded',
              icon: Icons.closed_caption_outlined,
              title: l.text('importEmbeddedText'),
            ),
          ],
        ),
        _ToolbarMenuButton(
          showLabel: showLabels,
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
            _MenuHeader(label: l.text('diagnostics')),
            PopupMenuItem(
              value: 'logs',
              child: _MenuRow(
                icon: Icons.bug_report_outlined,
                title: l.text('exportLogs'),
              ),
            ),
            const PopupMenuDivider(),
            _MenuHeader(label: l.text('dataManagement')),
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
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: ListenSpacing.gap8),
      ],
    );
  }
}

class _ToolbarMenuButton extends StatelessWidget {
  const _ToolbarMenuButton({
    required this.showLabel,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onSelected,
    required this.itemBuilder,
  });

  /// Below [ListenBreakpoints.appBarLabels] the text is dropped and only the
  /// icon remains. The tooltip carries the same wording either way, so this
  /// costs discoverability at a glance, not the name of the menu.
  final bool showLabel;
  final String tooltip;
  final IconData icon;
  final String label;
  final PopupMenuItemSelected<String> onSelected;
  final PopupMenuItemBuilder<String> itemBuilder;

  @override
  Widget build(BuildContext context) {
    // Shell recedes (#30): the bar's menus sit at the variant shade so the
    // stage below stays the brightest thing on screen.
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: ListenIconSize.chrome, color: quiet),
            if (showLabel) ...[
              const SizedBox(width: ListenSpacing.gap6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: quiet,
                ),
              ),
            ],
            const SizedBox(width: ListenSpacing.gap2),
            // Kept in the narrow form too: without it an icon-only button
            // reads as a plain action rather than something opening a menu.
            Icon(
              Icons.arrow_drop_down,
              size: ListenIconSize.control,
              color: quiet,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuHeader extends PopupMenuItem<String> {
  _MenuHeader({required String label})
    : super(
        enabled: false,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The title greys out for free via [PopupMenuItem]'s inherited text style;
  /// the icon and subtitle carry explicit colors, so they follow this flag.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final secondary = enabled
        ? colors.onSurfaceVariant
        : colors.disabledForeground;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Row(
        children: [
          Icon(icon, size: ListenIconSize.control, color: secondary),
          const SizedBox(width: ListenSpacing.gap12),
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
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: secondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
