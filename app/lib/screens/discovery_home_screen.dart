import 'package:flutter/material.dart';

import '../controllers/discovery_view_model.dart';
import '../localization.dart';
import '../models/discovery.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_empty_state.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';
import '../widgets/discovery/content_card.dart';
import '../widgets/discovery/detail_panel.dart';
import '../widgets/discovery/source_display_name.dart';

/// The media-aggregation landing page: a sticky channel switcher on top, media
/// cards below, and the action details panel on the right.
class DiscoveryHome extends StatelessWidget {
  const DiscoveryHome({
    super.key,
    required this.viewModel,
    required this.onOpenMedia,
    this.onPlayMedia,
  });

  final DiscoveryViewModel viewModel;

  /// The app's generic "open a file from disk" action. It cannot open a
  /// *selected* entry, so it only appears where that is what is being offered.
  final VoidCallback onOpenMedia;

  final ValueChanged<String>? onPlayMedia;

  /// The player affordance exists only when a local file backs the entry.
  /// Falling back to [onOpenMedia] would put a file picker behind a button
  /// labelled "open for learning".
  VoidCallback? _openPlayerAction(String entryId, {VoidCallback? before}) {
    final localPath = viewModel.localPathFor(entryId);
    final play = onPlayMedia;
    if (localPath == null || play == null) return null;
    return () {
      before?.call();
      play(localPath);
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final state = viewModel.state;
        return LayoutBuilder(
          builder: (context, constraints) {
            final showDetail =
                constraints.maxWidth >= ListenBreakpoints.discoveryDetail;
            final shelf = _DiscoveryShelf(
              state: state,
              durationMsFor: viewModel.durationMsFor,
              onSelectItem: (id) {
                viewModel.selectItem(id);
                if (!showDetail) {
                  final entry = state.entryById(id);
                  if (entry != null) {
                    _showDetailBottomSheet(context, entry);
                  }
                }
              },
              onDownload: viewModel.startDownload,
              onCancelDownload: viewModel.cancelDownload,
              onImport: viewModel.importCustomUrl,
              onSelectSource: viewModel.selectChannel,
              onRetrySources: viewModel.load,
              onRetryEntries: viewModel.retryEntries,
              onOpenMedia: onOpenMedia,
              isGrid: constraints.maxWidth >= ListenBreakpoints.discoveryGrid,
            );

            final content = <Widget>[
              Expanded(child: shelf),
              if (showDetail && state.selectedEntry != null)
                SizedBox(
                  width: 372,
                  child: DiscoveryDetailPanel(
                    entry: state.selectedEntry!,
                    source: state.selectedSource!,
                    durationMs: viewModel.durationMsFor(
                      state.selectedEntry!.id,
                    ),
                    downloadState: state.downloadStateOf(
                      state.selectedEntry!.id,
                    ),
                    downloadProgress: state.downloadProgressOf(
                      state.selectedEntry!.id,
                    ),
                    downloadFailure: state.downloadFailureOf(
                      state.selectedEntry!.id,
                    ),
                    packageStatus: state.packageStatusOf(
                      state.selectedEntry!.id,
                    ),
                    generationStatus: state.generationStatusOf(
                      state.selectedEntry!.id,
                    ),
                    generatorPhase: state.generatorPhaseOf(
                      state.selectedEntry!.id,
                    ),
                    generationFailure: state.generationFailureOf(
                      state.selectedEntry!.id,
                    ),
                    onDownload: () =>
                        viewModel.startDownload(state.selectedEntry!.id),
                    onCancelDownload: () =>
                        viewModel.cancelDownload(state.selectedEntry!.id),
                    onOpenPlayer: _openPlayerAction(state.selectedEntry!.id),
                    onViewPackage: () => _showPackageDialog(context),
                    onGenerate: () =>
                        viewModel.startGeneration(state.selectedEntry!.id),
                    onCancelGenerate: () =>
                        viewModel.cancelGeneration(state.selectedEntry!.id),
                    onRecheckPackage: () =>
                        viewModel.checkPackage(state.selectedEntry!.id),
                  ),
                ),
            ];

            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Row(children: content),
            );
          },
        );
      },
    );
  }

  void _showDetailBottomSheet(BuildContext context, MediaEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final scheme = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (scrollContext, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: ListenRadii.panel,
                ),
              ),
              child: ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) {
                  final state = viewModel.state;
                  final currentEntry = state.selectedEntry;
                  if (currentEntry == null) return const SizedBox.shrink();
                  final currentSource = state.selectedSource;
                  if (currentSource == null) return const SizedBox.shrink();

                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: DiscoveryDetailPanel(
                          entry: currentEntry,
                          source: currentSource,
                          durationMs: viewModel.durationMsFor(currentEntry.id),
                          downloadState: state.downloadStateOf(currentEntry.id),
                          downloadProgress: state.downloadProgressOf(
                            currentEntry.id,
                          ),
                          packageStatus: state.packageStatusOf(currentEntry.id),
                          generationStatus: state.generationStatusOf(
                            currentEntry.id,
                          ),
                          generatorPhase: state.generatorPhaseOf(
                            currentEntry.id,
                          ),
                          generationFailure: state.generationFailureOf(
                            currentEntry.id,
                          ),
                          onDownload: () =>
                              viewModel.startDownload(currentEntry.id),
                          onCancelDownload: () =>
                              viewModel.cancelDownload(currentEntry.id),
                          onOpenPlayer: _openPlayerAction(
                            currentEntry.id,
                            before: Navigator.of(bottomSheetContext).pop,
                          ),
                          onViewPackage: () => _showPackageDialog(context),
                          onGenerate: () =>
                              viewModel.startGeneration(currentEntry.id),
                          onCancelGenerate: () =>
                              viewModel.cancelGeneration(currentEntry.id),
                          onRecheckPackage: () =>
                              viewModel.checkPackage(currentEntry.id),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: ListenRadii.tightBorder,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showPackageDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('discoveryPackageTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('discoveryPackageNote'),
              style: Theme.of(
                dialogContext,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: ListenSpacing.gap12),
            for (final entry in const [
              ('discoveryPackageSubtitle', Icons.subtitles_outlined),
              ('discoveryPackageTimeline', Icons.timeline_outlined),
              ('discoveryPackagePhonetics', Icons.record_voice_over_outlined),
            ]) ...[
              Row(
                children: [
                  Icon(
                    entry.$2,
                    size: ListenIconSize.inline,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: ListenSpacing.gap8),
                  Text(
                    l.text(entry.$1),
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap6),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.text('discoveryClose')),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryChannelChips extends StatelessWidget {
  const _DiscoveryChannelChips({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelectSource,
  });

  final List<MediaSource> sources;
  final String? selectedSourceId;
  final void Function(String) onSelectSource;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 24,
                right: ListenSpacing.gap12,
              ),
              child: Text(
                l.text('discoverySources'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final source in sources)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: ListenSpacing.gap6,
                        ),
                        child: ChoiceChip(
                          label: Text(sourceDisplayName(l, source)),
                          selected: source.id == selectedSourceId,
                          onSelected: (_) => onSelectSource(source.id),
                          selectedColor: scheme.primaryContainer,
                          labelStyle: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pins the source switcher to the top of the shelf so switching channels
/// stays available while the media grid scrolls.
class _SourceSwitcherHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SourceSwitcherHeaderDelegate({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelectSource,
  });

  final List<MediaSource> sources;
  final String? selectedSourceId;
  final void Function(String) onSelectSource;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => _DiscoveryChannelChips(
    sources: sources,
    selectedSourceId: selectedSourceId,
    onSelectSource: onSelectSource,
  );

  @override
  bool shouldRebuild(_SourceSwitcherHeaderDelegate oldDelegate) =>
      oldDelegate.sources != sources ||
      oldDelegate.selectedSourceId != selectedSourceId ||
      oldDelegate.onSelectSource != onSelectSource;
}

class _DiscoveryShelf extends StatelessWidget {
  const _DiscoveryShelf({
    required this.state,
    required this.durationMsFor,
    required this.onSelectItem,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onImport,
    required this.onSelectSource,
    required this.onRetrySources,
    required this.onRetryEntries,
    required this.onOpenMedia,
    required this.isGrid,
  });

  final DiscoveryState state;
  final int? Function(String entryId) durationMsFor;
  final void Function(String) onSelectItem;
  final void Function(String) onDownload;
  final void Function(String) onCancelDownload;
  final ValueChanged<String> onImport;
  final void Function(String) onSelectSource;
  final VoidCallback onRetrySources;
  final VoidCallback onRetryEntries;
  final VoidCallback onOpenMedia;
  final bool isGrid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final source = state.selectedSource;
    final isCustomSource = source?.id == DiscoveryViewModel.customSource.id;

    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _SourceSwitcherHeaderDelegate(
              sources: state.sources,
              selectedSourceId: state.selectedSourceId,
              onSelectSource: onSelectSource,
            ),
          ),
          if (source != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  ListenSpacing.gap16,
                  24,
                  ListenSpacing.gap12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sourceDisplayName(l, source),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      source.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    // While the feed is in flight there is no count to state:
                    // the previous channel's total is not this one's.
                    if (!state.entriesLoading &&
                        state.entriesFailure == null) ...[
                      const SizedBox(height: ListenSpacing.gap8),
                      Text(
                        l
                            .text('discoveryVideoCount')
                            .replaceFirst('{count}', '${state.entries.length}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (isCustomSource) ...[
                      const SizedBox(height: ListenSpacing.gap12),
                      _LinkImportBar(
                        resolvingUrl: state.resolvingUrl,
                        onImport: onImport,
                      ),
                      if (state.resolveFailed) ...[
                        const SizedBox(height: ListenSpacing.gap6),
                        Text(
                          l.text('discoveryResolveFailed'),
                          style: TextStyle(
                            color: scheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          // The five shelf states, each answering a different question:
          // the catalog broke, something is in flight, this feed broke, the
          // channel is genuinely empty, or here are the videos.
          if (state.sourcesFailure != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ListenSpacing.gap32,
                ),
                child: ListenErrorState(
                  message: l.text('discoverySourcesFailed'),
                  action: OutlinedButton(
                    onPressed: onRetrySources,
                    child: Text(l.text('retry')),
                  ),
                ),
              ),
            )
          else if (state.loading || state.entriesLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: ListenSpacing.gap32),
                child: Center(child: ListenLoading()),
              ),
            )
          else if (state.entriesFailure != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ListenSpacing.gap32,
                ),
                child: ListenErrorState(
                  message: l.text('discoveryChannelFailed'),
                  action: OutlinedButton(
                    onPressed: onRetryEntries,
                    child: Text(l.text('retry')),
                  ),
                ),
              ),
            )
          else if (state.entries.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ListenSpacing.gap32,
                ),
                child: isCustomSource
                    ? ListenEmptyState(
                        icon: Icons.link_off,
                        message: l.text('discoveryEmptyImports'),
                        // The one place the generic file picker belongs: here
                        // it is offered as itself, not as a lesson's player.
                        action: OutlinedButton(
                          onPressed: onOpenMedia,
                          child: Text(l.text('openMedia')),
                        ),
                      )
                    : ListenEmptyState(
                        icon: Icons.video_library_outlined,
                        message: l.text('discoveryEmptyChannel'),
                      ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              sliver: isGrid
                  ? SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 360,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = state.entries[index];
                        return DiscoveryContentCard(
                          entry: entry,
                          source: state.sourceById(entry.sourceId) ?? source!,
                          durationMs: durationMsFor(entry.id),
                          downloadState: state.downloadStateOf(entry.id),
                          downloadProgress: state.downloadProgressOf(entry.id),
                          packageStatus: state.packageStatusOf(entry.id),
                          selected: entry.id == state.selectedEntryId,
                          onTap: () => onSelectItem(entry.id),
                          onDownload: () => onDownload(entry.id),
                          onCancel: () => onCancelDownload(entry.id),
                          axis: Axis.vertical,
                        );
                      }, childCount: state.entries.length),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = state.entries[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: DiscoveryContentCard(
                            entry: entry,
                            source: state.sourceById(entry.sourceId) ?? source!,
                            durationMs: durationMsFor(entry.id),
                            downloadState: state.downloadStateOf(entry.id),
                            downloadProgress: state.downloadProgressOf(
                              entry.id,
                            ),
                            packageStatus: state.packageStatusOf(entry.id),
                            selected: entry.id == state.selectedEntryId,
                            onTap: () => onSelectItem(entry.id),
                            onDownload: () => onDownload(entry.id),
                            onCancel: () => onCancelDownload(entry.id),
                            axis: Axis.horizontal,
                          ),
                        );
                      }, childCount: state.entries.length),
                    ),
            ),
        ],
      ),
    );
  }
}

class _LinkImportBar extends StatefulWidget {
  const _LinkImportBar({required this.resolvingUrl, required this.onImport});

  final bool resolvingUrl;
  final ValueChanged<String> onImport;

  @override
  State<_LinkImportBar> createState() => _LinkImportBarState();
}

class _LinkImportBarState extends State<_LinkImportBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      enabled: !widget.resolvingUrl,
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) {
          widget.onImport(value.trim());
          _controller.clear();
        }
      },
      decoration: InputDecoration(
        hintText: l.text('discoveryInputPlaceholder'),
        prefixIcon: widget.resolvingUrl
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: ListenLoading.inline(size: 16),
              )
            : const Icon(Icons.link, size: ListenIconSize.control),
        suffixIcon: widget.resolvingUrl
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) {
                    widget.onImport(text);
                    _controller.clear();
                  }
                },
              ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: ListenRadii.controlBorder),
      ),
    );
  }
}
