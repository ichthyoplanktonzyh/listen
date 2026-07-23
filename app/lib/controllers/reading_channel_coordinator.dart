import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/reading.dart';
import '../models/semantic_task.dart';
import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
import 'occurrence_media_resolver.dart';
import 'player_controller.dart';
import 'reading_controller.dart';
import 'reading_diff_controller.dart';
import 'reading_task_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Owns the reading channel's page state machine: which surface the channel
/// currently shows (reader, task studio, read-listen diff, listening check),
/// the word inspector flag, and the debounced reading-cursor write. Extracted
/// from the composition root; getter names mirror the host's former field
/// names so the reading tree reads identically at both sites.
///
/// Durable task rules stay in [ReadingTaskController] / [ReadingDiffController];
/// this coordinator only sequences them with audio focus and page state.
class ReadingChannelCoordinator extends ChangeNotifier {
  ReadingChannelCoordinator({
    required this.adapter,
    required this.player,
    required this.subtitle,
    required this.settings,
    required this.reading,
    required this.readingTask,
    required this.readingDiff,
  }) {
    reading.addListener(_scheduleReadingPositionSave);
  }

  final DesktopPlayerAdapter adapter;
  final PlayerController player;
  final SubtitleController subtitle;
  final SettingsController settings;
  final ReadingController reading;
  final ReadingTaskController readingTask;
  final ReadingDiffController readingDiff;

  LocalApi? Function()? _getApi;
  bool Function()? _isMounted;
  Future<void> Function(Map<String, dynamic> occurrence)? _openSlicePlayback;
  Future<void> Function(SubtitleToken token, Cue cue)? _openWord;

  /// Host seams. [openSlicePlayback] keeps replay on the slice window so the
  /// primary playback position never moves while reading; [openWord] hands
  /// lexical selection back to the vocabulary coordinator.
  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required Future<void> Function(Map<String, dynamic> occurrence)
    openSlicePlayback,
    required Future<void> Function(SubtitleToken token, Cue cue) openWord,
  }) {
    _getApi = getApi;
    _isMounted = isMounted;
    _openSlicePlayback = openSlicePlayback;
    _openWord = openWord;
  }

  ReadingTaskSource? _taskStudioSource;
  ReadingTaskSource? _diffSource;
  ReadingParagraph? _diffParagraph;
  bool _wordInspectorOpen = false;

  // Non-null while the listening-retell surface replaces the reading view.
  ReadingTaskSource? _listeningCheckSource;
  int _listeningPlayCount = 0;

  Timer? _saveTimer;
  String? _lastSavedAnchor;

  ReadingTaskSource? get taskStudioSource => _taskStudioSource;
  ReadingTaskSource? get diffSource => _diffSource;
  ReadingParagraph? get diffParagraph => _diffParagraph;
  ReadingTaskSource? get listeningCheckSource => _listeningCheckSource;
  int get listeningPlayCount => _listeningPlayCount;
  bool get wordInspectorOpen => _wordInspectorOpen;
  bool get isOpen => reading.isOpen;

  /// What [isOpen] actually depends on. Watchers of the channel *selection*
  /// listen here rather than to this coordinator, whose page-state
  /// notifications (which reading surface is on top) they do not need.
  Listenable get openChanges => reading;

  bool get _mounted => _isMounted?.call() ?? true;

  /// Enters the reading posture over the current primary track. Playback is
  /// paused (reading has its own rhythm); the position is untouched so
  /// closing returns to the exact playback context.
  Future<void> open() async {
    final track = subtitle.primaryTrack;
    // Defensive backstop: the channel switcher already disables Reading
    // (with a tooltip) when no transcript is loaded.
    if (track == null) return;
    await adapter.pause();
    // Restore the saved reading cursor; a fetch failure just starts from the
    // top (the cursor is a convenience, never a gate).
    String? resumeAnchor;
    try {
      final saved = await _getApi?.call()?.readingPosition(track.id);
      resumeAnchor = saved?.anchorCueId;
    } catch (_) {}
    _lastSavedAnchor = resumeAnchor;
    reading.open(
      track,
      secondaryTrack: subtitle.secondaryTrack,
      resumeAnchorCueId: resumeAnchor,
    );
  }

  Future<void> close() async {
    if (_listeningCheckSource != null) closeListeningCheck();
    if (_taskStudioSource != null) closeTaskStudio();
    if (_diffSource != null) closeDiff();
    _saveTimer?.cancel();
    unawaited(savePosition());
    reading.close();
    if (_mounted) {
      _wordInspectorOpen = false;
      notifyListeners();
    }
  }

  Future<void> openWord(SubtitleToken token, Cue cue) async {
    if (!_wordInspectorOpen) {
      _wordInspectorOpen = true;
      notifyListeners();
    }
    await _openWord?.call(token, cue);
  }

  void closeWordInspector() {
    if (!_wordInspectorOpen) return;
    _wordInspectorOpen = false;
    notifyListeners();
  }

  /// Debounced cursor write: paragraph taps arrive in bursts while the user
  /// settles; only the resting anchor is worth a backend round trip.
  void _scheduleReadingPositionSave() {
    final state = reading.state;
    if (!state.open ||
        state.anchorCueId == null ||
        state.anchorCueId == _lastSavedAnchor) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(savePosition());
    });
  }

  Future<void> savePosition() async {
    final state = reading.state;
    final trackId = state.trackId;
    final anchor = state.anchorCueId;
    if (trackId == null || anchor == null) return;
    if (anchor == _lastSavedAnchor) return;
    try {
      await _getApi?.call()?.saveReadingPosition(
        trackId: trackId,
        mediaId: subtitle.primaryTrack?.mediaId,
        anchorCueId: anchor,
        paragraphIndex: state.anchorParagraphIndex,
      );
      _lastSavedAnchor = anchor;
    } catch (_) {
      // Cursor writes are best-effort; the next tap retries.
    }
  }

  /// Builds the shared segment descriptor for reading/listening tasks and
  /// the diff card. The response language defaults to the learner's L1
  /// (comprehension is best demonstrated in the language they think in),
  /// falling back to the track language when L1 was never set.
  Future<ReadingTaskSource?> taskSource(ReadingParagraph paragraph) async {
    final track = subtitle.primaryTrack;
    final service = _getApi?.call();
    if (track == null || service == null) return null;
    final cursor = subtitle.primaryCursor;
    final sourceLanguage = settings.resolveLearningLanguage(track.language);
    var responseLanguage = sourceLanguage;
    try {
      final profile = await service.learnerProfile();
      final l1 = profile.l1Language;
      if (l1 != null && l1.isNotEmpty) responseLanguage = l1;
    } catch (_) {}
    final anchor = Cue(
      id: paragraph.anchorCueId,
      index: 0,
      start: paragraph.start,
      end: paragraph.end,
      text: '',
      tokens: const [],
    );
    return ReadingTaskSource(
      anchorCueId: paragraph.anchorCueId,
      mediaId: track.mediaId ?? player.mediaId,
      trackId: track.id,
      startMs: cursor.mediaStart(anchor).inMilliseconds,
      endMs: cursor.mediaEnd(anchor).inMilliseconds,
      sourceLanguage: sourceLanguage,
      responseLanguage: responseLanguage,
      transcriptSnapshot: paragraph.sentences
          .map((sentence) => sentence.text)
          .join(' '),
    );
  }

  /// Opens the paragraph-task flow (Slice 3): manual rubric + typed answer +
  /// per-point self-assessment through the 3.11 semantic fact family.
  Future<void> openTask(
    ReadingParagraph paragraph, {
    required List<RubricPointView> templatePoints,
  }) async {
    final source = await taskSource(paragraph);
    final service = _getApi?.call();
    if (source == null || service == null || !_mounted) return;
    await adapter.pause();
    _taskStudioSource = source;
    notifyListeners();
    unawaited(
      readingTask.openTask(
        service,
        source: source,
        templatePoints: templatePoints,
      ),
    );
  }

  void closeTaskStudio() {
    readingTask.closeTask();
    _taskStudioSource = null;
    notifyListeners();
  }

  /// Opens the read-listen pairing card (Slice 4): both sides' facts over
  /// the same segment, reduced independently — never a causal claim.
  Future<void> openDiff(ReadingParagraph paragraph) async {
    final source = await taskSource(paragraph);
    final service = _getApi?.call();
    if (source == null || service == null || !_mounted) return;
    _diffSource = source;
    _diffParagraph = paragraph;
    notifyListeners();
    unawaited(readingDiff.loadDiff(service, source));
  }

  void closeDiff() {
    _diffSource = null;
    _diffParagraph = null;
    notifyListeners();
  }

  /// Swaps the reading view for the listening-retell surface. The reading
  /// rubric's points seed the retell template when they exist, so both
  /// sides interrogate the same content; otherwise [fallbackTemplatePoints]
  /// applies. Text hidden by construction: the panel replaces the view.
  void openListeningCheck(
    ReadingTaskSource source, {
    required List<RubricPointView> fallbackTemplatePoints,
  }) {
    final service = _getApi?.call();
    // Defensive backstop: the reading surface only exists once the core is
    // connected (the workbench renders behind the root api gate).
    if (service == null) return;
    final readingPoints = readingDiff.state.read.rubric?.points;
    final template = readingPoints == null || readingPoints.isEmpty
        ? fallbackTemplatePoints
        : readingPoints;
    _listeningCheckSource = source;
    _listeningPlayCount = 0;
    notifyListeners();
    unawaited(
      readingTask.openTask(
        service,
        source: source,
        templatePoints: template,
        purpose: ReadingTaskController.listeningPurpose,
      ),
    );
  }

  void closeListeningCheck() {
    readingTask.closeTask();
    _listeningCheckSource = null;
    notifyListeners();
  }

  /// Replays the listening-check segment; the play count is the honest
  /// exposure record the retell panel surfaces.
  void playListeningCheckSegment() {
    final source = _listeningCheckSource;
    if (source == null) return;
    _listeningPlayCount++;
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

  /// Replays a reading range through the slice window (3.5.7) so the primary
  /// playback position never moves while reading.
  Future<void> playRange(
    Duration start,
    Duration end,
    String anchorCueId,
    String textSnapshot,
  ) async {
    final track = subtitle.primaryTrack;
    if (track == null) return;
    final cursor = subtitle.primaryCursor;
    final anchor = Cue(
      id: anchorCueId,
      index: 0,
      start: start,
      end: end,
      text: textSnapshot,
      tokens: const [],
    );
    await _openSlicePlayback?.call(
      currentMediaSliceOccurrence(
        mediaId: track.mediaId ?? player.mediaId,
        trackId: track.id,
        sentenceId: anchorCueId,
        textSnapshot: textSnapshot,
        startMs: cursor.mediaStart(anchor).inMilliseconds,
        endMs: cursor.mediaEnd(anchor).inMilliseconds,
        mediaFingerprint: player.mediaFingerprint,
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    reading.removeListener(_scheduleReadingPositionSave);
    super.dispose();
  }
}
