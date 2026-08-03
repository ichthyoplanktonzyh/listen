import 'package:flutter/material.dart';

import '../controllers/discovery_view_model.dart';
import '../localization.dart';
import '../models/discovery.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_loading.dart';
import '../widgets/discovery/source_tile.dart';
import '../widgets/discovery/content_card.dart';
import '../widgets/discovery/detail_panel.dart';
import '../widgets/listen_wordmark.dart';

/// The media-aggregation landing page: YouTube channels on the left, media cards
/// in the middle, and the action details panel on the right.
class DiscoveryHome extends StatelessWidget {
  const DiscoveryHome({
    super.key,
    required this.viewModel,
    required this.onOpenMedia,
    required this.onOpenSettings,
    required this.onOpenClassicHome,
    this.onPlayMedia,
  });

  final DiscoveryViewModel viewModel;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenClassicHome;
  final ValueChanged<String>? onPlayMedia;

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
            final showRail =
                constraints.maxWidth >= ListenBreakpoints.homeSidebar;
            final children = <Widget>[
              if (showRail)
                _DiscoveryRail(
                  sources: state.sources,
                  selectedSourceId: state.selectedSourceId,
                  onSelectSource: viewModel.selectChannel,
                  onOpenMyLearning: onOpenClassicHome,
                  onOpenSettings: onOpenSettings,
                ),
              Expanded(
                child: _DiscoveryShelf(
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
                ),
              ),
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
                    onOpenPlayer: () {
                      final localPath = viewModel.localPathFor(
                        state.selectedEntry!.id,
                      );
                      if (localPath != null && onPlayMedia != null) {
                        onPlayMedia!(localPath);
                      } else {
                        onOpenMedia();
                      }
                    },
                    onViewPackage: () => _showPackageDialog(context),
                    onGenerate: () =>
                        viewModel.startGeneration(state.selectedEntry!.id),
                    onCancelGenerate: () =>
                        viewModel.cancelGeneration(state.selectedEntry!.id),
                  ),
                ),
            ];
            if (showRail) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Row(children: children),
              );
            }
            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  _DiscoveryChannelChips(
                    sources: state.sources,
                    selectedSourceId: state.selectedSourceId,
                    onSelectSource: viewModel.selectChannel,
                  ),
                  Expanded(
                    child: _DiscoveryShelf(
                      state: state,
                      durationMsFor: viewModel.durationMsFor,
                      onSelectItem: (id) {
                        viewModel.selectItem(id);
                        final entry = state.entryById(id);
                        if (entry != null) {
                          _showDetailBottomSheet(context, entry);
                        }
                      },
                      onDownload: viewModel.startDownload,
                      onCancelDownload: viewModel.cancelDownload,
                      onImport: viewModel.importCustomUrl,
                    ),
                  ),
                ],
              ),
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
                          onOpenPlayer: () {
                            Navigator.of(bottomSheetContext).pop();
                            final localPath = viewModel.localPathFor(
                              currentEntry.id,
                            );
                            if (localPath != null && onPlayMedia != null) {
                              onPlayMedia!(localPath);
                            } else {
                              onOpenMedia();
                            }
                          },
                          onViewPackage: () => _showPackageDialog(context),
                          onGenerate: () =>
                              viewModel.startGeneration(currentEntry.id),
                          onCancelGenerate: () =>
                              viewModel.cancelGeneration(currentEntry.id),
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

class _DiscoveryRail extends StatelessWidget {
  const _DiscoveryRail({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelectSource,
    required this.onOpenMyLearning,
    required this.onOpenSettings,
  });

  final List<MediaSource> sources;
  final String? selectedSourceId;
  final void Function(String) onSelectSource;
  final VoidCallback onOpenMyLearning;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 232,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ListenWordmark(size: 22),
                  const SizedBox(width: ListenSpacing.gap8),
                  Expanded(
                    child: Text(
                      l.text('discoveryPrototypeBadge'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                l.text('discoverySources'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap6),
              Expanded(
                child: ListView(
                  children: [
                    for (final source in sources)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: DiscoverySourceTile(
                          source: source,
                          selected: source.id == selectedSourceId,
                          onTap: () => onSelectSource(source.id),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: ListenSpacing.gap16),
              TextButton.icon(
                onPressed: onOpenMyLearning,
                icon: const Icon(
                  Icons.school_outlined,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('discoveryMyLearning')),
              ),
              TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(
                  Icons.settings_outlined,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('discoverySettings')),
              ),
            ],
          ),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(right: ListenSpacing.gap6),
              child: ChoiceChip(
                label: Text(source.name),
                selected: source.id == selectedSourceId,
                onSelected: (_) => onSelectSource(source.id),
                selectedColor: scheme.primaryContainer,
                labelStyle: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveryShelf extends StatelessWidget {
  const _DiscoveryShelf({
    required this.state,
    required this.durationMsFor,
    required this.onSelectItem,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onImport,
  });

  final DiscoveryState state;
  final int? Function(String entryId) durationMsFor;
  final void Function(String) onSelectItem;
  final void Function(String) onDownload;
  final void Function(String) onCancelDownload;
  final ValueChanged<String> onImport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final source = state.selectedSource;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: ListenPadding.pageCompact,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ListenBreakpoints.wideColumnMax,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source != null) ...[
                  Text(
                    source.name,
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
                  const SizedBox(height: ListenSpacing.gap8),
                  Text(
                    '${state.entries.length} videos',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
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
                  const SizedBox(height: ListenSpacing.gap16),
                ],
                if (state.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ListenSpacing.gap32,
                    ),
                    child: Center(child: ListenLoading()),
                  )
                else if (state.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ListenSpacing.gap32,
                    ),
                    child: Center(
                      child: Text(
                        l.text('discoveryEmptyChannel'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (final entry in state.entries)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: ListenSpacing.gap8,
                      ),
                      child: DiscoveryContentCard(
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
                      ),
                    ),
              ],
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
