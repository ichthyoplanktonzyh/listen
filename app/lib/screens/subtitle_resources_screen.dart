import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../controllers/subtitle_controller.dart';
import '../localization.dart';
import '../models/timeline.dart';
import '../widgets/panels/subtitle_resource_manager_panel.dart';

class SubtitleResourcesScreen extends StatefulWidget {
  const SubtitleResourcesScreen({
    super.key,
    required this.playerController,
    required this.subtitleController,
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

  final PlayerController playerController;
  final SubtitleController subtitleController;
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
  State<SubtitleResourcesScreen> createState() =>
      _SubtitleResourcesScreenState();
}

class _SubtitleResourcesScreenState extends State<SubtitleResourcesScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.onRefreshResources());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.playerController,
      widget.subtitleController,
    ]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).text('subtitleResources')),
      ),
      body: SubtitleResourceManagerPanel(
        mediaId: widget.playerController.mediaId,
        resources: widget.subtitleController.subtitleResources,
        capabilities: widget.subtitleController.subtitleResourceCapabilities,
        activeTrack: widget.subtitleController.primaryTrack,
        timelineDocument: widget.subtitleController.llTimelineDocument,
        wordTimelineSummaries: widget.subtitleController.wordTimelineSummaries,
        phoneTimelineSummaries:
            widget.subtitleController.phoneTimelineSummaries,
        chunkTimelineSummaries:
            widget.subtitleController.chunkTimelineSummaries,
        activeWordTimingCount: _activeWordTimingCount(),
        timelineResourceError: widget.subtitleController.timelineResourceError,
        onImportSubtitle: widget.onImportSubtitle,
        onImportLLTimeline: widget.onImportLLTimeline,
        onRefreshResources: widget.onRefreshResources,
        onActivateSubtitle: widget.onActivateSubtitle,
        onArchiveSubtitle: widget.onArchiveSubtitle,
        onRestoreSubtitle: widget.onRestoreSubtitle,
        onDeleteSubtitle: widget.onDeleteSubtitle,
        onExportSubtitle: widget.onExportSubtitle,
        onLanguageChanged: widget.onLanguageChanged,
        availableLanguages: widget.availableLanguages,
        onExportLLTimeline: widget.onExportLLTimeline,
        onActivateWordTimeline: widget.onActivateWordTimeline,
        onManualReviewTimeline: widget.onManualReviewTimeline,
        onActivatePhoneTimeline: widget.onActivatePhoneTimeline,
        onArchivePhoneTimeline: widget.onArchivePhoneTimeline,
        onDeletePhoneTimeline: widget.onDeletePhoneTimeline,
        onGenerateChunkTimeline: widget.onGenerateChunkTimeline,
        onActivateChunkTimeline: widget.onActivateChunkTimeline,
        onArchiveChunkTimeline: widget.onArchiveChunkTimeline,
        onDeleteChunkTimeline: widget.onDeleteChunkTimeline,
      ),
    ),
  );

  int _activeWordTimingCount() => widget
      .subtitleController
      .timingsBySentence
      .values
      .fold<int>(0, (total, timings) => total + timings.length);
}
