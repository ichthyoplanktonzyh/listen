import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/capability_readiness.dart';
import '../../models/timeline.dart';
import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';

class TimelineResourceSummaryPanel extends StatelessWidget {
  const TimelineResourceSummaryPanel({
    super.key,
    required this.activeTrack,
    required this.document,
    required this.summaries,
    required this.phoneSummaries,
    required this.chunkSummaries,
    required this.activeWordTimingCount,
    required this.error,
    required this.onImport,
    required this.onRefresh,
    required this.onActivate,
    required this.onManualReview,
    required this.onActivatePhoneTimeline,
    required this.onArchivePhoneTimeline,
    required this.onDeletePhoneTimeline,
    required this.onGenerateChunkTimeline,
    required this.onActivateChunkTimeline,
    required this.onArchiveChunkTimeline,
    required this.onDeleteChunkTimeline,
    required this.onExportLLTimeline,
  });

  final SubtitleTrack? activeTrack;
  final LLTimelineDocument? document;
  final List<WordTimelineSummary> summaries;
  final List<PhoneTimelineSummary> phoneSummaries;
  final List<ChunkTimelineSummary> chunkSummaries;
  final int activeWordTimingCount;
  final String? error;
  final Future<void> Function() onImport;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String timelineId) onActivate;
  final Future<void> Function() onManualReview;
  final Future<void> Function(String timelineId) onActivatePhoneTimeline;
  final Future<void> Function(String timelineId) onArchivePhoneTimeline;
  final Future<void> Function(String timelineId) onDeletePhoneTimeline;
  final Future<void> Function() onGenerateChunkTimeline;
  final Future<void> Function(String timelineId) onActivateChunkTimeline;
  final Future<void> Function(String timelineId) onArchiveChunkTimeline;
  final Future<void> Function(String timelineId) onDeleteChunkTimeline;
  final Future<void> Function()? onExportLLTimeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = summaries.where((value) => value.isActive).firstOrNull;
    final activePhone = phoneSummaries
        .where((value) => value.isActive)
        .firstOrNull;
    final activeChunk = chunkSummaries
        .where((value) => value.isActive)
        .firstOrNull;
    final readiness = CapabilityReadinessSnapshot.fromResources(
      activeTrack: activeTrack,
      document: document,
      wordTimelineSummaries: summaries,
      chunkTimelineSummaries: chunkSummaries,
      phoneTimelineSummaries: phoneSummaries,
      activeWordTimingCount: activeWordTimingCount,
      timelineResourceError: error,
    );
    final hasWordSync = active != null || activeWordTimingCount > 0;
    final hasResource =
        document != null ||
        summaries.isNotEmpty ||
        phoneSummaries.isNotEmpty ||
        chunkSummaries.isNotEmpty;
    final artifacts = document?.artifacts ?? const <LLTimelineArtifact>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: ListenPadding.row,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, size: ListenIconSize.control),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('timelineResource'),
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: l.text('importLLTimeline'),
                  child: IconButton(
                    icon: const Icon(Icons.file_upload_outlined),
                    onPressed: onImport,
                  ),
                ),
                Tooltip(
                  message: l.text('refresh'),
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: onRefresh,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: hasResource ? Icons.check_circle : Icons.info_outline,
                  label: hasResource
                      ? l.text('lltimelinePresent')
                      : l.text('legacyTimelineFallback'),
                  color: hasResource
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                if (document?.metadata.humanReviewed == true ||
                    active?.humanReviewed == true)
                  _Chip(
                    icon: Icons.verified_user_outlined,
                    label: l.text('humanReviewed'),
                    color: Theme.of(context).colorScheme.secondary,
                  ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: ListenSpacing.gap8),
            _CapabilityReadinessGrid(snapshot: readiness),
            const SizedBox(height: ListenSpacing.gap8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(l.text('manualReview')),
                  onPressed: hasResource ? onManualReview : null,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  label: Text(l.text('generateChunks')),
                  onPressed: hasWordSync ? onGenerateChunkTimeline : null,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(l.text('exportLLTimelineJson')),
                  onPressed: hasResource ? onExportLLTimeline : null,
                ),
              ],
            ),
            Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  visualDensity: VisualDensity.compact,
                ),
                child: ExpansionTile(
                  key: const Key('timeline-technical-details'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  leading: const Icon(Icons.tune, size: ListenIconSize.control),
                  title: Text(l.text('technicalDetails')),
                  children: [
                    if (document != null)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Chip(
                            icon: Icons.memory,
                            label:
                                '${document!.metadata.generatorId} ${document!.metadata.generatorVersion}',
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          _Chip(
                            icon: _productionReady(artifacts)
                                ? Icons.fact_check_outlined
                                : Icons.pending_actions_outlined,
                            label: _productionReady(artifacts)
                                ? l.text('productionReportReady')
                                : l.text('productionReportMissing'),
                            color: _productionReady(artifacts)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    const SizedBox(height: ListenSpacing.gap8),
                    _ActiveTimelineLine(
                      active: active,
                      fallbackWordTimingCount: activeWordTimingCount,
                    ),
                    const SizedBox(height: ListenSpacing.gap6),
                    _ActivePhoneLine(active: activePhone),
                    const SizedBox(height: ListenSpacing.gap6),
                    _ActiveChunkLine(active: activeChunk),
                    const SizedBox(height: ListenSpacing.gap8),
                    SizedBox(
                      height: phoneSummaries.isEmpty ? 34 : 74,
                      child: phoneSummaries.isEmpty
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l.text('noPhoneTimelineCandidates'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: phoneSummaries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: ListenSpacing.gap8),
                              itemBuilder: (context, index) =>
                                  _PhoneCandidateTile(
                                    summary: phoneSummaries[index],
                                    onActivate: onActivatePhoneTimeline,
                                    onArchive: onArchivePhoneTimeline,
                                    onDelete: onDeletePhoneTimeline,
                                  ),
                            ),
                    ),
                    const SizedBox(height: ListenSpacing.gap8),
                    SizedBox(
                      height: chunkSummaries.isEmpty ? 34 : 74,
                      child: chunkSummaries.isEmpty
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l.text('noChunkTimelineCandidates'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: chunkSummaries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: ListenSpacing.gap8),
                              itemBuilder: (context, index) =>
                                  _ChunkCandidateTile(
                                    summary: chunkSummaries[index],
                                    onActivate: onActivateChunkTimeline,
                                    onArchive: onArchiveChunkTimeline,
                                    onDelete: onDeleteChunkTimeline,
                                  ),
                            ),
                    ),
                    const SizedBox(height: ListenSpacing.gap8),
                    SizedBox(
                      height: summaries.isEmpty ? 34 : 74,
                      child: summaries.isEmpty
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l.text('noTimelineCandidates'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: summaries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: ListenSpacing.gap8),
                              itemBuilder: (context, index) => _CandidateTile(
                                summary: summaries[index],
                                onActivate: onActivate,
                              ),
                            ),
                    ),
                    if (artifacts.isNotEmpty) ...[
                      const SizedBox(height: ListenSpacing.gap8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: artifacts
                              .map(
                                (artifact) => _Chip(
                                  icon: artifact.kind.contains('failure')
                                      ? Icons.warning_amber_outlined
                                      : Icons.inventory_2_outlined,
                                  label: artifact.providerId == null
                                      ? artifact.kind
                                      : '${artifact.kind} · ${artifact.providerId}',
                                  color: artifact.kind.contains('failure')
                                      ? Theme.of(context).colorScheme.secondary
                                      : Theme.of(context).colorScheme.tertiary,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _productionReady(List<LLTimelineArtifact> artifacts) =>
      artifacts.any((value) => value.kind.contains('production_report'));
}

class _CapabilityReadinessGrid extends StatelessWidget {
  const _CapabilityReadinessGrid({required this.snapshot});

  final CapabilityReadinessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('capabilityReadiness'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: ListenSpacing.gap6),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: snapshot.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: ListenSpacing.gap8),
            itemBuilder: (context, index) =>
                _CapabilityReadinessTile(readiness: snapshot.items[index]),
          ),
        ),
      ],
    );
  }
}

class _CapabilityReadinessTile extends StatelessWidget {
  const _CapabilityReadinessTile({required this.readiness});

  final CapabilityReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _stateColor(Theme.of(context).colorScheme, readiness.state);
    return SizedBox(
      width: 232,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: ListenPadding.row,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _stateIcon(readiness.state),
                    size: ListenIconSize.inline,
                    color: color,
                  ),
                  const SizedBox(width: ListenSpacing.gap6),
                  Expanded(
                    child: Text(
                      l.text(readiness.titleKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap6),
                  _StateBadge(readiness: readiness, color: color),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap4),
              Text(
                _detailText(l, readiness),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailText(AppLocalizations l, CapabilityReadiness readiness) {
    final parts = <String>[l.text(readiness.detailKey)];
    if (readiness.count != null && readiness.countLabelKey != null) {
      parts.add('${readiness.count} ${l.text(readiness.countLabelKey!)}');
    }
    return parts.join(' · ');
  }

  IconData _stateIcon(CapabilityReadinessState state) => switch (state) {
    CapabilityReadinessState.available => Icons.check_circle_outline,
    CapabilityReadinessState.generating => Icons.hourglass_empty,
    CapabilityReadinessState.degraded => Icons.warning_amber_outlined,
    CapabilityReadinessState.unavailable => Icons.info_outline,
    CapabilityReadinessState.unsupported => Icons.block,
    CapabilityReadinessState.stale => Icons.update,
    CapabilityReadinessState.error => Icons.error_outline,
  };

  Color _stateColor(ColorScheme colors, CapabilityReadinessState state) =>
      switch (state) {
        CapabilityReadinessState.available => colors.primary,
        CapabilityReadinessState.generating => colors.tertiary,
        CapabilityReadinessState.degraded => colors.secondary,
        CapabilityReadinessState.unavailable => colors.onSurfaceVariant,
        CapabilityReadinessState.unsupported => colors.disabledForeground,
        CapabilityReadinessState.stale => colors.secondary,
        CapabilityReadinessState.error => colors.error,
      };
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.readiness, required this.color});

  final CapabilityReadiness readiness;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: ListenRadii.pillBorder,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        AppLocalizations.of(context).text(readiness.stateKey),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ActiveTimelineLine extends StatelessWidget {
  const _ActiveTimelineLine({
    required this.active,
    required this.fallbackWordTimingCount,
  });

  final WordTimelineSummary? active;
  final int fallbackWordTimingCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasFallback = fallbackWordTimingCount > 0;
    final text = active == null
        ? hasFallback
              ? '${l.text('activeTimelineGeneratedTiming')} · '
                    '$fallbackWordTimingCount ${l.text('words')}'
              : l.text('activeTimelineLegacy')
        : '${active!.algorithmId} ${active!.algorithmVersion} · '
              '${active!.wordCount} ${l.text('words')} · '
              '${active!.timingSources.join(', ')}';
    return Row(
      children: [
        Icon(
          active == null
              ? hasFallback
                    ? Icons.check_circle_outline
                    : Icons.history
              : Icons.radio_button_checked,
          size: ListenIconSize.inline,
          color: active == null && !hasFallback
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: ListenSpacing.gap6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ActiveChunkLine extends StatelessWidget {
  const _ActiveChunkLine({required this.active});

  final ChunkTimelineSummary? active;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = active == null
        ? l.text('activeChunkTimelineMissing')
        : '${active!.algorithm} · ${active!.chunkCount} ${l.text('chunks')} · ${active!.precision}';
    return Row(
      children: [
        Icon(
          active == null ? Icons.splitscreen_outlined : Icons.grid_view,
          size: ListenIconSize.inline,
          color: active == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: ListenSpacing.gap6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ActivePhoneLine extends StatelessWidget {
  const _ActivePhoneLine({required this.active});

  final PhoneTimelineSummary? active;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = active == null
        ? l.text('activePhoneTimelineMissing')
        : '${active!.providerId} · ${active!.phoneCount} ${l.text('phones')} · ${active!.precision}';
    return Row(
      children: [
        Icon(
          active == null ? Icons.hearing_outlined : Icons.graphic_eq,
          size: ListenIconSize.inline,
          color: active == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: ListenSpacing.gap6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.summary, required this.onActivate});

  final WordTimelineSummary summary;
  final Future<void> Function(String timelineId) onActivate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confidence = summary.averageConfidence == null
        ? null
        : '${(summary.averageConfidence! * 100).round()}%';
    final window = summary.start == null || summary.end == null
        ? null
        : '${formatDuration(summary.start!)}-${formatDuration(summary.end!)}';
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 236, height: 74),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: summary.isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: summary.isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: ListenPadding.row,
          child: Row(
            children: [
              Icon(
                summary.isActive
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: ListenIconSize.control,
                color: summary.isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.algorithmId} ${summary.algorithmVersion}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      [
                        '${summary.wordCount} ${l.text('words')}',
                        ?confidence,
                        ?window,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: summary.isActive
                    ? l.text('activeTimeline')
                    : l.text('activateTimeline'),
                child: IconButton(
                  key: ValueKey('activate-word-timeline-${summary.id}'),
                  icon: Icon(
                    summary.isActive
                        ? Icons.play_circle_fill
                        : Icons.play_circle_outline,
                  ),
                  onPressed: summary.canActivate && !summary.isActive
                      ? () => onActivate(summary.id)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneCandidateTile extends StatelessWidget {
  const _PhoneCandidateTile({
    required this.summary,
    required this.onActivate,
    required this.onArchive,
    required this.onDelete,
  });

  final PhoneTimelineSummary summary;
  final Future<void> Function(String timelineId) onActivate;
  final Future<void> Function(String timelineId) onArchive;
  final Future<void> Function(String timelineId) onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confidence = summary.averageConfidence == null
        ? null
        : '${(summary.averageConfidence! * 100).round()}%';
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 250, height: 74),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: summary.isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: summary.isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: ListenPadding.row,
          child: Row(
            children: [
              Icon(
                summary.isActive ? Icons.check_circle : Icons.graphic_eq,
                size: ListenIconSize.control,
                color: summary.isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.providerId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      [
                        '${summary.phoneCount} ${l.text('phones')}',
                        summary.precision,
                        ?confidence,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l.text('resourceActions'),
                onSelected: (value) {
                  if (value == 'activate') onActivate(summary.id);
                  if (value == 'archive') onArchive(summary.id);
                  if (value == 'delete') onDelete(summary.id);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'activate',
                    enabled: summary.canActivate && !summary.isActive,
                    child: Text(l.text('activateTimeline')),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    enabled: summary.canArchive,
                    child: Text(l.text('archive')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: summary.canDelete,
                    child: Text(l.text('delete')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChunkCandidateTile extends StatelessWidget {
  const _ChunkCandidateTile({
    required this.summary,
    required this.onActivate,
    required this.onArchive,
    required this.onDelete,
  });

  final ChunkTimelineSummary summary;
  final Future<void> Function(String timelineId) onActivate;
  final Future<void> Function(String timelineId) onArchive;
  final Future<void> Function(String timelineId) onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confidence = summary.averageConfidence == null
        ? null
        : '${(summary.averageConfidence! * 100).round()}%';
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 250, height: 74),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: summary.isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: summary.isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: ListenRadii.controlBorder,
        ),
        child: Padding(
          padding: ListenPadding.row,
          child: Row(
            children: [
              Icon(
                summary.isActive ? Icons.check_circle : Icons.grid_view,
                size: ListenIconSize.control,
                color: summary.isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.algorithm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: ListenSpacing.gap2),
                    Text(
                      [
                        '${summary.chunkCount} ${l.text('chunks')}',
                        summary.precision,
                        ?confidence,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: summary.isActive
                    ? l.text('activeTimeline')
                    : l.text('activateTimeline'),
                icon: Icon(
                  summary.isActive
                      ? Icons.play_circle_fill
                      : Icons.play_circle_outline,
                ),
                onPressed: summary.canActivate && !summary.isActive
                    ? () => onActivate(summary.id)
                    : null,
              ),
              PopupMenuButton<String>(
                tooltip: l.text('resourceActions'),
                onSelected: (value) {
                  if (value == 'archive') onArchive(summary.id);
                  if (value == 'delete') onDelete(summary.id);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'archive',
                    enabled: summary.canArchive,
                    child: Text(l.text('archiveResource')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: summary.canDelete,
                    child: Text(l.text('deleteResource')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      border: Border.all(color: color.withValues(alpha: 0.55)),
      borderRadius: ListenRadii.controlBorder,
    ),
    child: Padding(
      padding: ListenPadding.tight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ListenIconSize.inline, color: color),
          const SizedBox(width: ListenSpacing.gap4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
