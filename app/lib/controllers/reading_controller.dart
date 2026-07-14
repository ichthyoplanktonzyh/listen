import 'package:flutter/foundation.dart';

import '../models/reading.dart';
import '../models/timeline.dart';
import '../state/store.dart';

const _unset = Object();

/// Reading-posture state. The reading position is deliberately independent
/// from playback: it anchors to a cue id (paragraph identity from the derived
/// read model) and never follows the player (Phase 3.13).
class ReadingState {
  const ReadingState({
    this.open = false,
    this.trackId,
    this.paragraphs = const [],
    this.anchorCueId,
    this.translationVisible = false,
    this.translationByAnchor = const {},
  });

  final bool open;
  final String? trackId;
  final List<ReadingParagraph> paragraphs;

  /// First cue id of the paragraph the reader is at (reading cursor).
  final String? anchorCueId;

  /// Whether paragraph translations are shown. Off by default: reading is
  /// low-assistance first, and what was visible feeds attempt conditions
  /// honestly in later slices.
  final bool translationVisible;

  /// Paragraph anchor cue id → secondary-track text overlapping the
  /// paragraph's time range. Empty when no secondary track is loaded.
  final Map<String, String> translationByAnchor;

  int get anchorParagraphIndex {
    if (anchorCueId == null) return 0;
    final index = paragraphs.indexWhere(
      (paragraph) => paragraph.anchorCueId == anchorCueId,
    );
    return index < 0 ? 0 : index;
  }

  ReadingState copyWith({
    bool? open,
    Object? trackId = _unset,
    List<ReadingParagraph>? paragraphs,
    Object? anchorCueId = _unset,
    bool? translationVisible,
    Map<String, String>? translationByAnchor,
  }) => ReadingState(
    open: open ?? this.open,
    trackId: identical(trackId, _unset)
        ? this.trackId
        : trackId as String?,
    paragraphs: paragraphs ?? this.paragraphs,
    anchorCueId: identical(anchorCueId, _unset)
        ? this.anchorCueId
        : anchorCueId as String?,
    translationVisible: translationVisible ?? this.translationVisible,
    translationByAnchor: translationByAnchor ?? this.translationByAnchor,
  );
}

class ReadingController extends ChangeNotifier {
  ReadingController() : _store = Store(const ReadingState()) {
    _store.addListener(notifyListeners);
  }

  final Store<ReadingState> _store;

  Store<ReadingState> get store => _store;
  ReadingState get state => _store.state;
  bool get isOpen => state.open;

  /// Enters the reading posture over [track]. Paragraphs are derived on the
  /// spot (never persisted); [resumeAnchorCueId] restores a saved reading
  /// cursor once Slice 2 wires persistence.
  void open(
    SubtitleTrack track, {
    SubtitleTrack? secondaryTrack,
    String? resumeAnchorCueId,
  }) {
    final paragraphs = deriveReadingParagraphs(track.cues);
    final resumeValid =
        resumeAnchorCueId != null &&
        paragraphs.any(
          (paragraph) => paragraph.anchorCueId == resumeAnchorCueId,
        );
    _store.replace(
      ReadingState(
        open: true,
        trackId: track.id,
        paragraphs: paragraphs,
        anchorCueId: resumeValid ? resumeAnchorCueId : null,
        translationByAnchor: secondaryTrack == null
            ? const {}
            : _projectTranslations(paragraphs, secondaryTrack),
      ),
    );
  }

  void close() {
    _store.update((s) => s.copyWith(open: false));
  }

  /// Moves the reading cursor to the paragraph containing [cue] (or anchored
  /// at it). Explicit user act only — playback never moves this.
  void markPosition(String anchorCueId) {
    _store.update((s) => s.copyWith(anchorCueId: anchorCueId));
  }

  void setTranslationVisible(bool visible) {
    _store.update((s) => s.copyWith(translationVisible: visible));
  }

  /// Secondary cues whose midpoint falls inside the paragraph's time range,
  /// joined in order. Midpoint matching avoids double-assigning a secondary
  /// cue that brushes two paragraphs' edges.
  static Map<String, String> _projectTranslations(
    List<ReadingParagraph> paragraphs,
    SubtitleTrack secondaryTrack,
  ) {
    final result = <String, String>{};
    for (final paragraph in paragraphs) {
      if (paragraph.nonSpeech) continue;
      final buffer = StringBuffer();
      for (final cue in secondaryTrack.cues) {
        final midpoint = (cue.start + cue.end) ~/ 2;
        if (midpoint >= paragraph.start && midpoint < paragraph.end) {
          if (buffer.isNotEmpty) buffer.write(' ');
          buffer.write(cue.text.trim());
        }
      }
      if (buffer.isNotEmpty) {
        result[paragraph.anchorCueId] = buffer.toString();
      }
    }
    return result;
  }
}
