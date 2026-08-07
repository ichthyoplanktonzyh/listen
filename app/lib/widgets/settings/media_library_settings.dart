import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../settings.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

/// The media library folder setting: where downloads land and where "my media"
/// reads from.
///
/// The three states are drawn as three different sentences on purpose. A folder
/// that is set but gone off disk is not an unset folder — telling the user they
/// never chose one would send them to re-pick instead of to remount the drive.
class MediaLibrarySettings extends StatelessWidget {
  const MediaLibrarySettings({
    super.key,
    required this.folder,
    required this.onChoose,
    required this.onClear,
  });

  final MediaLibraryFolder folder;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final missing = folder.state == MediaLibraryFolderState.missing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.text('mediaLibraryDescription'), style: text.bodyMedium),
        const SizedBox(height: ListenSpacing.gap8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (folder.state) {
                MediaLibraryFolderState.unset => Icons.folder_off_outlined,
                MediaLibraryFolderState.ready => Icons.folder_outlined,
                MediaLibraryFolderState.missing => Icons.warning_amber_outlined,
              },
              size: ListenIconSize.control,
              color: missing ? colors.error : colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.state == MediaLibraryFolderState.unset
                        ? l.text('mediaLibraryNotSet')
                        : folder.path,
                    style: text.bodyMedium?.copyWith(
                      color: missing ? colors.error : colors.onSurface,
                    ),
                  ),
                  if (missing) ...[
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      l.text('mediaLibraryMissing'),
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: ListenSpacing.gap8,
          runSpacing: ListenSpacing.gap6,
          children: [
            OutlinedButton.icon(
              onPressed: onChoose,
              icon: const Icon(
                Icons.folder_open_outlined,
                size: ListenIconSize.control,
              ),
              label: Text(
                folder.state == MediaLibraryFolderState.unset
                    ? l.text('mediaLibraryChoose')
                    : l.text('mediaLibraryChange'),
              ),
            ),
            if (folder.state != MediaLibraryFolderState.unset)
              TextButton(
                onPressed: onClear,
                child: Text(l.text('mediaLibraryClear')),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(
          l.text('mediaLibraryAccessHint'),
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
