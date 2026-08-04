import 'package:flutter/material.dart';

import '../../controllers/media_library_scan_controller.dart';
import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import 'media_library_section.dart';

/// The content home: what to listen to next, and nothing else. Navigation
/// to the standing learning destinations lives in the app sidebar alone —
/// this page used to carry a second rail with the same destinations, which
/// meant two navigations disagreeing about names, icons and grouping on one
/// screen.
class ListeningHome extends StatefulWidget {
  const ListeningHome({
    super.key,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onContinue,
    this.mediaLibrary,
    this.offlineEntries,
    this.familiarSupplyEnabled = true,
    this.scan,
    this.onScanRefresh,
    this.onScanCancel,
    this.onRetryScanRegistrations,
    this.onChooseMediaLibraryFolder,
    this.onOpenLibraryEntry,
    this.onStartExtensiveEntry,
    this.onStartIntensiveEntry,
    this.onSetLibraryIntent,
    this.onToggleFamiliarSupply,
    this.recentMediaTitle,
    this.recentMediaPath,
    this.recentPosition = Duration.zero,
    this.recentDuration = Duration.zero,
    this.recentSubtitleCount = 0,
    this.vocabularyCount = 0,
    this.vocabularyCapped = false,
    this.vocabularyKnown = false,
    this.listeningInboxCount = 0,
    this.coreStatusText = '',
  });

  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onContinue;
  final List<MediaLibraryEntry>? mediaLibrary;

  /// The offline subset of [mediaLibrary] (rows whose local file still
  /// exists). Offline used to be its own sidebar destination; it is a filter
  /// on the library now.
  final List<MediaLibraryEntry>? offlineEntries;
  final bool familiarSupplyEnabled;

  /// Folder-scan state, or null on a surface that has no scan wired. The scan
  /// is the only thing that can tell an empty library apart from a library
  /// nobody could read, so it renders even when [mediaLibrary] is unknown.
  final MediaLibraryScanState? scan;
  final VoidCallback? onScanRefresh;
  final VoidCallback? onScanCancel;
  final VoidCallback? onRetryScanRegistrations;
  final VoidCallback? onChooseMediaLibraryFolder;
  final void Function(MediaLibraryEntry entry)? onOpenLibraryEntry;
  final void Function(MediaLibraryEntry entry)? onStartExtensiveEntry;
  final void Function(MediaLibraryEntry entry)? onStartIntensiveEntry;
  final void Function(MediaLibraryEntry entry, String? intent)?
  onSetLibraryIntent;
  final void Function(bool enabled)? onToggleFamiliarSupply;
  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final int recentSubtitleCount;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;
  final String coreStatusText;

  @override
  State<ListeningHome> createState() => _ListeningHomeState();
}

class _ListeningHomeState extends State<ListeningHome> {
  var _offlineOnly = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < ListenBreakpoints.homeSidebar;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: _HomeContent(
          compact: compact,
          onOpenMedia: widget.onOpenMedia,
          onOpenOnline: widget.onOpenOnline,
          onContinue: widget.onContinue,
          offlineOnly: _offlineOnly,
          onOfflineOnlyChanged: (value) => setState(() => _offlineOnly = value),
          mediaLibrary: _offlineOnly
              ? widget.offlineEntries
              : widget.mediaLibrary,
          familiarSupplyEnabled: widget.familiarSupplyEnabled,
          scan: widget.scan,
          onScanRefresh: widget.onScanRefresh,
          onScanCancel: widget.onScanCancel,
          onRetryScanRegistrations: widget.onRetryScanRegistrations,
          onChooseMediaLibraryFolder: widget.onChooseMediaLibraryFolder,
          onOpenLibraryEntry: widget.onOpenLibraryEntry,
          onStartExtensiveEntry: widget.onStartExtensiveEntry,
          onStartIntensiveEntry: widget.onStartIntensiveEntry,
          onSetLibraryIntent: widget.onSetLibraryIntent,
          onToggleFamiliarSupply: widget.onToggleFamiliarSupply,
          recentMediaTitle: widget.recentMediaTitle,
          recentMediaPath: widget.recentMediaPath,
          recentPosition: widget.recentPosition,
          recentDuration: widget.recentDuration,
          recentSubtitleCount: widget.recentSubtitleCount,
          vocabularyCount: widget.vocabularyCount,
          vocabularyCapped: widget.vocabularyCapped,
          vocabularyKnown: widget.vocabularyKnown,
          listeningInboxCount: widget.listeningInboxCount,
          coreStatusText: widget.coreStatusText,
        ),
      );
    },
  );
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.compact,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onContinue,
    required this.offlineOnly,
    required this.onOfflineOnlyChanged,
    required this.mediaLibrary,
    required this.familiarSupplyEnabled,
    required this.scan,
    required this.onScanRefresh,
    required this.onScanCancel,
    required this.onRetryScanRegistrations,
    required this.onChooseMediaLibraryFolder,
    required this.onOpenLibraryEntry,
    required this.onStartExtensiveEntry,
    required this.onStartIntensiveEntry,
    required this.onSetLibraryIntent,
    required this.onToggleFamiliarSupply,
    required this.recentMediaTitle,
    required this.recentMediaPath,
    required this.recentPosition,
    required this.recentDuration,
    required this.recentSubtitleCount,
    required this.vocabularyCount,
    required this.vocabularyCapped,
    required this.vocabularyKnown,
    required this.listeningInboxCount,
    required this.coreStatusText,
  });

  final bool compact;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onContinue;

  /// The library's offline filter: offline used to be a sidebar destination
  /// sharing one data source with this section, so it reads as a view on the
  /// library now.
  final bool offlineOnly;
  final ValueChanged<bool> onOfflineOnlyChanged;
  final List<MediaLibraryEntry>? mediaLibrary;
  final bool familiarSupplyEnabled;
  final MediaLibraryScanState? scan;
  final VoidCallback? onScanRefresh;
  final VoidCallback? onScanCancel;
  final VoidCallback? onRetryScanRegistrations;
  final VoidCallback? onChooseMediaLibraryFolder;
  final void Function(MediaLibraryEntry entry)? onOpenLibraryEntry;
  final void Function(MediaLibraryEntry entry)? onStartExtensiveEntry;
  final void Function(MediaLibraryEntry entry)? onStartIntensiveEntry;
  final void Function(MediaLibraryEntry entry, String? intent)?
  onSetLibraryIntent;
  final void Function(bool enabled)? onToggleFamiliarSupply;
  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final int recentSubtitleCount;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;
  final String coreStatusText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      // One page role per window width, instead of four different numbers in
      // four directions (24|48 / 28|44 / 24|48 / 40, three of them off any
      // ladder). This is the inset the coach dashboard and the vocabulary
      // detail already use, so the home page finally measures its margin the
      // same way the rest of the app does.
      padding: compact ? ListenPadding.pageCompact : ListenPadding.page,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Wide content that carries media, not a reading measure: the cap
          // only stops the layout sprawling once the window is much wider than
          // the content needs.
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // The page title is the one hero size. `headlineMedium` is
                // 28px w400 — a geometry the ladder never chose — and this was
                // the largest of the sixteen sites that had picked one up.
                l.text('contentHome'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                l.text('currentContentJourney'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              _ContinueLearningCard(
                mediaTitle: recentMediaTitle,
                mediaPath: recentMediaPath,
                position: recentPosition,
                duration: recentDuration,
                onContinue: onContinue,
                onOpenMedia: onOpenMedia,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              _ResourceStatusStrip(
                recentSubtitleCount: recentSubtitleCount,
                hasRecentMedia: (recentMediaPath ?? '').isNotEmpty,
                vocabularyCount: vocabularyCount,
                vocabularyCapped: vocabularyCapped,
                vocabularyKnown: vocabularyKnown,
                listeningInboxCount: listeningInboxCount,
                coreStatusText: coreStatusText,
              ),
              const SizedBox(height: ListenSpacing.gap32),
              Text(
                l.text('addContentSource'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              _ResponsiveActionGrid(
                compact: compact,
                children: [
                  _SourceAction(
                    icon: Icons.folder_open_outlined,
                    label: l.text('openVideoAudio'),
                    sourceLabel: l.text('localSource'),
                    onTap: onOpenMedia,
                    primary: true,
                  ),
                  _SourceAction(
                    icon: Icons.link_outlined,
                    label: l.text('openUrl'),
                    sourceLabel: l.text('onlineSource'),
                    onTap: onOpenOnline,
                  ),
                ],
              ),
              if (scan != null &&
                  onScanRefresh != null &&
                  onScanCancel != null &&
                  onRetryScanRegistrations != null &&
                  onChooseMediaLibraryFolder != null) ...[
                const SizedBox(height: ListenSpacing.gap32),
                MediaLibraryScanCard(
                  state: scan!,
                  onRefresh: onScanRefresh!,
                  onCancel: onScanCancel!,
                  onRetryFailures: onRetryScanRegistrations!,
                  onChooseFolder: onChooseMediaLibraryFolder!,
                ),
              ],
              if (mediaLibrary != null &&
                  onOpenLibraryEntry != null &&
                  onStartExtensiveEntry != null &&
                  onStartIntensiveEntry != null &&
                  onSetLibraryIntent != null &&
                  onToggleFamiliarSupply != null) ...[
                SizedBox(
                  height: scan == null
                      ? ListenSpacing.gap32
                      : ListenSpacing.gap12,
                ),
                FilterChip(
                  // Offline used to occupy its own sidebar slot with the same
                  // data source; as a filter it stays one view on the library.
                  label: Text(l.text('sidebarOfflineDownloads')),
                  selected: offlineOnly,
                  onSelected: onOfflineOnlyChanged,
                ),
                const SizedBox(height: ListenSpacing.gap12),
                MediaLibrarySection(
                  entries: mediaLibrary,
                  familiarSupplyEnabled: familiarSupplyEnabled,
                  sidecarSubtitlePaths:
                      scan?.sidecarSubtitlePaths ?? const <String>{},
                  onOpen: onOpenLibraryEntry!,
                  onStartExtensive: onStartExtensiveEntry!,
                  onStartIntensive: onStartIntensiveEntry!,
                  onSetIntent: onSetLibraryIntent!,
                  onToggleFamiliarSupply: onToggleFamiliarSupply!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveActionGrid extends StatelessWidget {
  const _ResponsiveActionGrid({required this.compact, required this.children});

  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: ListenSpacing.gap8),
          ],
        ],
      );
    }
    final perRow = children.length;
    final rows = <List<Widget?>>[];
    for (var start = 0; start < children.length; start += perRow) {
      final row = <Widget?>[
        ...children.sublist(
          start,
          (start + perRow) > children.length ? children.length : start + perRow,
        ),
      ];
      while (row.length < perRow) {
        row.add(null);
      }
      rows.add(row);
    }
    return Column(
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < rows[rowIndex].length; index++) ...[
                Expanded(child: rows[rowIndex][index] ?? const SizedBox()),
                if (index != rows[rowIndex].length - 1)
                  const SizedBox(width: ListenSpacing.gap12),
              ],
            ],
          ),
          if (rowIndex != rows.length - 1)
            const SizedBox(height: ListenSpacing.gap12),
        ],
      ],
    );
  }
}

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard({
    required this.mediaTitle,
    required this.mediaPath,
    required this.position,
    required this.duration,
    required this.onContinue,
    required this.onOpenMedia,
  });

  final String? mediaTitle;
  final String? mediaPath;
  final Duration position;
  final Duration duration;
  final VoidCallback onContinue;
  final VoidCallback onOpenMedia;

  bool get _hasMedia => (mediaTitle ?? mediaPath ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final title = _hasMedia
        ? mediaTitle ?? mediaPath!.split('/').last
        : l.text('noRecentMedia');
    final progress = duration.inMilliseconds <= 0
        ? l.text('openMediaToContinue')
        : '${formatDuration(position)} / ${formatDuration(duration)}';
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.primary.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _hasMedia ? onContinue : onOpenMedia,
        child: Padding(
          padding: ListenPadding.card,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: ListenRadii.controlBorder,
                ),
                child: Icon(
                  _hasMedia
                      ? Icons.play_circle_outline
                      : Icons.folder_open_outlined,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: ListenSpacing.gap16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text('continueLearning'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      progress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ListenSpacing.gap12),
              FilledButton.icon(
                onPressed: _hasMedia ? onContinue : onOpenMedia,
                icon: Icon(_hasMedia ? Icons.play_arrow : Icons.add),
                label: Text(
                  _hasMedia ? l.text('continuePlayback') : l.text('openMedia'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceStatusStrip extends StatelessWidget {
  const _ResourceStatusStrip({
    required this.recentSubtitleCount,
    required this.hasRecentMedia,
    required this.vocabularyCount,
    required this.vocabularyCapped,
    required this.vocabularyKnown,
    required this.listeningInboxCount,
    required this.coreStatusText,
  });

  final int recentSubtitleCount;
  final bool hasRecentMedia;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;

  /// Health line for the "local core" tile. Empty means "nothing to report",
  /// which the tile renders as its ready state. The composition root filters
  /// playback notices out (see `PlayerController.statusIsPlayback`) rather
  /// than matching on the localized text here.
  final String coreStatusText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < ListenBreakpoints.homeStatusStrip;
        final items = [
          _StatusItem(
            icon: Icons.subtitles_outlined,
            label: l.text('subtitleReadiness'),
            value: !hasRecentMedia
                ? '—'
                : recentSubtitleCount == 0
                ? l.text('notReadyYet')
                : '$recentSubtitleCount',
          ),
          _StatusItem(
            icon: Icons.menu_book_outlined,
            label: l.text('savedWords'),
            value: !vocabularyKnown
                ? '—'
                : vocabularyCapped
                ? '$vocabularyCount+'
                : '$vocabularyCount',
          ),
          _StatusItem(
            icon: Icons.inbox_outlined,
            label: l.text('listeningInbox'),
            value: '$listeningInboxCount',
          ),
          _StatusItem(
            icon: Icons.memory_outlined,
            label: l.text('localCore'),
            value: coreStatusText.isEmpty
                ? l.text('coreReady')
                : coreStatusText,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _StatusTile(item: items[index]),
                if (index != items.length - 1)
                  const SizedBox(height: ListenSpacing.gap8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(child: _StatusTile(item: items[index])),
              if (index != items.length - 1)
                const SizedBox(width: ListenSpacing.gap8),
            ],
          ],
        );
      },
    );
  }
}

class _StatusItem {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.item});

  final _StatusItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: ListenRadii.controlBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Row(
          children: [
            Icon(
              item.icon,
              size: ListenIconSize.control,
              color: colors.primary,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Flexible(
              child: Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.icon,
    required this.label,
    required this.sourceLabel,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String sourceLabel;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: primary
          ? colors.primaryContainer.withValues(alpha: 0.42)
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(
          color: primary
              ? colors.primary.withValues(alpha: 0.42)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 112,
          child: Padding(
            padding: ListenPadding.card,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary ? colors.primary : colors.secondaryContainer,
                    borderRadius: ListenRadii.controlBorder,
                  ),
                  child: Icon(
                    icon,
                    color: primary
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: ListenSpacing.gap4),
                      Text(
                        sourceLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
