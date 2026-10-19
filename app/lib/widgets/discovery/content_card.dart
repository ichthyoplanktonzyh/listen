import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../localization.dart';
import '../../models/discovery.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import 'cover_image.dart';
import 'cover_tone.dart';
import 'discovery_preview_shell.dart';
import 'source_display_name.dart';

/// A card representing a discovery item: thumbnail, title, source, published
/// time, and the acquisition/local state.
class DiscoveryContentCard extends StatelessWidget {
  const DiscoveryContentCard({
    super.key,
    required this.item,
    required this.source,
    this.durationMs,
    required this.acquisitionState,
    this.downloadProgress,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.onCancel,
    this.onStartLearning,
    this.axis = Axis.horizontal,
  });

  final DiscoveryItem item;
  final ContentSource source;
  final int? durationMs;
  final DiscoveryItemState acquisitionState;

  /// Null while the total is unknown; renders indeterminate.
  final double? downloadProgress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback? onStartLearning;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.surfaceContainerLow : Colors.transparent,
      borderRadius: ListenRadii.surfaceBorder,
      child: InkWell(
        borderRadius: ListenRadii.surfaceBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: axis == Axis.horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardCover(
                      item: item,
                      source: source,
                      selected: selected,
                      durationMs: durationMs,
                      axis: axis,
                    ),
                    const SizedBox(width: ListenSpacing.gap12),
                    Expanded(child: _buildMetadata(context, l, scheme)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _CardCover(
                          item: item,
                          source: source,
                          selected: selected,
                          durationMs: durationMs,
                          axis: axis,
                        ),
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    _buildMetadata(context, l, scheme),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMetadata(
    BuildContext context,
    AppLocalizations l,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          '${sourceDisplayName(l, source)} · ${_formatViews(l, item.viewCount)} · ${item.publishedOn}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: ListenSpacing.gap8,
          runSpacing: ListenSpacing.gap4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            switch (acquisitionState) {
              DiscoveryItemState.available => _LocalChip(
                labelText: l.text('discoveryAvailableOnDevice'),
              ),
              DiscoveryItemState.discoverable => Text(
                l.text('discoveryUnacquirable'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              DiscoveryItemState.acquirable ||
              DiscoveryItemState.unavailable => _DownloadControl(
                state: acquisitionState,
                progress: downloadProgress,
                onDownload: onDownload,
                onCancel: onCancel,
              ),
              DiscoveryItemState.acquiring => _DownloadControl(
                state: acquisitionState,
                progress: downloadProgress,
                onDownload: onDownload,
                onCancel: onCancel,
              ),
              DiscoveryItemState.failed => _DownloadControl(
                state: acquisitionState,
                progress: downloadProgress,
                onDownload: onDownload,
                onCancel: onCancel,
              ),
            },
            if (onStartLearning != null &&
                (acquisitionState == DiscoveryItemState.acquirable ||
                    acquisitionState == DiscoveryItemState.available ||
                    acquisitionState == DiscoveryItemState.failed))
              FilledButton.tonalIcon(
                onPressed: onStartLearning,
                icon: const Icon(
                  Icons.school_outlined,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('discoveryStartLearning')),
              ),
          ],
        ),
      ],
    );
  }

  String _formatViews(AppLocalizations l, int count) {
    final viewsText = l.text('discoveryViews');
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M $viewsText';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}K $viewsText';
    }
    return '$count $viewsText';
  }
}

String _coverInitial(String text) {
  if (text.isEmpty) return '?';
  return text.characters.first.toUpperCase();
}

class _CardCover extends StatelessWidget {
  const _CardCover({
    required this.item,
    required this.source,
    required this.selected,
    this.durationMs,
    this.axis = Axis.horizontal,
  });

  final DiscoveryItem item;
  final ContentSource source;
  final bool selected;
  final int? durationMs;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final background = discoveryCoverTone(context, source.cover);
    final ink = discoveryCoverInk(context, source.cover);
    final scheme = Theme.of(context).colorScheme;
    final thumbnail = item.thumbnailUrl;
    return Container(
      width: axis == Axis.horizontal ? 168 : null,
      height: axis == Axis.horizontal ? 94 : null,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: ListenRadii.surfaceBorder,
        border: selected ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnail != null && thumbnail.isNotEmpty)
            DiscoveryCoverImage(
              url: thumbnail,
              // The grid cell has no fixed width, so the shelf's column width
              // stands in; either way the decode is bounded by something the
              // card is actually drawn at rather than by the source artwork.
              width: axis == Axis.horizontal ? 168 : 320,
              tone: background,
              fallback: _CoverPlaceholder(
                ink: ink,
                sourceName: source.name,
                title: item.title,
              ),
            )
          else
            _CoverPlaceholder(
              ink: ink,
              sourceName: source.name,
              title: item.title,
            ),
          // Duration badge in the bottom right corner — only when a duration
          // is actually known. The badge used to render a hardcoded five
          // minutes for every entry in a feed that publishes no durations,
          // which is the most confident-looking way to state a guess.
          if (durationMs ?? item.durationMs case final int known)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: ListenPadding.tight,
                decoration: BoxDecoration(
                  color: scheme.inverseSurface.withValues(alpha: 0.75),
                  borderRadius: ListenRadii.controlBorder,
                ),
                child: Text(
                  formatDuration(Duration(milliseconds: known)),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onInverseSurface,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({
    required this.ink,
    required this.sourceName,
    required this.title,
  });

  final Color ink;
  final String sourceName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 10,
          bottom: 8,
          child: Text(
            _coverInitial(title),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 8,
          child: SizedBox(
            width: 148,
            child: Text(
              sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ink.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalChip extends StatelessWidget {
  const _LocalChip({required this.labelText});

  final String labelText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: ListenPadding.tight,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: ListenRadii.pillBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: ListenIconSize.inline,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: ListenSpacing.gap4),
          Text(
            labelText,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.state,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
  });

  final DiscoveryItemState state;

  /// Null when the response carried no length, so the bar animates and the
  /// percentage is omitted rather than invented.
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return switch (state) {
      DiscoveryItemState.acquirable ||
      DiscoveryItemState.unavailable => TextButton.icon(
        onPressed: onDownload,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.download, size: ListenIconSize.inline),
        label: Text(
          l.text('discoveryDownload'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      DiscoveryItemState.acquiring => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: ListenRadii.controlBorder,
            ),
          ),
          if (progress case final double fraction) ...[
            const SizedBox(width: ListenSpacing.gap6),
            Text(
              '${(fraction * 100).round()}%',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
          ],
          const SizedBox(width: ListenSpacing.gap2),
          IconButton(
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: l.text('discoveryCancel'),
            icon: Icon(
              Icons.close,
              size: ListenIconSize.inline,
              color: scheme.error,
            ),
          ),
        ],
      ),
      // The row keeps the failure and offers the retry in place. The detail
      // panel carries the reason; a card this dense only has room to say that
      // it did not work and that trying again is one tap away.
      DiscoveryItemState.failed => TextButton.icon(
        onPressed: onDownload,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: scheme.error,
        ),
        icon: const Icon(Icons.refresh, size: ListenIconSize.inline),
        label: Text(
          l.text('discoveryDownloadFailedRetry'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      DiscoveryItemState.available ||
      DiscoveryItemState.discoverable => const SizedBox.shrink(),
    };
  }
}

@Preview(name: 'Content card', group: 'Discovery', size: Size(620, 120))
Widget discoveryContentCardPreview() => discoveryPreviewShell(
  const Padding(
    padding: EdgeInsets.all(12),
    child: DiscoveryContentCard(
      item: DiscoveryItem(
        id: 'i-preview',
        sourceId: 'c-preview',
        title: '6 Minute English: Why do we forget?',
        description: '',
        durationMs: 360000,
        language: 'English',
        publishedOn: '2026-07-28',
        thumbnailUrl: null,
        viewCount: 142000,
      ),
      source: ContentSource(
        id: 'c-preview',
        name: 'BBC Learning English',
        language: 'English',
        description: '',
        cover: ChannelCoverTone.blue,
        kind: ContentSourceKind.youtube,
        avatarUrl: null,
      ),
      acquisitionState: DiscoveryItemState.available,
      downloadProgress: 1,
      selected: false,
      onTap: _noop,
      onDownload: _noop,
      onCancel: _noop,
    ),
  ),
  width: 620,
  height: 120,
);

/// The same card for a source that publishes no duration — a YouTube Atom feed
/// before its background worker answers, or a podcast item with no
/// `itunes:duration`.
///
/// It exists so the honest state is something you can look at. The duration
/// badge is absent rather than showing a placeholder, and "absent" is exactly
/// the kind of difference that is invisible in a test name and obvious in a
/// picture.
@Preview(
  name: 'Content card · duration unknown',
  group: 'Discovery',
  size: Size(620, 120),
)
Widget discoveryContentCardUnknownDurationPreview() => discoveryPreviewShell(
  const Padding(
    padding: EdgeInsets.all(12),
    child: DiscoveryContentCard(
      item: DiscoveryItem(
        id: 'i-preview-unknown',
        sourceId: 'c-preview',
        title: 'Up First: the stories behind the morning news',
        description: '',
        durationMs: null,
        language: 'English',
        publishedOn: '2026-07-28',
        thumbnailUrl: null,
        viewCount: 0,
        acquisition: AcquisitionMode.enclosure,
        contentKind: ItemContentKind.audio,
        mediaUrl: 'https://cdn.example.com/ep001.mp3',
      ),
      source: ContentSource(
        id: 'c-preview',
        name: 'NPR',
        language: 'English',
        description: '',
        cover: ChannelCoverTone.blue,
        kind: ContentSourceKind.podcast,
        avatarUrl: null,
      ),
      acquisitionState: DiscoveryItemState.acquirable,
      downloadProgress: 0,
      selected: false,
      onTap: _noop,
      onDownload: _noop,
      onCancel: _noop,
    ),
  ),
  width: 620,
  height: 120,
);

void _noop() {}

/// A download in flight whose total the host never stated.
///
/// The bar animates instead of sitting at 0%, and no percentage is shown.
/// Which of the two is on screen is the whole difference between "working"
/// and "hung", and it is invisible in a test name.
@Preview(
  name: 'Content card · downloading, length unknown',
  group: 'Discovery',
  size: Size(620, 120),
)
Widget discoveryContentCardIndeterminatePreview() => discoveryPreviewShell(
  const Padding(
    padding: EdgeInsets.all(12),
    child: DiscoveryContentCard(
      item: DiscoveryItem(
        id: 'i-preview-indeterminate',
        sourceId: 'c-preview',
        title: 'Up First: the stories behind the morning news',
        description: '',
        durationMs: null,
        language: 'English',
        publishedOn: '2026-07-28',
        thumbnailUrl: null,
        viewCount: 0,
        acquisition: AcquisitionMode.enclosure,
        contentKind: ItemContentKind.audio,
        mediaUrl: 'https://cdn.example.com/ep001.mp3',
      ),
      source: ContentSource(
        id: 'c-preview',
        name: 'NPR',
        language: 'English',
        description: '',
        cover: ChannelCoverTone.blue,
        kind: ContentSourceKind.podcast,
        avatarUrl: null,
      ),
      acquisitionState: DiscoveryItemState.acquiring,
      downloadProgress: null,
      selected: false,
      onTap: _noop,
      onDownload: _noop,
      onCancel: _noop,
    ),
  ),
  width: 620,
  height: 120,
);
