import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import 'timeline_resource_summary_panel.dart';

class SubtitleResourceManagerPanel extends StatelessWidget {
  const SubtitleResourceManagerPanel({
    super.key,
    required this.mediaId,
    required this.resources,
    required this.activeTrack,
    required this.timelineDocument,
    required this.wordTimelineSummaries,
    required this.timelineResourceError,
    required this.onImportSubtitle,
    required this.onImportLLTimeline,
    required this.onRefreshResources,
    required this.onActivateSubtitle,
    required this.onActivateWordTimeline,
    required this.onManualReviewTimeline,
  });

  final String? mediaId;
  final List<SubtitleTrack> resources;
  final SubtitleTrack? activeTrack;
  final LLTimelineDocument? timelineDocument;
  final List<WordTimelineSummary> wordTimelineSummaries;
  final String? timelineResourceError;
  final Future<void> Function() onImportSubtitle;
  final Future<void> Function() onImportLLTimeline;
  final Future<void> Function() onRefreshResources;
  final Future<void> Function(SubtitleTrack track) onActivateSubtitle;
  final Future<void> Function(String timelineId) onActivateWordTimeline;
  final Future<void> Function() onManualReviewTimeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xff121820),
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
          Expanded(
            child: mediaId == null
                ? Center(child: Text(l.text('openMediaForSubtitles')))
                : resources.isEmpty
                ? Center(child: Text(l.text('noSubtitleResources')))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: resources.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final resource = resources[index];
                      final active = resource.id == activeTrack?.id;
                      return _SubtitleResourceTile(
                        resource: resource,
                        active: active,
                        onActivate: () => onActivateSubtitle(resource),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xff26313c)),
          TimelineResourceSummaryPanel(
            document: timelineDocument,
            summaries: wordTimelineSummaries,
            error: timelineResourceError,
            onImport: onImportLLTimeline,
            onRefresh: onRefreshResources,
            onActivate: onActivateWordTimeline,
            onManualReview: onManualReviewTimeline,
          ),
        ],
      ),
    );
  }
}

class _SubtitleResourceTile extends StatelessWidget {
  const _SubtitleResourceTile({
    required this.resource,
    required this.active,
    required this.onActivate,
  });

  final SubtitleTrack resource;
  final bool active;
  final Future<void> Function() onActivate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? const Color(0xff18332f) : const Color(0xff171f28),
        border: Border.all(
          color: active ? const Color(0xff38b88f) : const Color(0xff2b3642),
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
              color: active ? const Color(0xff6dd6c3) : const Color(0xff8fa1b3),
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
                      resource.source,
                      '${resource.cues.length} ${l.text('cues')}',
                      resource.id,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
                onPressed: active ? null : onActivate,
              ),
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
