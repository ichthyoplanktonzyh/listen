import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../utils/format_duration.dart';

class TimelineResourceSummaryPanel extends StatelessWidget {
  const TimelineResourceSummaryPanel({
    super.key,
    required this.document,
    required this.summaries,
    required this.phoneSummaries,
    required this.chunkSummaries,
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

  final LLTimelineDocument? document;
  final List<WordTimelineSummary> summaries;
  final List<PhoneTimelineSummary> phoneSummaries;
  final List<ChunkTimelineSummary> chunkSummaries;
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
    final hasResource =
        document?.importedResource == true ||
        summaries.isNotEmpty ||
        phoneSummaries.isNotEmpty ||
        chunkSummaries.isNotEmpty;
    final artifacts = document?.artifacts ?? const <LLTimelineArtifact>[];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xff10151b),
        border: Border(bottom: BorderSide(color: Color(0xff26313c))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, size: 18),
                const SizedBox(width: 8),
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
            const SizedBox(height: 8),
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
                      ? const Color(0xff38b88f)
                      : const Color(0xff8fa1b3),
                ),
                if (document != null)
                  _Chip(
                    icon: Icons.memory,
                    label:
                        '${document!.metadata.generatorId} ${document!.metadata.generatorVersion}',
                    color: const Color(0xff6dd6c3),
                  ),
                if (document?.metadata.humanReviewed == true ||
                    active?.humanReviewed == true)
                  _Chip(
                    icon: Icons.verified_user_outlined,
                    label: l.text('humanReviewed'),
                    color: const Color(0xffc9d96b),
                  ),
                _Chip(
                  icon: _productionReady(artifacts)
                      ? Icons.fact_check_outlined
                      : Icons.pending_actions_outlined,
                  label: _productionReady(artifacts)
                      ? l.text('productionReportReady')
                      : l.text('productionReportMissing'),
                  color: _productionReady(artifacts)
                      ? const Color(0xff38b88f)
                      : const Color(0xff8fa1b3),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            _ActiveTimelineLine(active: active),
            const SizedBox(height: 6),
            _ActivePhoneLine(active: activePhone),
            const SizedBox(height: 6),
            _ActiveChunkLine(active: activeChunk),
            const SizedBox(height: 8),
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
                  onPressed: active == null ? null : onGenerateChunkTimeline,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(l.text('exportLLTimelineJson')),
                  onPressed: hasResource ? onExportLLTimeline : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => _PhoneCandidateTile(
                        summary: phoneSummaries[index],
                        onActivate: onActivatePhoneTimeline,
                        onArchive: onArchivePhoneTimeline,
                        onDelete: onDeletePhoneTimeline,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
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
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => _ChunkCandidateTile(
                        summary: chunkSummaries[index],
                        onActivate: onActivateChunkTimeline,
                        onArchive: onArchiveChunkTimeline,
                        onDelete: onDeleteChunkTimeline,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
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
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => _CandidateTile(
                        summary: summaries[index],
                        onActivate: onActivate,
                      ),
                    ),
            ),
            if (artifacts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
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
                            ? const Color(0xffd89a4a)
                            : const Color(0xff9eb7ff),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _productionReady(List<LLTimelineArtifact> artifacts) =>
      artifacts.any((value) => value.kind.contains('production_report'));
}

class _ActiveTimelineLine extends StatelessWidget {
  const _ActiveTimelineLine({required this.active});

  final WordTimelineSummary? active;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = active == null
        ? l.text('activeTimelineLegacy')
        : '${active!.algorithmId} ${active!.algorithmVersion} · '
              '${active!.wordCount} ${l.text('words')} · '
              '${active!.timingSources.join(', ')}';
    return Row(
      children: [
        Icon(
          active == null ? Icons.history : Icons.radio_button_checked,
          size: 16,
          color: active == null
              ? const Color(0xff8fa1b3)
              : const Color(0xff6dd6c3),
        ),
        const SizedBox(width: 6),
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
          size: 16,
          color: active == null
              ? const Color(0xff8fa1b3)
              : const Color(0xff6dd6c3),
        ),
        const SizedBox(width: 6),
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
          size: 16,
          color: active == null
              ? const Color(0xff8fa1b3)
              : const Color(0xff6dd6c3),
        ),
        const SizedBox(width: 6),
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
              ? const Color(0xff18332f)
              : const Color(0xff171f28),
          border: Border.all(
            color: summary.isActive
                ? const Color(0xff38b88f)
                : const Color(0xff2b3642),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                summary.isActive
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: summary.isActive
                    ? const Color(0xff6dd6c3)
                    : const Color(0xff8fa1b3),
              ),
              const SizedBox(width: 8),
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
                    const SizedBox(height: 3),
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
              ? const Color(0xff18332f)
              : const Color(0xff171f28),
          border: Border.all(
            color: summary.isActive
                ? const Color(0xff38b88f)
                : const Color(0xff2b3642),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                summary.isActive ? Icons.check_circle : Icons.graphic_eq,
                size: 18,
                color: summary.isActive
                    ? const Color(0xff6dd6c3)
                    : const Color(0xff8fa1b3),
              ),
              const SizedBox(width: 8),
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
                    const SizedBox(height: 3),
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
              ? const Color(0xff18332f)
              : const Color(0xff171f28),
          border: Border.all(
            color: summary.isActive
                ? const Color(0xff38b88f)
                : const Color(0xff2b3642),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                summary.isActive ? Icons.check_circle : Icons.grid_view,
                size: 18,
                color: summary.isActive
                    ? const Color(0xff6dd6c3)
                    : const Color(0xff8fa1b3),
              ),
              const SizedBox(width: 8),
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
                    const SizedBox(height: 3),
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
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
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
