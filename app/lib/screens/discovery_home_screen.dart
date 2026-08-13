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

  /// The single "start learning" intent: acquires local media when needed
  /// (progress stays on this surface), then hands the path to the workbench
  /// opener. Returns without opening on failure or cancel — the discovery
  /// state carries the typed failure for a retry instead.
  Future<void> _startLearning(
    String entryId, {
    VoidCallback? beforeOpen,
  }) async {
    final play = onPlayMedia;
    if (play == null) return;
    final path = await viewModel.acquireForLearning(entryId);
    if (path == null) return;
    beforeOpen?.call();
    play(path);
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
                  _showDetailBottomSheet(context);
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
                    item: state.selectedEntry!,
                    source: state.selectedSource!,
                    durationMs: viewModel.durationMsFor(
                      state.selectedEntry!.id,
                    ),
                    acquisitionState: state.acquisitionStateOf(
                      state.selectedEntry!.id,
                    ),
                    acquisitionPhase: state.acquisitionPhaseOf(
                      state.selectedEntry!.id,
                    ),
                    downloadProgress: state.downloadProgressOf(
                      state.selectedEntry!.id,
                    ),
                    acquisitionFailure: state.acquisitionFailureOf(
                      state.selectedEntry!.id,
                    ),
                    onStartLearning: onPlayMedia == null
                        ? null
                        : () => _startLearning(state.selectedEntry!.id),
                    onCancelDownload: () =>
                        viewModel.cancelDownload(state.selectedEntry!.id),
                    onRecheckAvailability: () => viewModel.refreshMediaAvailability(
                      state.selectedEntry!.id,
                    ),
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

  void _showDetailBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The sheet closes itself only after acquisition succeeds: while media
      // is downloading or has failed, it stays open so the progress and the
      // retry have a surface to live on.
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
                          item: currentEntry,
                          source: currentSource,
                          durationMs: viewModel.durationMsFor(currentEntry.id),
                          acquisitionState: state.acquisitionStateOf(
                            currentEntry.id,
                          ),
                          acquisitionPhase: state.acquisitionPhaseOf(
                            currentEntry.id,
                          ),
                          downloadProgress: state.downloadProgressOf(
                            currentEntry.id,
                          ),
                          acquisitionFailure: state.acquisitionFailureOf(
                            currentEntry.id,
                          ),
                          onStartLearning: onPlayMedia == null
                              ? null
                              : () => _startLearning(
                                  currentEntry.id,
                                  beforeOpen: () =>
                                      Navigator.of(bottomSheetContext).pop(),
                                ),
                          onCancelDownload: () =>
                              viewModel.cancelDownload(currentEntry.id),
                          onRecheckAvailability: () =>
                              viewModel.refreshMediaAvailability(currentEntry.id),
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

}

class _DiscoveryChannelChips extends StatelessWidget {
  const _DiscoveryChannelChips({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelectSource,
  });

  final List<ContentSource> sources;
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

  final List<ContentSource> sources;
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
                          item: entry,
                          source: state.sourceById(entry.sourceId) ?? source!,
                          durationMs: durationMsFor(entry.id),
                          acquisitionState: state.acquisitionStateOf(entry.id),
                          downloadProgress: state.downloadProgressOf(entry.id),
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
                            item: entry,
                            source: state.sourceById(entry.sourceId) ?? source!,
                            durationMs: durationMsFor(entry.id),
                            acquisitionState: state.acquisitionStateOf(entry.id),
                            downloadProgress: state.downloadProgressOf(
                              entry.id,
                            ),
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
