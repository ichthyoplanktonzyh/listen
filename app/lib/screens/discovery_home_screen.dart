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

/// A material-first home surface.
///
/// Sources are discovery aids, not the primary object. The learner sees
/// material first, can move between audio, video, and articles at the same
/// level, and opens details only when a specific item is chosen.
class DiscoveryHome extends StatelessWidget {
  const DiscoveryHome({
    super.key,
    required this.viewModel,
    required this.onOpenMedia,
    this.onPlayMedia,
    this.onOpenDocument,
  });

  final DiscoveryViewModel viewModel;

  /// The app's generic "open a file from disk" action. It cannot open a
  /// *selected* entry, so it only appears where that is what is being offered.
  final VoidCallback onOpenMedia;

  final ValueChanged<String>? onPlayMedia;

  /// Opens an acquired article's Material in the document session. Required
  /// for document items; without it a document item has nothing to open.
  final ValueChanged<String>? onOpenDocument;

  /// The single "start learning" intent: acquires local content when needed
  /// (progress stays on this surface), then hands the openable target — a
  /// media path or a document Material — to the matching opener. Returns
  /// without opening on failure or cancel — the discovery state carries the
  /// typed failure for a retry instead.
  Future<void> _startLearning(
    String entryId, {
    VoidCallback? beforeOpen,
  }) async {
    final play = onPlayMedia;
    final openDocument = onOpenDocument;
    if (play == null && openDocument == null) return;
    final target = await viewModel.acquireForLearning(entryId);
    if (target == null) return;
    beforeOpen?.call();
    final materialId = target.materialId;
    if (materialId != null) {
      openDocument?.call(materialId);
      return;
    }
    play?.call(target.mediaPath!);
  }

  @override
  Widget build(BuildContext context) {
    final canStart = onPlayMedia != null || onOpenDocument != null;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final state = viewModel.state;
        return LayoutBuilder(
          builder: (context, constraints) {
            return _DiscoveryShelf(
              state: state,
              durationMsFor: viewModel.durationMsFor,
              onSelectItem: (id) {
                viewModel.selectItem(id);
                _showDetailBottomSheet(context);
              },
              onDownload: viewModel.startDownload,
              onCancelDownload: viewModel.cancelDownload,
              onImport: viewModel.importCustomUrl,
              onSelectSource: viewModel.selectChannel,
              onRetrySources: viewModel.load,
              onRetryEntries: viewModel.retryEntries,
              onRefreshSource: viewModel.refreshSource,
              onOpenMedia: onOpenMedia,
              isGrid: constraints.maxWidth >= ListenBreakpoints.discoveryGrid,
              canStart: canStart,
              onStartLearning: _startLearning,
            );
          },
        );
      },
    );
  }

  void _showDetailBottomSheet(BuildContext context) {
    final canStart = onPlayMedia != null || onOpenDocument != null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(
        maxWidth: ListenBreakpoints.cardColumnMax,
      ),
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
                          onStartLearning: !canStart
                              ? null
                              : () => _startLearning(
                                  currentEntry.id,
                                  beforeOpen: () =>
                                      Navigator.of(bottomSheetContext).pop(),
                                ),
                          onCancelDownload: () =>
                              viewModel.cancelDownload(currentEntry.id),
                          onRecheckAvailability: () => viewModel
                              .refreshMediaAvailability(currentEntry.id),
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
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: ListenSpacing.gap6),
        itemBuilder: (context, index) {
          final source = sources[index];
          return ChoiceChip(
            label: Text(sourceDisplayName(l, source)),
            selected: source.id == selectedSourceId,
            onSelected: (_) => onSelectSource(source.id),
            selectedColor: scheme.primaryContainer,
            labelStyle: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
    );
  }
}

class _ContentKindPicker extends StatelessWidget {
  const _ContentKindPicker({
    required this.sources,
    required this.selectedSource,
    required this.onSelectSource,
  });

  final List<ContentSource> sources;
  final ContentSource? selectedSource;
  final ValueChanged<String> onSelectSource;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final availableKinds = {
      for (final source in sources)
        if (source.id != DiscoveryViewModel.customSource.id) source.kind,
    };
    return Wrap(
      spacing: ListenSpacing.gap8,
      runSpacing: ListenSpacing.gap8,
      children: [
        for (final kind in ContentSourceKind.values)
          if (availableKinds.contains(kind))
            FilterChip(
              avatar: Icon(_kindIcon(kind), size: ListenIconSize.control),
              label: Text(_kindLabel(l, kind)),
              selected: selectedSource?.kind == kind,
              onSelected: (_) {
                final target = sources.firstWhere(
                  (source) => source.kind == kind,
                );
                onSelectSource(target.id);
              },
            ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l, ContentSourceKind kind) => switch (kind) {
  ContentSourceKind.youtube => l.text('homeContentVideo'),
  ContentSourceKind.podcast => l.text('homeContentAudio'),
  ContentSourceKind.document => l.text('homeContentArticles'),
};

IconData _kindIcon(ContentSourceKind kind) => switch (kind) {
  ContentSourceKind.youtube => Icons.play_circle_outline,
  ContentSourceKind.podcast => Icons.podcasts_outlined,
  ContentSourceKind.document => Icons.article_outlined,
};

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
    required this.onRefreshSource,
    required this.onOpenMedia,
    required this.isGrid,
    required this.canStart,
    required this.onStartLearning,
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
  final VoidCallback onRefreshSource;
  final VoidCallback onOpenMedia;
  final bool isGrid;
  final bool canStart;
  final Future<void> Function(String entryId) onStartLearning;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final source = state.selectedSource;
    final isCustomSource = source?.id == DiscoveryViewModel.customSource.id;

    return ColoredBox(
      color: scheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ListenSpacing.gap24,
                ListenSpacing.gap24,
                ListenSpacing.gap24,
                ListenSpacing.gap16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.text('homeExploreTitle'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: ListenSpacing.gap4),
                  Text(
                    l.text('homeExploreSubtitle'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (state.sources.isNotEmpty) ...[
                    const SizedBox(height: ListenSpacing.gap16),
                    _ContentKindPicker(
                      sources: state.sources,
                      selectedSource: source,
                      onSelectSource: onSelectSource,
                    ),
                    const SizedBox(height: ListenSpacing.gap16),
                    Text(
                      l.text('homeBrowseSources'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap8),
                    _DiscoveryChannelChips(
                      sources: state.sources,
                      selectedSourceId: state.selectedSourceId,
                      onSelectSource: onSelectSource,
                    ),
                  ],
                ],
              ),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l
                                .text('homeLatestFrom')
                                .replaceFirst(
                                  '{source}',
                                  sourceDisplayName(l, source),
                                ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: l.text('refresh'),
                          onPressed: onRefreshSource,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
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
                            .text('discoveryItemCount')
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
                          onStartLearning: canStart
                              ? () => onStartLearning(entry.id)
                              : null,
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
                            acquisitionState: state.acquisitionStateOf(
                              entry.id,
                            ),
                            downloadProgress: state.downloadProgressOf(
                              entry.id,
                            ),
                            selected: entry.id == state.selectedEntryId,
                            onTap: () => onSelectItem(entry.id),
                            onDownload: () => onDownload(entry.id),
                            onCancel: () => onCancelDownload(entry.id),
                            onStartLearning: canStart
                                ? () => onStartLearning(entry.id)
                                : null,
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
