import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/discovery.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/listen_loading.dart';
import 'cover_image.dart';
import 'cover_tone.dart';
import 'discovery_preview_shell.dart';
import 'source_display_name.dart';

/// The right-hand item detail: full metadata plus one active decision —
/// "start learning". Acquiring the content, when needed, happens here with its
/// progress visible; opening Workbench is the caller's step after
/// [DiscoveryViewModel.acquireForLearning] returns a local path.
class DiscoveryDetailPanel extends StatelessWidget {
  const DiscoveryDetailPanel({
    super.key,
    required this.item,
    required this.source,
    this.durationMs,
    required this.acquisitionState,
    required this.acquisitionPhase,
    required this.downloadProgress,
    this.acquisitionFailure,
    required this.onStartLearning,
    required this.onCancelDownload,
    required this.onRecheckAvailability,
  });

  final DiscoveryItem item;
  final ContentSource source;
  final int? durationMs;
  final DiscoveryItemState acquisitionState;
  final ItemAcquisitionPhase acquisitionPhase;

  /// Null while the total is unknown; renders indeterminate.
  final double? downloadProgress;

  /// Why the last acquisition attempt failed, shown only in the failed state.
  final ApiFailure? acquisitionFailure;

  /// The single "start learning" intent. Null when nothing in this app can
  /// open the media, so the button renders disabled rather than pretending.
  final VoidCallback? onStartLearning;
  final VoidCallback onCancelDownload;

  /// Re-runs the local-media reconciliation after an unavailable answer.
  final VoidCallback onRecheckAvailability;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: ListView(
        padding: ListenPadding.pageCompact,
        children: [
          _HeroCover(item: item, source: source),
          const SizedBox(height: ListenSpacing.gap12),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: ListenSpacing.gap12),
          _MetaRow(
            label: l.text('discoveryDuration'),
            // A duration nobody has stated is said to be unstated. It used to
            // be a hardcoded five minutes rendered as a fact.
            value: switch (durationMs ?? item.durationMs) {
              final int known => formatDuration(Duration(milliseconds: known)),
              null => l.text('discoveryDurationUnknown'),
            },
          ),
          _MetaRow(label: l.text('discoveryLanguage'), value: item.language),
          const SizedBox(height: ListenSpacing.gap24),

          _MediaAccessCard(
            item: item,
            acquisitionState: acquisitionState,
            acquisitionPhase: acquisitionPhase,
            downloadProgress: downloadProgress,
            acquisitionFailure: acquisitionFailure,
            onStartLearning: onStartLearning,
            onCancelDownload: onCancelDownload,
            onRecheckAvailability: onRecheckAvailability,
          ),
        ],
      ),
    );
  }
}

String _coverInitial(String text) {
  if (text.isEmpty) return '?';
  return text.characters.first.toUpperCase();
}

class _HeroCover extends StatelessWidget {
  const _HeroCover({required this.item, required this.source});

  final DiscoveryItem item;
  final ContentSource source;

  @override
  Widget build(BuildContext context) {
    final background = discoveryCoverTone(context, source.cover);
    final ink = discoveryCoverInk(context, source.cover);
    final thumbnail = item.thumbnailUrl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: ListenRadii.surfaceBorder,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnail != null && thumbnail.isNotEmpty)
              DiscoveryCoverImage(
                url: thumbnail,
                // The hero fills the panel, which is 380 wide in the preview
                // and narrower on a split layout; decoding to the wider case
                // keeps it crisp without reaching 3000px.
                width: 380,
                tone: background,
                fallback: _HeroCaption(
                  ink: ink,
                  sourceName: source.name,
                  title: item.title,
                ),
              )
            else
              _HeroCaption(
                ink: ink,
                sourceName: sourceDisplayName(
                  AppLocalizations.of(context),
                  source,
                ),
                title: item.title,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroCaption extends StatelessWidget {
  const _HeroCaption({
    required this.ink,
    required this.sourceName,
    required this.title,
  });

  final Color ink;
  final String sourceName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sourceName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ink.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              _coverInitial(title),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// The media-access surface: one primary action per state, always answering
/// "can I learn this now, and if not, what is actually happening?".
///
/// This deliberately knows nothing about packages, generation or transcripts:
/// once the content is local, Workbench owns learning-transcript readiness.
class _MediaAccessCard extends StatelessWidget {
  const _MediaAccessCard({
    required this.item,
    required this.acquisitionState,
    required this.acquisitionPhase,
    required this.downloadProgress,
    this.acquisitionFailure,
    required this.onStartLearning,
    required this.onCancelDownload,
    required this.onRecheckAvailability,
  });

  final DiscoveryItem item;
  final DiscoveryItemState acquisitionState;
  final ItemAcquisitionPhase acquisitionPhase;

  /// Null while the total is unknown; renders indeterminate.
  final double? downloadProgress;
  final ApiFailure? acquisitionFailure;
  final VoidCallback? onStartLearning;
  final VoidCallback onCancelDownload;
  final VoidCallback onRecheckAvailability;

  bool get isDownloading =>
      acquisitionState == DiscoveryItemState.acquiring &&
      acquisitionPhase == ItemAcquisitionPhase.download;
  bool get isChecking =>
      acquisitionState == DiscoveryItemState.acquiring &&
      acquisitionPhase == ItemAcquisitionPhase.check;
  bool get downloadFailed =>
      acquisitionState == DiscoveryItemState.failed;
  bool get isLocal => acquisitionState == DiscoveryItemState.available;
  bool get isUndetermined =>
      acquisitionState == DiscoveryItemState.unavailable;
  bool get isDiscoverable =>
      acquisitionState == DiscoveryItemState.discoverable;
  bool get canAcquire => item.acquisition != AcquisitionMode.none;
  bool get loading => isDownloading || isChecking;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: ListenRadii.surfaceBorder,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                loading
                    ? Icons.download
                    : downloadFailed
                    ? Icons.error_outline
                    : isLocal
                    ? Icons.check_circle
                    : isUndetermined
                    ? Icons.help_outline
                    : Icons.school_outlined,
                size: ListenIconSize.control,
                color: downloadFailed
                    ? scheme.error
                    : isLocal
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  _statusText(l),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: downloadFailed
                        ? scheme.error
                        : isLocal
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (loading) ...[
                const SizedBox(width: ListenSpacing.gap8),
                const ListenLoading.inline(size: 16),
              ],
            ],
          ),
          const SizedBox(height: ListenSpacing.gap12),
          ..._actionArea(context),
        ],
      ),
    );
  }

  String _statusText(AppLocalizations l) {
    if (isDownloading) return l.text('discoveryGettingMedia');
    if (isChecking) return l.text('discoveryCheckingLocalMedia');
    if (downloadFailed) return l.text('discoveryDownloadFailed');
    if (isLocal) return l.text('discoveryAvailableOnDevice');
    if (isUndetermined) return l.text('discoveryCannotCheckMedia');
    if (isDiscoverable) return l.text('discoveryCannotAcquire');
    return l.text('discoveryRemoteMedia');
  }

  List<Widget> _actionArea(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (isDownloading) {
      return [
        // Null renders the indeterminate animation: running, length unknown.
        // A bar held at 0% reads as a hang.
        LinearProgressIndicator(value: downloadProgress),
        const SizedBox(height: ListenSpacing.gap6),
        OutlinedButton.icon(
          onPressed: onCancelDownload,
          icon: const Icon(Icons.close, size: ListenIconSize.inline),
          label: Text(l.text('discoveryCancel')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ];
    }

    if (downloadFailed) {
      return [
        if (acquisitionFailure case final failure?) ...[
          Text(
            _downloadFailureDetail(l, failure),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        FilledButton.icon(
          onPressed: onStartLearning,
          icon: const Icon(Icons.refresh, size: ListenIconSize.control),
          label: Text(l.text('discoveryDownloadFailedRetry')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 36),
          ),
        ),
      ];
    }

    if (isLocal || (canAcquire && !isChecking && !isUndetermined)) {
      // Local content, or remote content whose bytes can be acquired: the
      // single "start learning" intent covers both. In the remote case the
      // press starts acquisition and this surface keeps showing its progress.
      return [
        FilledButton.icon(
          onPressed: onStartLearning,
          icon: const Icon(Icons.school, size: ListenIconSize.control),
          label: Text(l.text('discoveryStartLearning')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ];
    }

    if (isChecking) {
      // The status row already carries the sentence; the loader travels with
      // it, so the action area has nothing further to say.
      return const [];
    }

    if (isUndetermined) {
      return [
        Text(
          l.text('discoveryCannotCheckMedia'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        OutlinedButton.icon(
          onPressed: onRecheckAvailability,
          icon: const Icon(Icons.refresh, size: ListenIconSize.control),
          label: Text(l.text('discoveryCheckAgain')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 36),
          ),
        ),
      ];
    }

    // A discoverable item: the source lists it but grants nothing to fetch.
    // The status row already carries the sentence, so there is no dead
    // download/start CTA and nothing further to say.
    return const [];
  }
}

String _downloadFailureDetail(AppLocalizations l, ApiFailure failure) {
  final message = failure.message;
  if (message == null || message.isEmpty) {
    final code = failure.code;
    if (code == null || code.isEmpty) return l.text('discoveryDownloadFailed');
    return code;
  }
  return message;
}

@Preview(name: 'Detail panel · local', group: 'Discovery', size: Size(380, 720))
Widget discoveryDetailPanelLocalPreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    item: const DiscoveryItem(
      id: 'i-preview',
      sourceId: 'c-preview',
      title: '6 Minute English: Why do we forget?',
      description: 'Memory researchers explain why names and facts slip away.',
      durationMs: 360000,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 142000,
    ),
    source: const ContentSource(
      id: 'c-preview',
      name: 'BBC Learning English',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.blue,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    acquisitionState: DiscoveryItemState.available,
    acquisitionPhase: ItemAcquisitionPhase.download,
    downloadProgress: 1,
    onStartLearning: _noop,
    onCancelDownload: _noop,
    onRecheckAvailability: _noop,
  ),
  width: 380,
  height: 720,
);

@Preview(name: 'Detail panel · remote', group: 'Discovery', size: Size(380, 720))
Widget discoveryDetailPanelRemotePreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    item: const DiscoveryItem(
      id: 'i-preview-remote',
      sourceId: 'c-preview',
      title: 'The fastest way to board a plane, according to mathematics',
      description: 'A queueing-theory look at why boarding takes so long.',
      durationMs: 357000,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 142000,
      acquisition: AcquisitionMode.externalTool,
      contentKind: ItemContentKind.video,
      mediaUrl: 'https://www.youtube.com/watch?v=i-preview-remote',
    ),
    source: const ContentSource(
      id: 'c-preview',
      name: 'TED-Ed',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.rose,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    acquisitionState: DiscoveryItemState.acquirable,
    acquisitionPhase: ItemAcquisitionPhase.download,
    downloadProgress: null,
    onStartLearning: _noop,
    onCancelDownload: _noop,
    onRecheckAvailability: _noop,
  ),
  width: 380,
  height: 720,
);

@Preview(name: 'Detail panel · acquiring', group: 'Discovery', size: Size(380, 720))
Widget discoveryDetailPanelAcquiringPreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    item: const DiscoveryItem(
      id: 'i-preview-acquiring',
      sourceId: 'c-preview',
      title: 'The fastest way to board a plane, according to mathematics',
      description: 'A queueing-theory look at why boarding takes so long.',
      durationMs: 357000,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 142000,
      acquisition: AcquisitionMode.externalTool,
      contentKind: ItemContentKind.video,
      mediaUrl: 'https://www.youtube.com/watch?v=i-preview-acquiring',
    ),
    source: const ContentSource(
      id: 'c-preview',
      name: 'TED-Ed',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.rose,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    acquisitionState: DiscoveryItemState.acquiring,
    acquisitionPhase: ItemAcquisitionPhase.download,
    downloadProgress: 0.4,
    onStartLearning: _noop,
    onCancelDownload: _noop,
    onRecheckAvailability: _noop,
  ),
  width: 380,
  height: 720,
);

@Preview(
  name: 'Detail panel · acquisition unavailable',
  group: 'Discovery',
  size: Size(380, 720),
)
Widget discoveryDetailPanelUnavailablePreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    item: const DiscoveryItem(
      id: 'i-preview-none',
      sourceId: 'c-preview',
      title: 'Up First: notes without an enclosure',
      description: 'A feed item with show notes but no audio.',
      durationMs: null,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 0,
    ),
    source: const ContentSource(
      id: 'c-preview',
      name: 'NPR',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.blue,
      kind: ContentSourceKind.podcast,
      avatarUrl: null,
    ),
    acquisitionState: DiscoveryItemState.discoverable,
    acquisitionPhase: ItemAcquisitionPhase.download,
    downloadProgress: null,
    onStartLearning: _noop,
    onCancelDownload: _noop,
    onRecheckAvailability: _noop,
  ),
  width: 380,
  height: 720,
);

void _noop() {}
