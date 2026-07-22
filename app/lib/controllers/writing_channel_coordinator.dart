import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/reading.dart';
import '../models/semantic_task.dart';
import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
import 'auxiliary_audio_controller.dart';
import 'occurrence_media_resolver.dart';
import 'player_controller.dart';
import 'settings_controller.dart';
import 'slice_player_controller.dart';
import 'subtitle_controller.dart';
import 'writing_task_controller.dart';

/// Owns the writing channel's page state: which segment the studio is anchored
/// on, which writing kind is selected, and how many times the learner replayed
/// the source. Extracted from the composition root; getter names mirror the
/// host's former field names.
///
/// Durable task rules stay in [WritingTaskController]. Cross-channel teardown
/// stays with the host through [closeOtherChannels] — the writing channel does
/// not know what "reading" or "speaking" are.
class WritingChannelCoordinator extends ChangeNotifier {
  WritingChannelCoordinator({
    required this.adapter,
    required this.recordingAdapter,
    required this.player,
    required this.subtitle,
    required this.settings,
    required this.slicePlayer,
    required this.auxiliaryAudio,
    required this.task,
  });

  final DesktopPlayerAdapter adapter;
  final DesktopPlayerAdapter recordingAdapter;
  final PlayerController player;
  final SubtitleController subtitle;
  final SettingsController settings;
  final SlicePlayerController slicePlayer;
  final AuxiliaryAudioController auxiliaryAudio;
  final WritingTaskController task;

  LocalApi? Function()? _getApi;
  bool Function()? _isMounted;
  Future<void> Function(Map<String, dynamic> occurrence)? _openSlicePlayback;
  Future<void> Function()? _closeOtherChannels;

  /// Host seams. [closeOtherChannels] runs the listening/reading/speaking
  /// teardown the composition root owns, right before the studio opens.
  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required Future<void> Function(Map<String, dynamic> occurrence)
    openSlicePlayback,
    required Future<void> Function() closeOtherChannels,
  }) {
    _getApi = getApi;
    _isMounted = isMounted;
    _openSlicePlayback = openSlicePlayback;
    _closeOtherChannels = closeOtherChannels;
  }

  WritingTaskSource? _studioSource;
  String _kind = WritingTaskController.summaryKind;
  int _playCount = 0;

  WritingTaskSource? get studioSource => _studioSource;
  String get kind => _kind;
  int get playCount => _playCount;
  bool get isOpen => _studioSource != null;

  bool get _mounted => _isMounted?.call() ?? true;

  /// Anchors the writing studio on the paragraph under the playhead (or the
  /// first speech paragraph) and opens [kind]. Re-entrant: switching kinds
  /// goes through here again.
  Future<void> openTask(
    String kind, {
    required String promptSnapshot,
    required List<RubricPointView> fixedRubricPoints,
  }) async {
    final service = _getApi?.call();
    final track = subtitle.primaryTrack;
    if (service == null || track == null) return;
    final paragraphs = deriveReadingParagraphs(
      track.cues,
    ).where((paragraph) => !paragraph.nonSpeech).toList(growable: false);
    if (paragraphs.isEmpty) return;
    final currentCueId = subtitle.currentPrimaryCue?.id;
    final paragraph = paragraphs.firstWhere(
      (candidate) => candidate.sentences.any(
        (sentence) => sentence.cues.any((cue) => cue.id == currentCueId),
      ),
      orElse: () => paragraphs.first,
    );
    final cursor = subtitle.primaryCursor;
    final anchor = Cue(
      id: paragraph.anchorCueId,
      index: 0,
      start: paragraph.start,
      end: paragraph.end,
      text: '',
      tokens: const [],
    );
    final language = settings.resolveLearningLanguage(track.language);
    final source = WritingTaskSource(
      anchorCueId: paragraph.anchorCueId,
      mediaId: track.mediaId ?? player.mediaId,
      trackId: track.id,
      startMs: cursor.mediaStart(anchor).inMilliseconds,
      endMs: cursor.mediaEnd(anchor).inMilliseconds,
      sourceLanguage: language,
      responseLanguage: language,
      transcriptSnapshot: paragraph.sentences
          .map((sentence) => sentence.text)
          .join(' '),
    );
    await slicePlayer.close();
    await adapter.pause();
    await _closeOtherChannels?.call();
    if (!_mounted) return;
    _kind = kind;
    _playCount = 0;
    _studioSource = source;
    notifyListeners();
    unawaited(
      task.openTask(
        service,
        source: source,
        kind: kind,
        promptSnapshot: promptSnapshot,
        fixedRubricPoints: fixedRubricPoints,
      ),
    );
  }

  Future<void> close() async {
    await auxiliaryAudio.stop();
    await slicePlayer.close();
    task.closeTask();
    if (_mounted) {
      _studioSource = null;
      notifyListeners();
    }
  }

  /// Reads the learner's own text back to them. Returns false when synthesis
  /// was unavailable, so the host can surface that where it has a context.
  Future<bool> speakText(String text) async {
    final service = _getApi?.call();
    final source = _studioSource;
    if (service == null || source == null || text.trim().isEmpty) return true;
    final asset = await auxiliaryAudio.speak(
      service,
      text: text,
      language: source.responseLanguage,
      purpose: 'writing_readback',
      acquireAudioFocus: () async {
        await adapter.pause();
        await recordingAdapter.pause();
        await slicePlayer.pause();
      },
    );
    return asset != null;
  }

  void playSource() {
    final source = _studioSource;
    if (source == null) return;
    _playCount++;
    notifyListeners();
    unawaited(
      _openSlicePlayback?.call(
            currentMediaSliceOccurrence(
              mediaId: source.mediaId,
              trackId: source.trackId,
              sentenceId: source.anchorCueId,
              textSnapshot: '',
              startMs: source.startMs,
              endMs: source.endMs,
              mediaFingerprint: player.mediaFingerprint,
            ),
          ) ??
          Future<void>.value(),
    );
  }
}
