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
import 'cover_tone.dart';
import 'discovery_preview_shell.dart';

/// The right-hand lesson detail: shows full details of a YouTube video, its
/// metadata, and orchestrates the core user journey (Download -> Package -> Study).
class DiscoveryDetailPanel extends StatelessWidget {
  const DiscoveryDetailPanel({
    super.key,
    required this.entry,
    required this.source,
    this.durationMs,
    required this.downloadState,
    required this.downloadProgress,
    required this.packageStatus,
    required this.generationStatus,
    required this.generatorPhase,
    required this.generationFailure,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onOpenPlayer,
    required this.onViewPackage,
    required this.onGenerate,
    required this.onCancelGenerate,
  });

  final MediaEntry entry;
  final MediaSource source;
  final int? durationMs;
  final DownloadState downloadState;
  final double downloadProgress;
  final PackageStatus packageStatus;
  final ContentGenerationStatus generationStatus;
  final String? generatorPhase;
  final ApiFailure? generationFailure;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onOpenPlayer;
  final VoidCallback onViewPackage;
  final VoidCallback onGenerate;
  final VoidCallback onCancelGenerate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: ListView(
        padding: ListenPadding.pageCompact,
        children: [
          _HeroCover(entry: entry, source: source),
          const SizedBox(height: ListenSpacing.gap12),
          Text(
            entry.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: ListenSpacing.gap4),
          Text(
            '${source.name} · ${entry.publishedOn}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap12),
          Text(
            entry.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap16),
          _MetaRow(
            label: l.text('discoveryDuration'),
            value: formatDuration(
              Duration(milliseconds: durationMs ?? entry.durationMs),
            ),
          ),
          _MetaRow(
            label: l.text('discoveryLevel'), // Re-mapped to views
            value: _formatViews(l, entry.viewCount),
          ),
          _MetaRow(label: l.text('discoveryLanguage'), value: entry.language),
          _MetaRow(
            label: l.text('discoveryPublished'),
            value: entry.publishedOn,
          ),
          const SizedBox(height: ListenSpacing.gap24),

          // Action flow dashboard card
          _UserJourneyActionsCard(
            downloadState: downloadState,
            downloadProgress: downloadProgress,
            packageStatus: packageStatus,
            generationStatus: generationStatus,
            generatorPhase: generatorPhase,
            generationFailure: generationFailure,
            onDownload: onDownload,
            onCancelDownload: onCancelDownload,
            onGenerate: onGenerate,
            onCancelGenerate: onCancelGenerate,
            onOpenPlayer: onOpenPlayer,
          ),
          const SizedBox(height: ListenSpacing.gap16),

          if (packageStatus == PackageStatus.available)
            OutlinedButton.icon(
              onPressed: onViewPackage,
              icon: const Icon(
                Icons.inventory_2_outlined,
                size: ListenIconSize.inline,
              ),
              label: Text(l.text('discoveryViewPackage')),
            ),
        ],
      ),
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

class _HeroCover extends StatelessWidget {
  const _HeroCover({required this.entry, required this.source});

  final MediaEntry entry;
  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    final background = discoveryCoverTone(context, source.cover);
    final ink = discoveryCoverInk(context, source.cover);
    final thumbnail = entry.thumbnailUrl;
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
              Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _HeroCaption(
                  ink: ink,
                  sourceName: source.name,
                  title: entry.title,
                ),
              )
            else
              _HeroCaption(
                ink: ink,
                sourceName: source.name,
                title: entry.title,
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

class _UserJourneyActionsCard extends StatelessWidget {
  const _UserJourneyActionsCard({
    required this.downloadState,
    required this.downloadProgress,
    required this.packageStatus,
    required this.generationStatus,
    required this.generatorPhase,
    required this.generationFailure,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onGenerate,
    required this.onCancelGenerate,
    required this.onOpenPlayer,
  });

  final DownloadState downloadState;
  final double downloadProgress;
  final PackageStatus packageStatus;
  final ContentGenerationStatus generationStatus;
  final String? generatorPhase;
  final ApiFailure? generationFailure;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onGenerate;
  final VoidCallback onCancelGenerate;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final isDownloaded = downloadState == DownloadState.done;
    final isDownloading = downloadState == DownloadState.downloading;

    final isPackageAvailable = packageStatus == PackageStatus.available;
    final isCheckingPackage = packageStatus == PackageStatus.checking;
    final isGenerating =
        generationStatus == ContentGenerationStatus.preparing ||
        generationStatus == ContentGenerationStatus.generating ||
        generationStatus == ContentGenerationStatus.importing;

    // Both downloaded AND package available means ready to study!
    final isReadyToLearn = isDownloaded && isPackageAvailable;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: ListenRadii.surfaceBorder,
        border: Border.all(
          color: isReadyToLearn
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: isReadyToLearn ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.text('contentPackageProgress'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isReadyToLearn ? scheme.primary : scheme.onSurface,
            ),
          ),
          const SizedBox(height: ListenSpacing.gap12),

          // ── STEP 1: Download Media ──
          Row(
            children: [
              Icon(
                isDownloaded ? Icons.check_circle : Icons.download,
                size: ListenIconSize.inline,
                color: isDownloaded ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  isDownloaded
                      ? l.text('discoveryDownloaded')
                      : isDownloading
                      ? l
                            .text('discoveryDownloading')
                            .replaceFirst(
                              '{percent}',
                              '${(downloadProgress * 100).round()}%',
                            )
                      : l.text('discoveryDownload'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isDownloading || !isDownloaded
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: ListenSpacing.gap6),
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
          ] else if (!isDownloaded) ...[
            const SizedBox(height: ListenSpacing.gap8),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download, size: ListenIconSize.control),
              label: Text(l.text('discoveryDownload')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ],

          const Divider(height: ListenSpacing.gap24),

          // ── STEP 2: Content Package ──
          if (isGenerating) ...[
            Row(
              children: [
                const ListenLoading.inline(size: 16),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l
                        .text('discoveryGenerating')
                        .replaceFirst(
                          '{phase}',
                          _generatorPhaseLabel(l, generatorPhase),
                        ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap6),
            OutlinedButton.icon(
              onPressed: onCancelGenerate,
              icon: const Icon(Icons.close, size: ListenIconSize.inline),
              label: Text(l.text('discoveryCancel')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ] else if (isCheckingPackage) ...[
            Row(
              children: [
                const ListenLoading.inline(size: 16),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('discoveryCheckingPackage'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ] else if (isPackageAvailable) ...[
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  size: ListenIconSize.control,
                  color: scheme.primary,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('discoveryPackageAvailable'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Package is NOT available (notAvailable or unknown)
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: ListenIconSize.control,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('discoveryPackageNone'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap8),

            if (generationStatus == ContentGenerationStatus.failed) ...[
              Text(
                l.text('discoveryGenerateFailed'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
              if (generationFailure case final failure?) ...[
                const SizedBox(height: ListenSpacing.gap4),
                Text(
                  _failureDetail(failure),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: ListenSpacing.gap8),
            ] else if (generationStatus ==
                ContentGenerationStatus.cancelled) ...[
              Text(
                l.text('discoveryGenerateCancelled'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap8),
            ],

            // Generate button - disabled unless media is downloaded!
            FilledButton.icon(
              onPressed: isDownloaded ? onGenerate : null,
              icon: const Icon(Icons.auto_awesome, size: ListenIconSize.control),
              label: Text(l.text('discoveryGenerate')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 36),
                backgroundColor: scheme.secondary,
                foregroundColor: scheme.onSecondary,
              ),
            ),
            if (!isDownloaded) ...[
              const SizedBox(height: ListenSpacing.gap4),
              Text(
                'Please download media first to generate a learning package.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],

          // ── STEP 3: Learning Launch ──
          if (isReadyToLearn) ...[
            const Divider(height: ListenSpacing.gap24),
            FilledButton.icon(
              onPressed: onOpenPlayer,
              icon: const Icon(Icons.school, size: ListenIconSize.control),
              label: Text(l.text('discoveryOpenLearning')),
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
          ],
        ],
      ),
    );
  }
}

@Preview(name: 'Detail panel', group: 'Discovery', size: Size(380, 720))
Widget discoveryDetailPanelPreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    entry: const MediaEntry(
      id: 'i-preview',
      sourceId: 'c-preview',
      title: '6 Minute English: Why do we forget?',
      description: 'Memory researchers explain why names and facts slip away.',
      durationMs: 360000,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 142000,
      hasPackage: true,
    ),
    source: const MediaSource(
      id: 'c-preview',
      name: 'BBC Learning English',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.blue,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    downloadState: DownloadState.downloading,
    downloadProgress: 0.4,
    packageStatus: PackageStatus.notAvailable,
    generationStatus: ContentGenerationStatus.idle,
    generatorPhase: null,
    generationFailure: null,
    onDownload: _noop,
    onCancelDownload: _noop,
    onOpenPlayer: _noop,
    onViewPackage: _noop,
    onGenerate: _noop,
    onCancelGenerate: _noop,
  ),
  width: 380,
  height: 720,
);

void _noop() {}

String _generatorPhaseLabel(AppLocalizations l, String? phase) =>
    switch (phase) {
      'validating' => l.text('contentPackagePhaseValidating'),
      'probing_media' => l.text('contentPackagePhaseProbing'),
      'normalizing_audio' => l.text('contentPackagePhaseNormalizing'),
      'transcribing' => l.text('contentPackagePhaseTranscribing'),
      'building_package' => l.text('contentPackagePhaseBuilding'),
      _ => l.text('contentPackagePhaseWorking'),
    };

String _failureDetail(ApiFailure failure) {
  final code = failure.code == null || failure.code!.isEmpty
      ? 'generator_failed'
      : failure.code!;
  final message = failure.message;
  if (message == null || message.isEmpty) return code;
  return '$code: ${message.length > 220 ? '${message.substring(0, 220)}…' : message}';
}
