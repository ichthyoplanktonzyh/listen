import 'package:flutter/material.dart';

import '../../controllers/media_library_scan_controller.dart';
import '../../localization.dart';
import '../../models/learning_material.dart';
import '../../models/personal_library.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_loading.dart';
import '../panels/content_fit_card.dart';

/// Home Personal Library for retained audio/video materials.
///
/// Manual triage intent stays attached to each media row. It never reorders or
/// recommends materials automatically.
///
/// Every row has exactly one primary action: Open. Which projection of the
/// material lands on is the workbench's business, not a question the library
/// asks first.
class PersonalLibrarySection extends StatelessWidget {
  const PersonalLibrarySection({
    super.key,
    required this.entries,
    this.sidecarSubtitlePaths = const <String>{},
    required this.onOpen,
    required this.onStartExtensive,
    required this.onStartIntensive,
    required this.onSetIntent,
    this.showHeader = true,
    this.simplifiedRows = false,
  });

  /// Null while the first load is in flight; empty when the library is empty.
  final List<PersonalLibraryEntry>? entries;

  /// Library paths the last folder scan saw next to a subtitle file. Reported
  /// as a fact about the folder — pairing them into a learnable resource is a
  /// separate step, so no row promises anything because of it.
  final Set<String> sidecarSubtitlePaths;

  /// Activates the material's workbench session. The library's single
  /// primary action: it states no opinion about which projection of the
  /// material the learner wanted.
  final void Function(PersonalLibraryEntry entry) onOpen;
  final void Function(PersonalLibraryEntry entry) onStartExtensive;
  final void Function(PersonalLibraryEntry entry) onStartIntensive;
  final void Function(PersonalLibraryEntry entry, String? intent) onSetIntent;
  final bool showHeader;
  final bool simplifiedRows;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loaded = entries;
    if (loaded == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l.text('personalLibrary'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        if (loaded.isEmpty)
          Text(
            l.text('personalLibraryEmpty'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else if (simplifiedRows)
          for (final entry in loaded) ...[
            _UnifiedLibraryRow(
              entry: entry,
              hasSidecarSubtitle:
                  entry.primaryMedia != null &&
                  sidecarSubtitlePaths.contains(entry.primaryMedia!.media.path),
              onOpen: () => onOpen(entry),
              onStartExtensive: () => onStartExtensive(entry),
              onStartIntensive: () => onStartIntensive(entry),
              onSetIntent: (intent) => onSetIntent(entry, intent),
            ),
            const SizedBox(height: ListenSpacing.gap8),
          ]
        else
          for (final entry in loaded) ...[
            _LibraryRow(
              entry: entry,
              hasSidecarSubtitle:
                  entry.primaryMedia != null &&
                  sidecarSubtitlePaths.contains(entry.primaryMedia!.media.path),
              onOpen: () => onOpen(entry),
              onStartExtensive: () => onStartExtensive(entry),
              onStartIntensive: () => onStartIntensive(entry),
              onSetIntent: (intent) => onSetIntent(entry, intent),
            ),
            const SizedBox(height: ListenSpacing.gap6),
          ],
      ],
    );
  }
}

class _UnifiedLibraryRow extends StatelessWidget {
  const _UnifiedLibraryRow({
    required this.entry,
    required this.hasSidecarSubtitle,
    required this.onOpen,
    required this.onStartExtensive,
    required this.onStartIntensive,
    required this.onSetIntent,
  });

  final PersonalLibraryEntry entry;
  final bool hasSidecarSubtitle;
  final VoidCallback onOpen;
  final VoidCallback onStartExtensive;
  final VoidCallback onStartIntensive;
  final ValueChanged<String?> onSetIntent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final fit = entry.primaryMedia?.fit;
    final (icon, typeLabel) = entry.shape == MaterialShape.mixed
        ? (Icons.layers_outlined, l.text('libraryTypeMixed'))
        : entry.canWatch
        ? (Icons.movie_outlined, l.text('libraryTypeVideo'))
        : entry.canListen
        ? (Icons.audiotrack_outlined, l.text('libraryTypeAudio'))
        : (Icons.movie_outlined, l.text('libraryTypeVideo'));

    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ListenSpacing.gap12,
            ListenSpacing.gap8,
            ListenSpacing.gap6,
            ListenSpacing.gap8,
          ),
          child: Row(
            children: [
              Icon(icon, size: ListenIconSize.control),
              const SizedBox(width: ListenSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Wrap(
                      spacing: ListenSpacing.gap6,
                      runSpacing: ListenSpacing.gap4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          typeLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        if (fit != null)
                          FitChip(
                            label: l.text('contentFitMeaning'),
                            fit: fit.meaning.fit,
                          ),
                        if (fit != null)
                          FitChip(
                            label: l.text('contentFitSound'),
                            fit: fit.sound.fit,
                          ),
                        if (hasSidecarSubtitle)
                          _Badge(
                            icon: Icons.subtitles_outlined,
                            label: l.text('sidecarSubtitleBadge'),
                            color: colors.secondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onOpen,
                child: Text(l.text('libraryContinueLearning')),
              ),
              if (entry.canListenOrWatch)
                PopupMenuButton<String>(
                  tooltip: l.text('moreActions'),
                  icon: const Icon(
                    Icons.more_vert,
                    size: ListenIconSize.control,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'extensive':
                        onStartExtensive();
                      case 'intensive':
                        onStartIntensive();
                      case 'pin_extensive':
                      case 'pin_intensive':
                      case 'defer':
                        onSetIntent(value);
                      case 'clear':
                        onSetIntent(null);
                    }
                  },
                  itemBuilder: (context) => [
                    if (entry.canListenOrWatch) ...[
                      PopupMenuItem(
                        value: 'extensive',
                        child: Text(l.text('startExtensiveAction')),
                      ),
                      PopupMenuItem(
                        value: 'intensive',
                        child: Text(l.text('startIntensiveAction')),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'pin_extensive',
                        child: Text(l.text('pinExtensiveAction')),
                      ),
                      PopupMenuItem(
                        value: 'pin_intensive',
                        child: Text(l.text('pinIntensiveAction')),
                      ),
                      PopupMenuItem(
                        value: 'defer',
                        child: Text(l.text('deferMediaAction')),
                      ),
                      if (entry.triageIntent != null)
                        PopupMenuItem(
                          value: 'clear',
                          child: Text(l.text('clearTriageAction')),
                        ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.entry,
    required this.hasSidecarSubtitle,
    required this.onOpen,
    required this.onStartExtensive,
    required this.onStartIntensive,
    required this.onSetIntent,
  });

  final PersonalLibraryEntry entry;
  final bool hasSidecarSubtitle;

  /// Activates this material's workbench session. One action for every shape
  /// of material — text, media, mixed, and generated-edition alike.
  final VoidCallback onOpen;
  final VoidCallback onStartExtensive;
  final VoidCallback onStartIntensive;
  final void Function(String? intent) onSetIntent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final primaryMedia = entry.primaryMedia;
    final duration = primaryMedia?.media.durationMs;
    final fit = primaryMedia?.fit;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Every row taps into the same workbench session. The row used to
        // refuse the tap on a mixed material because it could not guess
        // between Read and Listen — but the workbench does not need that
        // guess: it mounts whatever the material can actually do.
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                primaryMedia?.media.kind == 'audio'
                    ? Icons.audiotrack_outlined
                    : Icons.movie_outlined,
                size: ListenIconSize.control,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (duration != null && duration > 0)
                          Text(
                            formatDuration(Duration(milliseconds: duration)),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        if (fit != null)
                          FitChip(
                            label: l.text('contentFitMeaning'),
                            fit: fit.meaning.fit,
                          ),
                        if (fit != null)
                          FitChip(
                            label: l.text('contentFitSound'),
                            fit: fit.sound.fit,
                          ),
                        if (hasSidecarSubtitle)
                          // States what the folder holds, nothing more: the
                          // subtitle file is not imported yet, so this must
                          // not read as "ready to learn".
                          _Badge(
                            icon: Icons.subtitles_outlined,
                            label: l.text('sidecarSubtitleBadge'),
                            color: colors.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ListenSpacing.gap6),
              // One primary action. The row used to offer Read, Open media and
              // "open the generated result" side by side, which made the
              // learner decide up front which projection of a material they
              // wanted — a decision the workbench is better placed to make,
              // and the reason several different routes existed at all. The
              // study modes stay as secondary shortcuts, and they open the
              // same session before starting.
              Wrap(
                spacing: ListenSpacing.gap6,
                runSpacing: ListenSpacing.gap4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    key: const Key('library-open'),
                    onPressed: onOpen,
                    child: Text(l.text('libraryOpenAction')),
                  ),
                  if (entry.canListenOrWatch) ...[
                    TextButton(
                      onPressed: onStartExtensive,
                      child: Text(l.text('startExtensiveAction')),
                    ),
                    TextButton(
                      onPressed: onStartIntensive,
                      child: Text(l.text('startIntensiveAction')),
                    ),
                    PopupMenuButton<String>(
                      tooltip: l.text('moreActions'),
                      icon: Icon(
                        Icons.more_vert,
                        size: ListenIconSize.control,
                        color: colors.onSurfaceVariant,
                      ),
                      onSelected: (value) =>
                          onSetIntent(value == 'clear' ? null : value),
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem(
                          value: 'pin_extensive',
                          checked: entry.triageIntent == 'pin_extensive',
                          child: Text(l.text('pinExtensiveAction')),
                        ),
                        CheckedPopupMenuItem(
                          value: 'pin_intensive',
                          checked: entry.triageIntent == 'pin_intensive',
                          child: Text(l.text('pinIntensiveAction')),
                        ),
                        CheckedPopupMenuItem(
                          value: 'defer',
                          checked: entry.triageIntent == 'defer',
                          child: Text(l.text('deferMediaAction')),
                        ),
                        if (entry.triageIntent != null)
                          PopupMenuItem(
                            value: 'clear',
                            child: Text(l.text('clearTriageAction')),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact per-row rendition of the fit chips from the content fit card:
/// same band vocabulary (`fit_*` keys), smaller footprint. Bands only —
/// never raw densities (invariant 18).
/// The managed asset store scan as the "my media" surface shows it.
///
/// Every outcome gets its own sentence, because they ask for different things
/// from the user: a custom location gone off disk sends them to the drive, an
/// unreachable core says the contents are unknown — which is the one this
/// surface must never collapse into "you have no media". The default
/// app-managed store always scans like a ready folder.
class MediaLibraryScanCard extends StatelessWidget {
  const MediaLibraryScanCard({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onCancel,
    required this.onRetryFailures,
    required this.onChooseFolder,
  });

  final MediaLibraryScanState state;
  final VoidCallback onRefresh;
  final VoidCallback onCancel;
  final VoidCallback onRetryFailures;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final alarming =
        state.status == MediaLibraryScanStatus.folderMissing ||
        state.status == MediaLibraryScanStatus.failed;
    final message = switch (state.status) {
      MediaLibraryScanStatus.idle => l.text('mediaScanIdle'),
      MediaLibraryScanStatus.folderMissing => l.text('managedStoreMissing'),
      MediaLibraryScanStatus.coreUnavailable => l.text(
        'mediaScanCoreUnavailable',
      ),
      MediaLibraryScanStatus.scanning => l.text('mediaScanScanning'),
      MediaLibraryScanStatus.completed => l.text('mediaScanCompleted'),
      MediaLibraryScanStatus.cancelled => l.text('mediaScanCancelled'),
      MediaLibraryScanStatus.failed => l.text('mediaScanFailed'),
    };
    final failures = state.registrationFailures;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(
          color: alarming ? colors.error : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.isScanning)
                  const ListenLoading.inline(size: ListenIconSize.control)
                else
                  Icon(
                    switch (state.status) {
                      MediaLibraryScanStatus.folderMissing =>
                        Icons.warning_amber_outlined,
                      MediaLibraryScanStatus.coreUnavailable =>
                        Icons.cloud_off_outlined,
                      MediaLibraryScanStatus.completed =>
                        Icons.check_circle_outline,
                      MediaLibraryScanStatus.cancelled =>
                        Icons.pause_circle_outline,
                      MediaLibraryScanStatus.failed => Icons.error_outline,
                      _ => Icons.folder_outlined,
                    },
                    size: ListenIconSize.control,
                    color: alarming ? colors.error : colors.onSurfaceVariant,
                  ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: text.bodyMedium?.copyWith(
                          color: alarming ? colors.error : colors.onSurface,
                        ),
                      ),
                      if (state.folderPath.isNotEmpty) ...[
                        const SizedBox(height: ListenSpacing.gap2),
                        Text(
                          state.folderPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_showsCounts) ...[
                        const SizedBox(height: ListenSpacing.gap2),
                        Text(
                          l
                              .text('mediaScanCounts')
                              .replaceAll('{new}', '${state.registered}')
                              .replaceAll('{unchanged}', '${state.unchanged}')
                              .replaceAll('{skipped}', '${state.skipped}'),
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        // "300 added" read as "300 things joined my library",
                        // and then the library showed none of them: a scan
                        // registers with `retain: false`, which is exactly not
                        // Personal Library membership. The count now says what
                        // it counts, and the sentence says what it is not.
                        const SizedBox(height: ListenSpacing.gap4),
                        Text(
                          l.text('mediaScanRegistrationHint'),
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap12),
                _action(l),
              ],
            ),
            if (state.status == MediaLibraryScanStatus.failed &&
                ApiFailureDisclosure.hasDetail(state.failure))
              ApiFailureDisclosure(failure: state.failure!),
            if (failures.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap8),
              ApiFailureNotice(
                message: l
                    .text('mediaScanRegisterFailed')
                    .replaceAll('{count}', '${failures.length}'),
                failure: failures.first.failure,
              ),
              const SizedBox(height: ListenSpacing.gap4),
              for (final failure in failures.take(3))
                Text(
                  failure.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRetryFailures,
                  child: Text(l.text('mediaScanRetryFailed')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _showsCounts => switch (state.status) {
    MediaLibraryScanStatus.scanning ||
    MediaLibraryScanStatus.completed ||
    MediaLibraryScanStatus.cancelled => true,
    _ => false,
  };

  Widget _action(AppLocalizations l) => switch (state.status) {
    MediaLibraryScanStatus.folderMissing => OutlinedButton(
      onPressed: onChooseFolder,
      child: Text(l.text('managedStoreChange')),
    ),
    MediaLibraryScanStatus.scanning => TextButton(
      onPressed: onCancel,
      child: Text(l.text('mediaScanCancel')),
    ),
    _ => TextButton(
      onPressed: onRefresh,
      child: Text(l.text('mediaScanRefresh')),
    ),
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: ListenIconSize.inline, color: color),
      const SizedBox(width: ListenSpacing.gap2),
      // A badge is a label: on a narrow column it ellipsizes instead of
      // overflowing the row.
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
