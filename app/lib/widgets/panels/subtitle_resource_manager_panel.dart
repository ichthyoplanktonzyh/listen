import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import 'content_fit_card.dart';
import 'timeline_resource_summary_panel.dart';

class SubtitleResourceManagerPanel extends StatelessWidget {
  const SubtitleResourceManagerPanel({
    super.key,
    required this.mediaId,
    this.contentFit,
    required this.resources,
    required this.capabilities,
    required this.activeTrack,
    required this.timelineDocument,
    required this.wordTimelineSummaries,
    required this.phoneTimelineSummaries,
    required this.chunkTimelineSummaries,
    required this.activeWordTimingCount,
    required this.timelineResourceError,
    required this.onImportSubtitle,
    required this.onImportLLTimeline,
    required this.onRefreshResources,
    required this.onActivateSubtitle,
    required this.onArchiveSubtitle,
    required this.onRestoreSubtitle,
    required this.onDeleteSubtitle,
    required this.onExportSubtitle,
    required this.onLanguageChanged,
    required this.availableLanguages,
    required this.onExportLLTimeline,
    required this.onActivateWordTimeline,
    required this.onManualReviewTimeline,
    required this.onActivatePhoneTimeline,
    required this.onArchivePhoneTimeline,
    required this.onDeletePhoneTimeline,
    required this.onGenerateChunkTimeline,
    required this.onActivateChunkTimeline,
    required this.onArchiveChunkTimeline,
    required this.onDeleteChunkTimeline,
  });

  final String? mediaId;
  final ContentDifficultyProfile? contentFit;
  final List<SubtitleTrack> resources;
  final Map<String, SubtitleResourceCapabilities> capabilities;
  final SubtitleTrack? activeTrack;
  final LLTimelineDocument? timelineDocument;
  final List<WordTimelineSummary> wordTimelineSummaries;
  final List<PhoneTimelineSummary> phoneTimelineSummaries;
  final List<ChunkTimelineSummary> chunkTimelineSummaries;
  final int activeWordTimingCount;
  final String? timelineResourceError;
  final Future<void> Function() onImportSubtitle;
  final Future<void> Function() onImportLLTimeline;
  final Future<void> Function() onRefreshResources;
  final Future<void> Function(SubtitleTrack track) onActivateSubtitle;
  final Future<void> Function(SubtitleTrack track) onArchiveSubtitle;
  final Future<void> Function(SubtitleTrack track) onRestoreSubtitle;
  final Future<void> Function(SubtitleTrack track) onDeleteSubtitle;
  final Future<void> Function(SubtitleTrack track) onExportSubtitle;
  final Future<void> Function(SubtitleTrack track, String language)
  onLanguageChanged;
  final List<String> availableLanguages;
  final Future<void> Function(SubtitleTrack track) onExportLLTimeline;
  final Future<void> Function(String timelineId) onActivateWordTimeline;
  final Future<void> Function() onManualReviewTimeline;
  final Future<void> Function(String timelineId) onActivatePhoneTimeline;
  final Future<void> Function(String timelineId) onArchivePhoneTimeline;
  final Future<void> Function(String timelineId) onDeletePhoneTimeline;
  final Future<void> Function() onGenerateChunkTimeline;
  final Future<void> Function(String timelineId) onActivateChunkTimeline;
  final Future<void> Function(String timelineId) onArchiveChunkTimeline;
  final Future<void> Function(String timelineId) onDeleteChunkTimeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final resourceWordTimingCount = activeTrack == null
        ? 0
        : capabilities[activeTrack!.id]?.wordTimingCount ?? 0;
    final visibleWordTimingCount = activeWordTimingCount > 0
        ? activeWordTimingCount
        : resourceWordTimingCount;
    return Material(
      color: ListenColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.subtitles_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.text('subtitleResources'),
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: l.text('importSubtitle'),
                  child: IconButton(
                    icon: const Icon(Icons.note_add_outlined),
                    onPressed: mediaId == null ? null : onImportSubtitle,
                  ),
                ),
                Tooltip(
                  message: l.text('importLLTimeline'),
                  child: IconButton(
                    icon: const Icon(Icons.file_upload_outlined),
                    onPressed: mediaId == null ? null : onImportLLTimeline,
                  ),
                ),
                Tooltip(
                  message: l.text('refresh'),
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: mediaId == null ? null : onRefreshResources,
                  ),
                ),
              ],
            ),
          ),
          if (contentFit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ContentFitCard(profile: contentFit!),
            ),
          Expanded(
            child: mediaId == null
                ? Center(child: Text(l.text('openMediaForSubtitles')))
                : resources.isEmpty
                ? Center(child: Text(l.text('noSubtitleResources')))
                : _ResizableResourceBody(
                    subtitleList: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: resources.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final resource = resources[index];
                        final active = resource.id == activeTrack?.id;
                        return _SubtitleResourceTile(
                          resource: resource,
                          capabilities:
                              capabilities[resource.id] ??
                              SubtitleResourceCapabilities.fromCounts(
                                sentenceCount: resource.cues.length,
                                wordTimingCount: 0,
                                chunkCount: 0,
                                phoneCount: 0,
                              ),
                          active: active,
                          onActivate: () => onActivateSubtitle(resource),
                          onArchive: () => onArchiveSubtitle(resource),
                          onRestore: () => onRestoreSubtitle(resource),
                          onDelete: () => onDeleteSubtitle(resource),
                          onExport: () => onExportSubtitle(resource),
                          onLanguageChanged: (language) =>
                              onLanguageChanged(resource, language),
                          availableLanguages: availableLanguages,
                        );
                      },
                    ),
                    timelineSummary: TimelineResourceSummaryPanel(
                      activeTrack: activeTrack,
                      document: timelineDocument,
                      summaries: wordTimelineSummaries,
                      phoneSummaries: phoneTimelineSummaries,
                      chunkSummaries: chunkTimelineSummaries,
                      activeWordTimingCount: visibleWordTimingCount,
                      error: timelineResourceError,
                      onImport: onImportLLTimeline,
                      onRefresh: onRefreshResources,
                      onActivate: onActivateWordTimeline,
                      onManualReview: onManualReviewTimeline,
                      onActivatePhoneTimeline: onActivatePhoneTimeline,
                      onArchivePhoneTimeline: onArchivePhoneTimeline,
                      onDeletePhoneTimeline: onDeletePhoneTimeline,
                      onGenerateChunkTimeline: onGenerateChunkTimeline,
                      onActivateChunkTimeline: onActivateChunkTimeline,
                      onArchiveChunkTimeline: onArchiveChunkTimeline,
                      onDeleteChunkTimeline: onDeleteChunkTimeline,
                      onExportLLTimeline: activeTrack == null
                          ? null
                          : () => onExportLLTimeline(activeTrack!),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResizableResourceBody extends StatefulWidget {
  const _ResizableResourceBody({
    required this.subtitleList,
    required this.timelineSummary,
  });

  final Widget subtitleList;
  final Widget timelineSummary;

  @override
  State<_ResizableResourceBody> createState() => _ResizableResourceBodyState();
}

class _ResizableResourceBodyState extends State<_ResizableResourceBody> {
  static const _splitterHeight = 11.0;

  double _subtitleFraction = 0.34;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final totalHeight = constraints.maxHeight;
      if (!totalHeight.isFinite || totalHeight <= _splitterHeight) {
        return Column(
          children: [
            Expanded(child: widget.subtitleList),
            _ResourceSplitter(onDrag: (_) {}),
            Expanded(child: widget.timelineSummary),
          ],
        );
      }

      final bodyHeight = totalHeight - _splitterHeight;
      final canHonorMinimums = bodyHeight >= 340;
      final subtitleHeight = canHonorMinimums
          ? _clampHeight(bodyHeight * _subtitleFraction, 118, bodyHeight - 220)
          : _clampHeight(bodyHeight * 0.30, 54, bodyHeight * 0.45);
      final timelineHeight = (bodyHeight - subtitleHeight).clamp(
        0.0,
        double.infinity,
      );

      return Column(
        children: [
          SizedBox(
            key: const Key('subtitle-resource-list-pane'),
            height: subtitleHeight,
            child: widget.subtitleList,
          ),
          _ResourceSplitter(
            onDrag: (delta) {
              if (bodyHeight <= 0) return;
              setState(() {
                final nextHeight = subtitleHeight + delta;
                _subtitleFraction = (nextHeight / bodyHeight).clamp(0.18, 0.72);
              });
            },
          ),
          SizedBox(
            key: const Key('timeline-resource-pane'),
            height: timelineHeight,
            child: widget.timelineSummary,
          ),
        ],
      );
    },
  );

  double _clampHeight(double value, double minHeight, double maxHeight) {
    final normalizedMax = maxHeight < minHeight ? minHeight : maxHeight;
    return value.clamp(minHeight, normalizedMax).toDouble();
  }
}

class _ResourceSplitter extends StatelessWidget {
  const _ResourceSplitter({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Resize subtitle and timeline resources',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        key: const Key('subtitle-resource-splitter'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: _ResizableResourceBodyState._splitterHeight,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ListenColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox(width: 42, height: 2),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SubtitleResourceTile extends StatelessWidget {
  const _SubtitleResourceTile({
    required this.resource,
    required this.capabilities,
    required this.active,
    required this.onActivate,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.onExport,
    required this.onLanguageChanged,
    required this.availableLanguages,
  });

  final SubtitleTrack resource;
  final SubtitleResourceCapabilities capabilities;
  final bool active;
  final Future<void> Function() onActivate;
  final Future<void> Function() onArchive;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;
  final Future<void> Function() onExport;
  final Future<void> Function(String language) onLanguageChanged;
  final List<String> availableLanguages;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? ListenColors.selected : ListenColors.fog,
        border: Border.all(
          color: active ? ListenColors.primary : ListenColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle : Icons.subtitles_outlined,
              size: 18,
              color: active ? ListenColors.primary : ListenColors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _resourceTitle(resource),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      active
                          ? l.text('activeSubtitle')
                          : resource.archived
                          ? l.text('resourceArchived')
                          : l.text('resourceReady'),
                      '${capabilities.sentenceCount} ${l.text('cues')}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.text('resourceLearningCapabilities'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ListenColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _LanguageChip(
                        language: resource.language,
                        availableLanguages: availableLanguages,
                        onChanged: onLanguageChanged,
                      ),
                      _CapabilityChip(
                        label: l.text('capabilitySubtitles'),
                        stateLabel: capabilities.sentenceTiming
                            ? l.text('capabilityStateAvailable')
                            : l.text('capabilityStateUnavailable'),
                        active: capabilities.sentenceTiming,
                        count: capabilities.sentenceCount,
                        countLabel: l.text('cues'),
                      ),
                      _CapabilityChip(
                        label: l.text('capabilityWordSync'),
                        stateLabel: capabilities.wordTiming
                            ? l.text('capabilityStateAvailable')
                            : l.text('capabilityStateUnavailable'),
                        active: capabilities.wordTiming,
                        count: capabilities.wordTimingCount,
                        countLabel: l.text('words'),
                      ),
                      _CapabilityChip(
                        label: l.text('capabilityChunkReplay'),
                        stateLabel: capabilities.chunkTiming
                            ? l.text('capabilityStateAvailable')
                            : l.text('capabilityStateUnavailable'),
                        active: capabilities.chunkTiming,
                        count: capabilities.chunkCount,
                        countLabel: l.text('chunks'),
                      ),
                      _CapabilityChip(
                        label: l.text('capabilityPhoneEvidence'),
                        stateLabel: capabilities.phoneTiming
                            ? l.text('capabilityStateAvailable')
                            : l.text('capabilityStateUnavailable'),
                        active: capabilities.phoneTiming,
                        count: capabilities.phoneCount,
                        countLabel: l.text('phones'),
                      ),
                      _CapabilityChip(
                        label: l.text('capabilityListeningStructure'),
                        stateLabel: active
                            ? l.text('resourceTimelineDetailsBelow')
                            : l.text('resourceActivateToInspect'),
                        active: active,
                      ),
                      if (capabilities.error != null)
                        Tooltip(
                          message: capabilities.error!,
                          child: _CapabilityChip(
                            label: l.text('resourcePartial'),
                            stateLabel: l.text('capabilityStateDegraded'),
                            active: false,
                          ),
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
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        title: Text(
                          l.text('technicalDetails'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: ListenColors.muted),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              [
                                resource.source,
                                resource.status,
                                resource.id,
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: active
                  ? l.text('activeSubtitle')
                  : l.text('activateSubtitle'),
              child: IconButton(
                icon: Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.play_circle_outline,
                ),
                onPressed: active || resource.archived ? null : onActivate,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: l.text('resourceActions'),
              onSelected: (value) {
                switch (value) {
                  case 'export':
                    onExport();
                    break;
                  case 'archive':
                    onArchive();
                    break;
                  case 'restore':
                    onRestore();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'export',
                  child: Text(l.text('exportSubtitle')),
                ),
                if (resource.archived)
                  PopupMenuItem(
                    value: 'restore',
                    child: Text(l.text('restoreResource')),
                  )
                else
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(l.text('archiveResource')),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l.text('deleteResource')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _resourceTitle(SubtitleTrack resource) {
    final first = resource.cues.isEmpty ? null : resource.cues.first.text;
    if (first == null || first.trim().isEmpty) return resource.source;
    return first.trim();
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.label,
    required this.stateLabel,
    required this.active,
    this.count,
    this.countLabel,
  });

  final String label;
  final String stateLabel;
  final bool active;
  final int? count;
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    final color = active ? ListenColors.primary : ListenColors.muted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? ListenColors.selected : ListenColors.fog,
        border: Border.all(
          color: active ? ListenColors.primary : ListenColors.border,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          _text(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _text() {
    final countPart = count == null
        ? null
        : countLabel == null
        ? '$count'
        : '$count $countLabel';
    return [label, stateLabel, ?countPart].join(' · ');
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.availableLanguages,
    required this.onChanged,
  });

  final String? language;
  final List<String> availableLanguages;
  final Future<void> Function(String language) onChanged;

  static const _displayNames = {'en': 'English', 'zh': '中文', 'ja': '日本語'};

  @override
  Widget build(BuildContext context) {
    final label = language ?? '?';
    return PopupMenuButton<String>(
      tooltip: 'Language',
      onSelected: onChanged,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final code in availableLanguages)
          PopupMenuItem(
            value: code,
            child: Text(
              '${_displayNames[code] ?? code} ($code)',
              style: TextStyle(
                fontWeight: code == language
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ListenColors.infoSurface,
          border: Border.all(color: ListenColors.info),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 12, color: ListenColors.info),
              const SizedBox(width: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ListenColors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
