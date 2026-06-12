import 'package:flutter/foundation.dart';

import '../models/timeline.dart';

const _unset = Object();

/// Immutable snapshot of subtitle-related state.
class SubtitleState {
  const SubtitleState({
    this.primaryTrack,
    this.secondaryTrack,
    this.currentPrimaryCue,
    this.currentSecondaryCue,
    this.selectedCue,
    this.primarySubtitleOffset = Duration.zero,
    this.secondarySubtitleOffset = Duration.zero,
    this.loopCue = false,
    this.visible = true,
    this.secondaryVisible = true,
    this.statusStylesVisible = true,
    this.primaryFontSize = 1.0,
    this.secondaryFontSize = 1.0,
    this.primaryFontFamily = 'system',
    this.secondaryFontFamily = 'system',
    this.preset = 'learning',
    this.positionX = 0.5,
    this.positionY = 0.82,
    this.backgroundOpacity = 0.72,
    this.pronunciationBySentence = const {},
    this.timingsBySentence = const {},
    this.pronunciationProviders = const [],
    this.currentWordToken,
  });

  final SubtitleTrack? primaryTrack;
  final SubtitleTrack? secondaryTrack;
  final Cue? currentPrimaryCue;
  final Cue? currentSecondaryCue;
  final Cue? selectedCue;
  final Duration primarySubtitleOffset;
  final Duration secondarySubtitleOffset;
  final bool loopCue;
  final bool visible;
  final bool secondaryVisible;
  final bool statusStylesVisible;
  final double primaryFontSize;
  final double secondaryFontSize;
  final String primaryFontFamily;
  final String secondaryFontFamily;
  final String preset;
  final double positionX;
  final double positionY;
  final double backgroundOpacity;
  final Map<String, Map<String, dynamic>> pronunciationBySentence;
  final Map<String, List<WordTiming>> timingsBySentence;
  final List<Map<String, dynamic>> pronunciationProviders;
  final int? currentWordToken;

  SubtitleState copyWith({
    Object? primaryTrack = _unset,
    Object? secondaryTrack = _unset,
    Object? currentPrimaryCue = _unset,
    Object? currentSecondaryCue = _unset,
    Object? selectedCue = _unset,
    Duration? primarySubtitleOffset,
    Duration? secondarySubtitleOffset,
    bool? loopCue,
    bool? visible,
    bool? secondaryVisible,
    bool? statusStylesVisible,
    double? primaryFontSize,
    double? secondaryFontSize,
    String? primaryFontFamily,
    String? secondaryFontFamily,
    String? preset,
    double? positionX,
    double? positionY,
    double? backgroundOpacity,
    Map<String, Map<String, dynamic>>? pronunciationBySentence,
    Map<String, List<WordTiming>>? timingsBySentence,
    List<Map<String, dynamic>>? pronunciationProviders,
    Object? currentWordToken = _unset,
  }) => SubtitleState(
    primaryTrack: identical(primaryTrack, _unset)
        ? this.primaryTrack
        : primaryTrack as SubtitleTrack?,
    secondaryTrack: identical(secondaryTrack, _unset)
        ? this.secondaryTrack
        : secondaryTrack as SubtitleTrack?,
    currentPrimaryCue: identical(currentPrimaryCue, _unset)
        ? this.currentPrimaryCue
        : currentPrimaryCue as Cue?,
    currentSecondaryCue: identical(currentSecondaryCue, _unset)
        ? this.currentSecondaryCue
        : currentSecondaryCue as Cue?,
    selectedCue: identical(selectedCue, _unset)
        ? this.selectedCue
        : selectedCue as Cue?,
    primarySubtitleOffset: primarySubtitleOffset ?? this.primarySubtitleOffset,
    secondarySubtitleOffset:
        secondarySubtitleOffset ?? this.secondarySubtitleOffset,
    loopCue: loopCue ?? this.loopCue,
    visible: visible ?? this.visible,
    secondaryVisible: secondaryVisible ?? this.secondaryVisible,
    statusStylesVisible: statusStylesVisible ?? this.statusStylesVisible,
    primaryFontSize: primaryFontSize ?? this.primaryFontSize,
    secondaryFontSize: secondaryFontSize ?? this.secondaryFontSize,
    primaryFontFamily: primaryFontFamily ?? this.primaryFontFamily,
    secondaryFontFamily: secondaryFontFamily ?? this.secondaryFontFamily,
    preset: preset ?? this.preset,
    positionX: positionX ?? this.positionX,
    positionY: positionY ?? this.positionY,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    pronunciationBySentence:
        pronunciationBySentence ?? this.pronunciationBySentence,
    timingsBySentence: timingsBySentence ?? this.timingsBySentence,
    pronunciationProviders:
        pronunciationProviders ?? this.pronunciationProviders,
    currentWordToken: identical(currentWordToken, _unset)
        ? this.currentWordToken
        : currentWordToken as int?,
  );

  TimelineCursor get primaryCursor => TimelineCursor(
    primaryTrack?.cues ?? const [],
    offset: primarySubtitleOffset,
  );

  TimelineCursor get secondaryCursor => secondaryTrack != null
      ? TimelineCursor(secondaryTrack!.cues, offset: secondarySubtitleOffset)
      : const TimelineCursor([], offset: Duration.zero);

  Cue? get currentCue => currentPrimaryCue;
}

/// Controls subtitle display, timing, and appearance.
class SubtitleController extends ChangeNotifier {
  SubtitleState _state = const SubtitleState();

  SubtitleState get state => _state;

  // Convenience accessors
  SubtitleTrack? get primaryTrack => _state.primaryTrack;
  SubtitleTrack? get secondaryTrack => _state.secondaryTrack;
  Cue? get currentPrimaryCue => _state.currentPrimaryCue;
  Cue? get currentSecondaryCue => _state.currentSecondaryCue;
  Cue? get currentCue => _state.currentPrimaryCue;
  Cue? get selectedCue => _state.selectedCue;
  bool get loopCue => _state.loopCue;
  bool get visible => _state.visible;
  bool get secondaryVisible => _state.secondaryVisible;
  bool get statusStylesVisible => _state.statusStylesVisible;
  String get preset => _state.preset;
  double get primaryFontSize => _state.primaryFontSize;
  double get secondaryFontSize => _state.secondaryFontSize;
  String get primaryFontFamily => _state.primaryFontFamily;
  String get secondaryFontFamily => _state.secondaryFontFamily;
  double get positionX => _state.positionX;
  double get positionY => _state.positionY;
  double get backgroundOpacity => _state.backgroundOpacity;
  Map<String, Map<String, dynamic>> get pronunciationBySentence =>
      _state.pronunciationBySentence;
  Map<String, List<WordTiming>> get timingsBySentence =>
      _state.timingsBySentence;
  List<Map<String, dynamic>> get pronunciationProviders =>
      _state.pronunciationProviders;
  int? get currentWordToken => _state.currentWordToken;
  Duration get primarySubtitleOffset => _state.primarySubtitleOffset;
  Duration get secondarySubtitleOffset => _state.secondarySubtitleOffset;
  TimelineCursor get primaryCursor => _state.primaryCursor;
  TimelineCursor get secondaryCursor => _state.secondaryCursor;

  void _update(SubtitleState Function(SubtitleState) fn) {
    _state = fn(_state);
    notifyListeners();
  }

  /// Update cue positions based on current media position.
  void updatePosition(Duration mediaPosition) {
    final primaryOffset = _state.primarySubtitleOffset;
    final secondaryOffset = _state.secondarySubtitleOffset;
    final newPrimary = _state.primaryCursor.current(mediaPosition);
    final newSecondary = _state.secondaryCursor.current(
      mediaPosition + secondaryOffset - primaryOffset,
    );
    if (newPrimary != _state.currentPrimaryCue ||
        newSecondary != _state.currentSecondaryCue) {
      _update(
        (s) => s.copyWith(
          currentPrimaryCue: newPrimary,
          currentSecondaryCue: newSecondary,
        ),
      );
    }
  }

  void setPrimaryTrack(SubtitleTrack? track) =>
      _update((s) => s.copyWith(primaryTrack: track));

  void setSecondaryTrack(SubtitleTrack? track) =>
      _update((s) => s.copyWith(secondaryTrack: track));

  void setVisible(bool visible) => _update((s) => s.copyWith(visible: visible));
  void setSecondaryVisible(bool visible) =>
      _update((s) => s.copyWith(secondaryVisible: visible));
  void setStatusStylesVisible(bool visible) =>
      _update((s) => s.copyWith(statusStylesVisible: visible));
  void setLoopCue(bool loop) => _update((s) => s.copyWith(loopCue: loop));
  void setPreset(String preset) => _update((s) => s.copyWith(preset: preset));
  void setPrimaryFontSize(double size) =>
      _update((s) => s.copyWith(primaryFontSize: size));
  void setSecondaryFontSize(double size) =>
      _update((s) => s.copyWith(secondaryFontSize: size));
  void setPrimaryFontFamily(String family) =>
      _update((s) => s.copyWith(primaryFontFamily: family));
  void setSecondaryFontFamily(String family) =>
      _update((s) => s.copyWith(secondaryFontFamily: family));
  void setSelectedCue(Cue? cue) => _update((s) => s.copyWith(selectedCue: cue));

  void movePosition(
    double dx,
    double dy,
    double viewportWidth,
    double viewportHeight,
  ) {
    _update(
      (s) => s.copyWith(
        positionX: (s.positionX + dx / viewportWidth).clamp(0.0, 1.0),
        positionY: (s.positionY + dy / viewportHeight).clamp(0.0, 1.0),
      ),
    );
  }

  void setPositionX(double x) =>
      _update((s) => s.copyWith(positionX: x.clamp(0.0, 1.0)));

  void setPositionY(double y) =>
      _update((s) => s.copyWith(positionY: y.clamp(0.0, 1.0)));

  void setBackgroundOpacity(double opacity) =>
      _update((s) => s.copyWith(backgroundOpacity: opacity));

  void setSpeechEnhancements({
    required Map<String, Map<String, dynamic>> pronunciationBySentence,
    required Map<String, List<WordTiming>> timingsBySentence,
    required List<Map<String, dynamic>> pronunciationProviders,
  }) => _update(
    (s) => s.copyWith(
      pronunciationBySentence: pronunciationBySentence,
      timingsBySentence: timingsBySentence,
      pronunciationProviders: pronunciationProviders,
    ),
  );

  void setSentencePronunciation(
    String sentenceId,
    Map<String, dynamic> pronunciation,
  ) {
    final values = Map<String, Map<String, dynamic>>.from(
      _state.pronunciationBySentence,
    );
    values[sentenceId] = pronunciation;
    _update((s) => s.copyWith(pronunciationBySentence: values));
  }

  void clearSpeechEnhancements() => _update(
    (s) => s.copyWith(
      pronunciationBySentence: const {},
      timingsBySentence: const {},
      pronunciationProviders: const [],
      currentWordToken: null,
    ),
  );

  void updateCurrentWord(Duration mediaPosition, {required bool enabled}) {
    final cue = _state.currentPrimaryCue;
    final token = enabled && cue != null
        ? currentWordTokenIndex(
            _state.timingsBySentence[cue.id] ?? const [],
            mediaPosition,
            offset: _state.primarySubtitleOffset,
          )
        : null;
    if (token != _state.currentWordToken) {
      _update((s) => s.copyWith(currentWordToken: token));
    }
  }

  /// Seek to the previous cue relative to the current one.
  Cue? previousCue() {
    final cue = _state.currentPrimaryCue;
    if (cue == null) return null;
    return _state.primaryCursor.previous(cue);
  }

  /// Seek to the next cue relative to the current one.
  Cue? nextCue() {
    return _state.primaryCursor.next(_state.currentPrimaryCue);
  }

  /// Binary search the transcript list to keep the active cue visible.
  int transcriptIndexFor(Cue? cue) {
    if (cue == null || _state.primaryTrack == null) return 0;
    final cues = _state.primaryTrack!.cues;
    var low = 0;
    var high = cues.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (cues[mid].start <= cue.start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return (low - 1).clamp(0, cues.length - 1);
  }

  void setPrimarySubtitleOffset(Duration offset) =>
      _update((s) => s.copyWith(primarySubtitleOffset: offset));

  void setSecondarySubtitleOffset(Duration offset) =>
      _update((s) => s.copyWith(secondarySubtitleOffset: offset));

  void setCurrentPrimaryCue(Cue? cue) =>
      _update((s) => s.copyWith(currentPrimaryCue: cue));

  void setCurrentSecondaryCue(Cue? cue) =>
      _update((s) => s.copyWith(currentSecondaryCue: cue));
}
