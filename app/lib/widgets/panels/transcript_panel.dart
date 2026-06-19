import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';
import 'timeline_resource_summary_panel.dart';

class TranscriptPanel extends StatelessWidget {
  const TranscriptPanel({
    super.key,
    required this.track,
    required this.scrollController,
    required this.itemExtent,
    required this.currentCue,
    required this.wordProfiles,
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
    required this.timelineDocument,
    required this.wordTimelineSummaries,
    required this.timelineResourceError,
    required this.onImportLLTimeline,
    required this.onRefreshTimelineResource,
    required this.onActivateWordTimeline,
    required this.onManualReviewTimeline,
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final double itemExtent;
  final Cue? currentCue;
  final Map<String, Map<String, dynamic>> wordProfiles;
  final bool showStyles;
  final Color baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final LLTimelineDocument? timelineDocument;
  final List<WordTimelineSummary> wordTimelineSummaries;
  final String? timelineResourceError;
  final Future<void> Function() onImportLLTimeline;
  final Future<void> Function() onRefreshTimelineResource;
  final Future<void> Function(String timelineId) onActivateWordTimeline;
  final Future<void> Function() onManualReviewTimeline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xff151a20),
      child: Column(
        children: [
          TimelineResourceSummaryPanel(
            document: timelineDocument,
            summaries: wordTimelineSummaries,
            error: timelineResourceError,
            onImport: onImportLLTimeline,
            onRefresh: onRefreshTimelineResource,
            onActivate: onActivateWordTimeline,
            onManualReview: onManualReviewTimeline,
          ),
          Expanded(
            child: track == null
                ? Center(child: Text(l.text('importSubtitleHint')))
                : ListView.builder(
                    controller: scrollController,
                    itemExtent: itemExtent,
                    itemCount: track!.cues.length,
                    itemBuilder: (context, index) {
                      final cue = track!.cues[index];
                      final selected = cue.id == currentCue?.id;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
                        leading: Text(formatDuration(cue.start)),
                        title: TokenLine(
                          cue: cue,
                          profiles: wordProfiles,
                          showStyles: showStyles,
                          baseColor: baseColor,
                          onWord: onWord,
                        ),
                        onTap: () => onSeekCue(cue),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
