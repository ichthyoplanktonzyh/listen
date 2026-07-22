import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/reading.dart';
import '../models/practice.dart';
import '../models/semantic_task.dart';
import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
import 'player_controller.dart';
import 'slice_player_controller.dart';
import 'speaking_task_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Content-session and audio-focus orchestration around the Speaking tenant.
/// Durable task rules stay in [SpeakingTaskController].
class SpeakingActionsCoordinator extends ChangeNotifier {
  /// Localization seam; falls back to raw keys when unbound (tests).
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;

  SpeakingActionsCoordinator({
    required this.task,
    required this.player,
    required this.subtitle,
    required this.settings,
    required this.slicePlayer,
    required this.adapter,
    required this.recordingAdapter,
    this.stopAuxiliaryAudio,
  });

  final SpeakingTaskController task;
  final PlayerController player;
  final SubtitleController subtitle;
  final SettingsController settings;
  final SlicePlayerController slicePlayer;
  final DesktopPlayerAdapter adapter;
  final DesktopPlayerAdapter recordingAdapter;
  final Future<void> Function()? stopAuxiliaryAudio;

  SpeakingTaskSource? _source;
  Duration? _returnPosition;
  int _audioGeneration = 0;

  SpeakingTaskSource? get source => _source;
  bool get isOpen => _source != null;

  Future<void> openRetelling(
    LocalApi api, {
    required List<RubricPointView> fixedRubricPoints,
    required Future<void> Function() closeReading,
  }) async {
    final track = subtitle.primaryTrack;
    if (track == null) return;
    final paragraphs = deriveReadingParagraphs(
      track.cues,
    ).where((paragraph) => !paragraph.nonSpeech).toList(growable: false);
    if (paragraphs.isEmpty) return;
    final currentCueId = subtitle.currentPrimaryCue?.id;
    var paragraph = paragraphs.first;
    for (final candidate in paragraphs) {
      if (candidate.sentences.any(
        (sentence) => sentence.cues.any((cue) => cue.id == currentCueId),
      )) {
        paragraph = candidate;
        break;
      }
    }
    final sourceLanguage = settings.resolveLearningLanguage(track.language);
    final cues = _speakingWindow(track.cues, currentCueId, paragraph);
    final first = cues.first;
    final last = cues.last;
    final startMs = subtitle.primaryCursor.mediaStart(first).inMilliseconds;
    final endMs = subtitle.primaryCursor.mediaEnd(last).inMilliseconds;
    if (endMs - startMs < 10000 || endMs - startMs > 60000) {
      player.setStatus(_t('statusSpeakingSegmentLength'));
      return;
    }
    final source = SpeakingTaskSource(
      anchorCueId: first.id,
      mediaId: track.mediaId ?? player.mediaId,
      trackId: track.id,
      startMs: startMs,
      endMs: endMs,
      language: sourceLanguage,
      transcriptSnapshot: cues.map((cue) => cue.text.trim()).join(' '),
    );
    await closeReading();
    await acquireRecordingFocus();
    _returnPosition = player.position;
    _source = source;
    notifyListeners();
    unawaited(
      task.openTask(api, source: source, fixedRubricPoints: fixedRubricPoints),
    );
  }

  Future<void> close(LocalApi? api, {bool restorePosition = true}) async {
    _audioGeneration++;
    await adapter.pause();
    await recordingAdapter.pause();
    await slicePlayer.close();
    await task.closeTask(api);
    final returnPosition = _returnPosition;
    if (restorePosition && returnPosition != null) {
      await adapter.seek(returnPosition);
    }
    _source = null;
    _returnPosition = null;
    notifyListeners();
  }

  Future<void> playSource() async {
    final current = _source;
    if (current == null) return;
    await stopAuxiliaryAudio?.call();
    final generation = ++_audioGeneration;
    await recordingAdapter.pause();
    await slicePlayer.pause();
    await adapter.pause();
    final playbackAdapter = current.sourceMediaPath == null
        ? adapter
        : recordingAdapter;
    if (current.sourceMediaPath != null) {
      await playbackAdapter.open(current.sourceMediaPath!, play: false);
    }
    await playbackAdapter.seek(Duration(milliseconds: current.startMs));
    await playbackAdapter.play();
    await Future<void>.delayed(
      Duration(milliseconds: current.endMs - current.startMs + 80),
    );
    if (generation == _audioGeneration) {
      await playbackAdapter.pause();
    }
  }

  Future<void> openDelayedRetelling(
    LocalApi api, {
    required ReviewQueueEntry entry,
    required String mediaPath,
    required List<RubricPointView> fixedRubricPoints,
    required Future<void> Function() closeReading,
  }) async {
    final startMs = entry.playbackStartMs;
    final endMs = entry.playbackEndMs;
    if (startMs == null || endMs == null || endMs <= startMs) return;
    final anchor = entry.item.anchors.firstOrNull;
    final source = SpeakingTaskSource(
      anchorCueId: anchor?.sentenceId ?? anchor?.id ?? entry.item.id,
      mediaId: entry.item.source.mediaId,
      trackId: entry.item.source.trackId,
      startMs: startMs,
      endMs: endMs,
      language: anchor?.label?.trim().isNotEmpty == true
          ? anchor!.label!.trim()
          : 'und',
      transcriptSnapshot: entry.item.promptSnapshot,
      recall: 'delayed',
      sourceMediaPath: mediaPath,
      reviewItemId: entry.item.id,
    );
    await closeReading();
    await acquireRecordingFocus();
    _returnPosition = player.position;
    _source = source;
    notifyListeners();
    await task.openTask(
      api,
      source: source,
      fixedRubricPoints: fixedRubricPoints,
    );
  }

  Future<void> openPersonalPattern(
    LocalApi api, {
    required String patternId,
    required String language,
    required String sourceText,
    required String promptText,
    String? mediaId,
    String? trackId,
    int? startMs,
    int? endMs,
    required List<RubricPointView> fixedRubricPoints,
    required Future<void> Function() closeReading,
  }) async {
    final effectiveStart = startMs ?? 0;
    final source = SpeakingTaskSource(
      anchorCueId: patternId,
      mediaId: mediaId,
      trackId: trackId,
      startMs: effectiveStart,
      endMs: endMs != null && endMs > effectiveStart
          ? endMs
          : effectiveStart + 1,
      language: language,
      transcriptSnapshot: sourceText,
      promptSnapshot: promptText,
    );
    await closeReading();
    await acquireRecordingFocus();
    _returnPosition = player.position;
    _source = source;
    notifyListeners();
    await task.openTask(
      api,
      source: source,
      fixedRubricPoints: fixedRubricPoints,
      kind: SpeakingTaskController.patternProductionKind,
      assistance: 'no_text',
    );
  }

  Future<void> playRecording() async {
    final asset = task.state.recording;
    if (asset == null) return;
    await stopAuxiliaryAudio?.call();
    final generation = ++_audioGeneration;
    await adapter.pause();
    await slicePlayer.pause();
    await recordingAdapter.open(asset.filePath);
    await Future<void>.delayed(Duration(milliseconds: asset.durationMs + 80));
    if (generation == _audioGeneration) {
      await recordingAdapter.pause();
    }
  }

  Future<void> acquireRecordingFocus() async {
    _audioGeneration++;
    await stopAuxiliaryAudio?.call();
    await adapter.pause();
    await recordingAdapter.pause();
    await slicePlayer.pause();
  }

  /// Keeps content-launched retelling inside the v1 10–60 second task range.
  /// A normal paragraph is preserved; pathological short/long subtitle
  /// grouping falls back to a cue window anchored at the current position.
  List<Cue> _speakingWindow(
    List<Cue> trackCues,
    String? currentCueId,
    ReadingParagraph paragraph,
  ) {
    final paragraphCues = [
      for (final sentence in paragraph.sentences) ...sentence.cues,
    ];
    final paragraphDuration =
        paragraphCues.last.end.inMilliseconds -
        paragraphCues.first.start.inMilliseconds;
    if (paragraphDuration >= 10000 && paragraphDuration <= 60000) {
      return paragraphCues;
    }

    var anchor = trackCues.indexWhere((cue) => cue.id == currentCueId);
    if (anchor < 0) {
      anchor = trackCues.indexWhere((cue) => cue.id == paragraph.anchorCueId);
    }
    if (anchor < 0) anchor = 0;
    var start = anchor;
    var end = anchor;
    int duration() =>
        trackCues[end].end.inMilliseconds -
        trackCues[start].start.inMilliseconds;
    bool canInclude(int nextStart, int nextEnd) =>
        trackCues[nextEnd].end.inMilliseconds -
            trackCues[nextStart].start.inMilliseconds <=
        60000;

    while (duration() < 10000 && (end + 1 < trackCues.length || start > 0)) {
      if (end + 1 < trackCues.length && canInclude(start, end + 1)) {
        end++;
      } else if (start > 0 && canInclude(start - 1, end)) {
        start--;
      } else {
        break;
      }
    }
    while (end + 1 < trackCues.length && canInclude(start, end + 1)) {
      final nextDuration =
          trackCues[end + 1].end.inMilliseconds -
          trackCues[start].start.inMilliseconds;
      if (nextDuration > 30000) break;
      end++;
    }
    return trackCues.sublist(start, end + 1);
  }
}
