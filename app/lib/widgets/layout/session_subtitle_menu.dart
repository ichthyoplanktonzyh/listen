import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';

/// Subtitle sourcing for the media on the workbench: import, generate or
/// search, per track, plus the embedded-text import and archiving.
///
/// It lives on the session header rather than on a shell app bar, and that is
/// the point: every item here acts on *this* media. On the app bar the same
/// items had to be gated by `canActOnMedia` and rendered as a row of dead
/// entries on every standing destination — honest, but useless. The session
/// header only exists while media is open, so the gate is the widget's own
/// existence and no item here can ever be dead.
class SessionSubtitleMenu extends StatelessWidget {
  const SessionSubtitleMenu({
    super.key,
    required this.onImportPrimarySubtitle,
    required this.onGeneratePrimarySubtitles,
    required this.onSearchPrimarySubtitles,
    required this.onImportSecondarySubtitle,
    required this.onGenerateSecondarySubtitles,
    required this.onSearchSecondarySubtitles,
    required this.onImportEmbeddedSubtitle,
    required this.onArchiveMedia,
  });

  final VoidCallback onImportPrimarySubtitle;
  final VoidCallback onGeneratePrimarySubtitles;
  final VoidCallback onSearchPrimarySubtitles;
  final VoidCallback onImportSecondarySubtitle;
  final VoidCallback onGenerateSecondarySubtitles;
  final VoidCallback onSearchSecondarySubtitles;
  final VoidCallback onImportEmbeddedSubtitle;
  final VoidCallback onArchiveMedia;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;

    return PopupMenuButton<String>(
      tooltip: l.text('subtitleActions'),
      onSelected: (value) {
        switch (value) {
          case 'import-primary':
            onImportPrimarySubtitle();
          case 'generate-primary':
            onGeneratePrimarySubtitles();
          case 'search-primary':
            onSearchPrimarySubtitles();
          case 'import-secondary':
            onImportSecondarySubtitle();
          case 'generate-secondary':
            onGenerateSecondarySubtitles();
          case 'search-secondary':
            onSearchSecondarySubtitles();
          case 'import-embedded':
            onImportEmbeddedSubtitle();
          case 'archive-media':
            onArchiveMedia();
        }
      },
      itemBuilder: (_) => [
        ListenMenuHeader(label: l.text('primarySubtitle')),
        PopupMenuItem(
          value: 'import-primary',
          child: ListenMenuRow(
            icon: Icons.upload_file_outlined,
            title: l.text('importSubtitleHint'),
          ),
        ),
        PopupMenuItem(
          value: 'generate-primary',
          child: ListenMenuRow(
            icon: Icons.auto_fix_high_outlined,
            title: l.text('generateSubtitles'),
          ),
        ),
        PopupMenuItem(
          value: 'search-primary',
          child: ListenMenuRow(
            icon: Icons.search_outlined,
            title: l.text('openSubtitles'),
          ),
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('secondarySubtitle')),
        PopupMenuItem(
          value: 'import-secondary',
          child: ListenMenuRow(
            icon: Icons.upload_file_outlined,
            title: l.text('importSubtitleHint'),
          ),
        ),
        PopupMenuItem(
          value: 'generate-secondary',
          child: ListenMenuRow(
            icon: Icons.auto_fix_high_outlined,
            title: l.text('generateSubtitles'),
          ),
        ),
        PopupMenuItem(
          value: 'search-secondary',
          child: ListenMenuRow(
            icon: Icons.search_outlined,
            title: l.text('openSubtitles'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'import-embedded',
          child: ListenMenuRow(
            icon: Icons.closed_caption_outlined,
            title: l.text('importEmbeddedText'),
          ),
        ),
        PopupMenuItem(
          value: 'archive-media',
          child: ListenMenuRow(
            icon: Icons.archive_outlined,
            title: l.text('archiveMedia'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.subtitles_outlined,
              size: ListenIconSize.chrome,
              color: quiet,
            ),
            const SizedBox(width: ListenSpacing.gap2),
            // Kept so the control reads as something that opens a menu rather
            // than a plain action.
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
