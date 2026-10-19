import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../settings.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

/// Which set of sentences a [ManagedStoreSettings] speaks.
///
/// The app has two storage locations with the same three states and two
/// genuinely different meanings — the managed store holds what was kept, the
/// downloads folder holds what was merely acquired. One widget, two vocabularies:
/// sharing the *shape* is right, sharing the *words* would tell the learner
/// the two folders do the same job.
typedef StorageLocationCopy = ({
  String description,
  String defaultLabel,
  String missing,
  String choose,
  String change,
  String clear,
  String accessHint,
});

const managedStoreCopy = (
  description: 'managedStoreDescription',
  defaultLabel: 'managedStoreDefault',
  missing: 'managedStoreMissing',
  choose: 'managedStoreChoose',
  change: 'managedStoreChange',
  clear: 'managedStoreClear',
  accessHint: 'managedStoreAccessHint',
);

const downloadsLocationCopy = (
  description: 'downloadsLocationDescription',
  defaultLabel: 'downloadsLocationDefault',
  missing: 'downloadsLocationMissing',
  choose: 'managedStoreChoose',
  change: 'managedStoreChange',
  clear: 'managedStoreClear',
  accessHint: 'managedStoreAccessHint',
);

/// A storage location setting: the managed asset store, or the downloads
/// folder.
///
/// The three states are drawn as three different sentences on purpose. No
/// custom location is the app-managed *default* — a real folder the app owns
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
    this.copy = managedStoreCopy,
  });

  final ManagedStoreLocation location;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  /// Which location this instance is talking about.
  final StorageLocationCopy copy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final missing = location.state == StorageLocationState.missing;
    final isDefault = location.state == StorageLocationState.appManaged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.text(copy.description), style: text.bodyMedium),
        const SizedBox(height: ListenSpacing.gap8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (location.state) {
                StorageLocationState.appManaged => Icons.folder_special_outlined,
                StorageLocationState.ready => Icons.folder_outlined,
                StorageLocationState.missing => Icons.warning_amber_outlined,
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
                    isDefault ? l.text(copy.defaultLabel) : location.path,
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
                      l.text(copy.missing),
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
                isDefault ? l.text(copy.choose) : l.text(copy.change),
              ),
            ),
            if (!isDefault)
              TextButton(
                onPressed: onClear,
                child: Text(l.text(copy.clear)),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(
          l.text(copy.accessHint),
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
