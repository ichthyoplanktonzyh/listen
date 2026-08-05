import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/discovery.dart';
import '../../services/content_generator_setup.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/listen_loading.dart';
import 'cover_image.dart';
import 'cover_tone.dart';
import 'discovery_preview_shell.dart';
import 'source_display_name.dart';

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
    this.downloadFailure,
    required this.packageStatus,
    required this.generationStatus,
    required this.generatorPhase,
    required this.generationFailure,
    this.generatorState = ContentGeneratorState.ready,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onOpenPlayer,
    required this.onViewPackage,
    required this.onGenerate,
    required this.onCancelGenerate,
    required this.onRecheckPackage,
  });

  final MediaEntry entry;
  final MediaSource source;
  final int? durationMs;
  final DownloadState downloadState;

  /// Null while the total is unknown; renders indeterminate.
  final double? downloadProgress;

  /// Why the last acquisition attempt failed, shown only in the failed state.
  final ApiFailure? downloadFailure;

  final PackageStatus packageStatus;
  final ContentGenerationStatus generationStatus;
  final String? generatorPhase;
  final ApiFailure? generationFailure;

  /// Which piece of the toolchain is missing, so the unavailable row names
  /// the one thing to fix rather than saying "not configured".
  final ContentGeneratorState generatorState;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;

  /// Null when no local file backs this entry — the affordance says "open for
  /// learning", so it may only exist when there is something to open.
  final VoidCallback? onOpenPlayer;

  final VoidCallback onViewPackage;
  final VoidCallback onGenerate;
  final VoidCallback onCancelGenerate;

  /// Re-runs the package lookup after an undetermined answer.
  final VoidCallback onRecheckPackage;

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
          const SizedBox(height: ListenSpacing.gap12),
          _MetaRow(
            label: l.text('discoveryDuration'),
            // A duration nobody has stated is said to be unstated. It used to
            // be a hardcoded five minutes rendered as a fact.
            value: switch (durationMs ?? entry.durationMs) {
              final int known => formatDuration(Duration(milliseconds: known)),
              null => l.text('discoveryDurationUnknown'),
            },
          ),
          _MetaRow(label: l.text('discoveryLanguage'), value: entry.language),
          const SizedBox(height: ListenSpacing.gap24),

          // Action flow dashboard card
          _UserJourneyActionsCard(
            downloadState: downloadState,
            downloadProgress: downloadProgress,
            downloadFailure: downloadFailure,
            packageStatus: packageStatus,
            generationStatus: generationStatus,
            generatorPhase: generatorPhase,
            generationFailure: generationFailure,
            generatorState: generatorState,
            onDownload: onDownload,
            onCancelDownload: onCancelDownload,
            onGenerate: onGenerate,
            onCancelGenerate: onCancelGenerate,
            onOpenPlayer: onOpenPlayer,
            onRecheckPackage: onRecheckPackage,
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
                  title: entry.title,
                ),
              )
            else
              _HeroCaption(
                ink: ink,
                sourceName: sourceDisplayName(
                  AppLocalizations.of(context),
                  source,
                ),
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

/// The package line for every status that is not "available" or "checking":
/// checked-and-none, never-asked, and could-not-ask each get their own words.
class _PackageStatusRow extends StatelessWidget {
  const _PackageStatusRow({required this.status});

  final PackageStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (status) {
      PackageStatus.undetermined => (
        Icons.help_outline,
        l.text('discoveryPackageUndetermined'),
      ),
      PackageStatus.unknown => (
        Icons.inventory_2_outlined,
        l.text('discoveryPackageUnknown'),
      ),
      _ => (Icons.inventory_2_outlined, l.text('discoveryPackageNone')),
    };
    return Row(
      children: [
        Icon(
          icon,
          size: ListenIconSize.control,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: ListenSpacing.gap8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _UserJourneyActionsCard extends StatelessWidget {
  const _UserJourneyActionsCard({
    required this.downloadState,
    required this.downloadProgress,
    this.downloadFailure,
    required this.packageStatus,
    required this.generationStatus,
    required this.generatorPhase,
    required this.generationFailure,
    this.generatorState = ContentGeneratorState.ready,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onGenerate,
    required this.onCancelGenerate,
    required this.onOpenPlayer,
    required this.onRecheckPackage,
  });

  final DownloadState downloadState;

  /// Null while the total is unknown; renders indeterminate.
  final double? downloadProgress;
  final ApiFailure? downloadFailure;
  final PackageStatus packageStatus;
  final ContentGenerationStatus generationStatus;
  final String? generatorPhase;
  final ApiFailure? generationFailure;

  /// Which piece of the toolchain is missing, so the unavailable row names
  /// the one thing to fix rather than saying "not configured".
  final ContentGeneratorState generatorState;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onGenerate;
  final VoidCallback onCancelGenerate;
  final VoidCallback? onOpenPlayer;
  final VoidCallback onRecheckPackage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final isDownloaded = downloadState == DownloadState.done;
    final isDownloading = downloadState == DownloadState.downloading;
    final downloadFailed = downloadState == DownloadState.failed;

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
                isDownloaded
                    ? Icons.check_circle
                    : downloadFailed
                    ? Icons.error_outline
                    : Icons.download,
                size: ListenIconSize.inline,
                color: isDownloaded
                    ? scheme.primary
                    : downloadFailed
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  isDownloaded
                      ? l.text('discoveryDownloaded')
                      : downloadFailed
                      ? l.text('discoveryDownloadFailed')
                      : isDownloading
                      // With no length there is no percentage, so the token is
                      // removed rather than filled with a guess.
                      ? l.text('discoveryDownloading').replaceFirst(
                          '{percent}',
                          switch (downloadProgress) {
                            final double fraction =>
                              '${(fraction * 100).round()}%',
                            null => '',
                          },
                        ).trim()
                      : l.text('discoveryDownload'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: downloadFailed ? scheme.error : null,
                    fontWeight: isDownloading || !isDownloaded
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          // The panel is where the reason lives; the card only had room to say
          // that it failed.
          if (downloadFailure case final failure? when downloadFailed) ...[
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              _failureDetail(l, failure),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.error),
            ),
          ],
          if (isDownloading) ...[
            const SizedBox(height: ListenSpacing.gap6),
            // Null renders the indeterminate animation: running, length
            // unknown. A bar held at 0% reads as a hang.
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
              icon: Icon(
                downloadFailed ? Icons.refresh : Icons.download,
                size: ListenIconSize.control,
              ),
              label: Text(
                l.text(
                  downloadFailed
                      ? 'discoveryDownloadFailedRetry'
                      : 'discoveryDownload',
                ),
              ),
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
            _PackageStatusRow(status: packageStatus),
            const SizedBox(height: ListenSpacing.gap8),

            // Only a *checked* "no package" earns the generate flow. Under
            // unknown or undetermined we have not been told whether one
            // already exists, so the honest next step is to ask again.
            if (packageStatus == PackageStatus.notAvailable) ...[
              // No generator on this machine is an absent capability, not a
              // failed run. It gets a plain unavailable row and a disabled
              // button — disabled rather than hidden, so the feature is still
              // discoverable — and never a retry, which could only fail again.
              if (generationStatus == ContentGenerationStatus.unavailable) ...[
                Row(
                  children: [
                    Icon(
                      Icons.block_outlined,
                      size: ListenIconSize.inline,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: ListenSpacing.gap6),
                    Expanded(
                      child: Text(
                        l.text(_generatorUnavailableKey(generatorState)),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ListenSpacing.gap4),
                Text(
                  l.text('${_generatorUnavailableKey(generatorState)}Hint'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: ListenIconSize.control,
                  ),
                  label: Text(l.text('discoveryGenerate')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
              ] else ...[
                if (generationStatus == ContentGenerationStatus.failed) ...[
                  Text(
                    l.text('discoveryGenerateFailed'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                  if (generationFailure case final failure?) ...[
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      _failureDetail(l, failure),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.error),
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
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: ListenIconSize.control,
                  ),
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
                    l.text('discoveryGenerateNeedsDownload'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ] else
              OutlinedButton.icon(
                onPressed: onRecheckPackage,
                icon: const Icon(Icons.refresh, size: ListenIconSize.control),
                label: Text(l.text('discoveryCheckPackageAgain')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 36),
                ),
              ),
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
    onRecheckPackage: _noop,
  ),
  width: 380,
  height: 720,
);

/// The panel on a machine with no `listen-gen`: media downloaded, package
/// checked and absent, and generation simply not available here.
///
/// It exists because the difference between this and the `failed` state is
/// the whole point of the fix — a grey unavailable row with a disabled button
/// and a sentence naming the real next step, versus a red failure with a retry
/// that can never succeed. Which one is on screen is obvious in a picture and
/// invisible in a test name.
@Preview(
  name: 'Detail panel · no generator',
  group: 'Discovery',
  size: Size(380, 720),
)
Widget discoveryDetailPanelNoGeneratorPreview() => discoveryPreviewShell(
  DiscoveryDetailPanel(
    entry: const MediaEntry(
      id: 'i-preview-nogen',
      sourceId: 'c-preview',
      title: 'The fastest way to board a plane, according to mathematics',
      description: 'A queueing-theory look at why boarding takes so long.',
      durationMs: 357000,
      language: 'English',
      publishedOn: '2026-07-28',
      thumbnailUrl: null,
      viewCount: 142000,
      hasPackage: false,
    ),
    source: const MediaSource(
      id: 'c-preview',
      name: 'TED-Ed',
      language: 'English',
      description: '',
      cover: ChannelCoverTone.rose,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    downloadState: DownloadState.done,
    downloadProgress: 1,
    packageStatus: PackageStatus.notAvailable,
    generationStatus: ContentGenerationStatus.unavailable,
    generatorPhase: null,
    generationFailure: null,
    onDownload: _noop,
    onCancelDownload: _noop,
    onOpenPlayer: _noop,
    onViewPackage: _noop,
    onGenerate: _noop,
    onCancelGenerate: _noop,
    onRecheckPackage: _noop,
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

/// Sentences for the generator codes we know about.
///
/// A raw code like `generator_not_configured` is honest but useless: it tells
/// the user nothing about what happened or what to do. Unknown codes still
/// fall through to the code itself — losing diagnosability would be the worse
/// trade — but every code the generator can actually emit is named here, and
/// `generation_failure_copy_test.dart` fails when one is added without a
/// sentence.
const _generatorFailureKeys = <String, String>{
  'generator_not_configured': 'genFailureNotConfigured',
  'generator_start_failed': 'genFailureStartFailed',
  'generator_protocol_invalid': 'genFailureProtocolInvalid',
  'generator_output_invalid': 'genFailureOutputInvalid',
  'generator_terminal_missing': 'genFailureTerminalMissing',
  'generator_failed': 'genFailureFailed',
  'generator_output_missing': 'genFailureOutputMissing',
  'generator_package_digest_mismatch': 'genFailureDigestMismatch',
};

String _failureDetail(AppLocalizations l, ApiFailure failure) {
  final code = failure.code == null || failure.code!.isEmpty
      ? 'generator_failed'
      : failure.code!;
  final key = _generatorFailureKeys[code];
  // The generator's own stderr is a diagnostic, not a user sentence, so it is
  // never concatenated into the localized line.
  if (key != null) return l.text(key);
  final message = failure.message;
  if (message == null || message.isEmpty) return code;
  return '$code: ${message.length > 220 ? '${message.substring(0, 220)}…' : message}';
}

/// The copy key for each missing piece. Each names one thing to fix; a single
/// "not configured" sentence would be honest about the state and useless
/// about the cause.
String _generatorUnavailableKey(ContentGeneratorState state) => switch (state) {
  ContentGeneratorState.modelMissing => 'discoveryGeneratorNoModel',
  ContentGeneratorState.whisperMissing => 'discoveryGeneratorNoWhisper',
  ContentGeneratorState.generatorMissing ||
  ContentGeneratorState.ready => 'discoveryGeneratorUnavailable',
};
