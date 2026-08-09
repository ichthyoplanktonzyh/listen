import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../settings.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

/// The managed asset store location setting: where kept material is copied and
/// where "my media" reads from.
///
/// The three states are drawn as three different sentences on purpose. No
/// custom location is the app-managed *default* — a real store the app owns
/// under Application Support — never "you have no store". A custom location
/// that is set but gone off disk is not the default either: telling the user
/// they never chose one would send them to re-pick instead of to remount the
/// drive.
class ManagedStoreSettings extends StatelessWidget {
  const ManagedStoreSettings({
    super.key,
    required this.location,
    required this.onChoose,
    required this.onClear,
  });

  final ManagedStoreLocation location;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final missing = location.state == ManagedStoreState.missing;
    final isDefault = location.state == ManagedStoreState.appManaged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.text('managedStoreDescription'), style: text.bodyMedium),
        const SizedBox(height: ListenSpacing.gap8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (location.state) {
                ManagedStoreState.appManaged => Icons.folder_special_outlined,
                ManagedStoreState.ready => Icons.folder_outlined,
                ManagedStoreState.missing => Icons.warning_amber_outlined,
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
                    isDefault ? l.text('managedStoreDefault') : location.path,
                    style: text.bodyMedium?.copyWith(
                      color: missing ? colors.error : colors.onSurface,
                    ),
                  ),
                  if (isDefault) ...[
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      location.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (missing) ...[
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      l.text('managedStoreMissing'),
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
                isDefault
                    ? l.text('managedStoreChoose')
                    : l.text('managedStoreChange'),
              ),
            ),
            if (!isDefault)
              TextButton(
                onPressed: onClear,
                child: Text(l.text('managedStoreClear')),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(
          l.text('managedStoreAccessHint'),
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
