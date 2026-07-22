import 'package:flutter/foundation.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../state/store.dart';

const _unset = Object();
const _wordHighlightGapTolerance = Duration(milliseconds: 220);

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
    this.chunkPartitionsBySentence = const {},
    this.senseGroupsBySentence = const {},
    this.pronunciationProviders = const [],
    this.subtitleResources = const [],
    this.subtitleResourceCapabilities = const {},
    this.wordTimelineSummaries = const [],
    this.phoneTimelineSummaries = const [],
    this.chunkTimelineSummaries = const [],
    this.llTimelineDocument,
    this.timelineResourceError,
    this.phoneticAnalysisBySentence = const {},
    this.contentFit,
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
  final Map<String, PronunciationAnalysis> pronunciationBySentence;
  final Map<String, List<WordTiming>> timingsBySentence;
  final Map<String, SentenceChunkPartition> chunkPartitionsBySentence;
  final Map<String, List<SenseGroup>> senseGroupsBySentence;
  final List<PronunciationProvider> pronunciationProviders;
  final List<SubtitleTrack> subtitleResources;
  final Map<String, SubtitleResourceCapabilities> subtitleResourceCapabilities;
  final List<WordTimelineSummary> wordTimelineSummaries;
  final List<PhoneTimelineSummary> phoneTimelineSummaries;
  final List<ChunkTimelineSummary> chunkTimelineSummaries;
  final LLTimelineDocument? llTimelineDocument;
  final String? timelineResourceError;
  final Map<String, PhoneticAnalysis> phoneticAnalysisBySentence;
  final ContentDifficultyProfile? contentFit;

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
    Map<String, PronunciationAnalysis>? pronunciationBySentence,
    Map<String, List<WordTiming>>? timingsBySentence,
    Map<String, SentenceChunkPartition>? chunkPartitionsBySentence,
    Map<String, List<SenseGroup>>? senseGroupsBySentence,
    List<PronunciationProvider>? pronunciationProviders,
    List<SubtitleTrack>? subtitleResources,
    Map<String, SubtitleResourceCapabilities>? subtitleResourceCapabilities,
    List<WordTimelineSummary>? wordTimelineSummaries,
    List<PhoneTimelineSummary>? phoneTimelineSummaries,
    List<ChunkTimelineSummary>? chunkTimelineSummaries,
    Object? llTimelineDocument = _unset,
    Object? timelineResourceError = _unset,
    Map<String, PhoneticAnalysis>? phoneticAnalysisBySentence,
    Object? contentFit = _unset,
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
    chunkPartitionsBySentence:
        chunkPartitionsBySentence ?? this.chunkPartitionsBySentence,
    senseGroupsBySentence: senseGroupsBySentence ?? this.senseGroupsBySentence,
    pronunciationProviders:
        pronunciationProviders ?? this.pronunciationProviders,
    subtitleResources: subtitleResources ?? this.subtitleResources,
    subtitleResourceCapabilities:
        subtitleResourceCapabilities ?? this.subtitleResourceCapabilities,
    wordTimelineSummaries: wordTimelineSummaries ?? this.wordTimelineSummaries,
    phoneTimelineSummaries:
        phoneTimelineSummaries ?? this.phoneTimelineSummaries,
    chunkTimelineSummaries:
        chunkTimelineSummaries ?? this.chunkTimelineSummaries,
    llTimelineDocument: identical(llTimelineDocument, _unset)
        ? this.llTimelineDocument
        : llTimelineDocument as LLTimelineDocument?,
    timelineResourceError: identical(timelineResourceError, _unset)
        ? this.timelineResourceError
        : timelineResourceError as String?,
    phoneticAnalysisBySentence:
        phoneticAnalysisBySentence ?? this.phoneticAnalysisBySentence,
    contentFit: identical(contentFit, _unset)
        ? this.contentFit
        : contentFit as ContentDifficultyProfile?,
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
///
/// Uses [Store] internally for fine-grained reactive state.
class SubtitleController extends ChangeNotifier {
  final Store<SubtitleState> _store;

  // Speech-rate highlight cursors; see the listenable getters below for the
  // notification contract.
  final ValueNotifier<int?> _currentWordToken = ValueNotifier(null);
  final ValueNotifier<int?> _currentChunkIndex = ValueNotifier(null);
  final ValueNotifier<DetectedPhone?> _currentDetectedPhone = ValueNotifier(
    null,
  );

  SubtitleController() : _store = Store(const SubtitleState()) {
    _store.addListener(notifyListeners);
  }

  /// The reactive store — allows fine-grained field subscriptions.
  Store<SubtitleState> get store => _store;

  SubtitleState get state => _store.state;

  // ── Convenience accessors ──
  SubtitleTrack? get primaryTrack => _store.state.primaryTrack;
  SubtitleTrack? get secondaryTrack => _store.state.secondaryTrack;
  Cue? get currentPrimaryCue => _store.state.currentPrimaryCue;
  Cue? get currentSecondaryCue => _store.state.currentSecondaryCue;
  Cue? get currentCue => _store.state.currentPrimaryCue;
  Cue? get selectedCue => _store.state.selectedCue;
  bool get loopCue => _store.state.loopCue;
  bool get visible => _store.state.visible;
  bool get secondaryVisible => _store.state.secondaryVisible;
  bool get statusStylesVisible => _store.state.statusStylesVisible;
  String get preset => _store.state.preset;
  double get primaryFontSize => _store.state.primaryFontSize;
  double get secondaryFontSize => _store.state.secondaryFontSize;
  String get primaryFontFamily => _store.state.primaryFontFamily;
  String get secondaryFontFamily => _store.state.secondaryFontFamily;
  double get positionX => _store.state.positionX;
  double get positionY => _store.state.positionY;
  double get backgroundOpacity => _store.state.backgroundOpacity;
  Map<String, PronunciationAnalysis> get pronunciationBySentence =>
      _store.state.pronunciationBySentence;
  Map<String, List<WordTiming>> get timingsBySentence =>
      _store.state.timingsBySentence;

  /// Total word timings across the active track's sentences; the capability
  /// readiness and resource panels read this as the word-sync signal.
  int get activeWordTimingCount => _store.state.timingsBySentence.values
      .fold<int>(0, (total, timings) => total + timings.length);
  Map<String, SentenceChunkPartition> get chunkPartitionsBySentence =>
      _store.state.chunkPartitionsBySentence;
  Map<String, List<SenseGroup>> get senseGroupsBySentence =>
      _store.state.senseGroupsBySentence;
  List<PronunciationProvider> get pronunciationProviders =>
      _store.state.pronunciationProviders;
  List<SubtitleTrack> get subtitleResources => _store.state.subtitleResources;
  Map<String, SubtitleResourceCapabilities> get subtitleResourceCapabilities =>
      _store.state.subtitleResourceCapabilities;
  List<WordTimelineSummary> get wordTimelineSummaries =>
      _store.state.wordTimelineSummaries;
  List<PhoneTimelineSummary> get phoneTimelineSummaries =>
      _store.state.phoneTimelineSummaries;
  List<ChunkTimelineSummary> get chunkTimelineSummaries =>
      _store.state.chunkTimelineSummaries;
  LLTimelineDocument? get llTimelineDocument => _store.state.llTimelineDocument;
  String? get timelineResourceError => _store.state.timelineResourceError;
  int? get currentWordToken => _currentWordToken.value;
  Map<String, PhoneticAnalysis> get phoneticAnalysisBySentence =>
      _store.state.phoneticAnalysisBySentence;
  DetectedPhone? get currentDetectedPhone => _currentDetectedPhone.value;
  int? get currentChunkIndex => _currentChunkIndex.value;

  /// High-frequency word/chunk/phone highlight cursors. They advance at
  /// speech rate while media plays, so they live outside [SubtitleState]:
  /// writes do NOT fire the aggregate [ChangeNotifier], and widgets that
  /// render them must subscribe to these listenables.
  ValueListenable<int?> get currentWordTokenListenable => _currentWordToken;
  ValueListenable<int?> get currentChunkIndexListenable => _currentChunkIndex;
  ValueListenable<DetectedPhone?> get currentDetectedPhoneListenable =>
      _currentDetectedPhone;
  Duration get primarySubtitleOffset => _store.state.primarySubtitleOffset;
  Duration get secondarySubtitleOffset => _store.state.secondarySubtitleOffset;
  TimelineCursor get primaryCursor => _store.state.primaryCursor;
  TimelineCursor get secondaryCursor => _store.state.secondaryCursor;

  /// Create a [ValueNotifier] that tracks a specific derived value.
  ValueNotifier<R> select<R>(R Function(SubtitleState) selector) =>
      _store.select(selector);

  /// Update cue positions based on current media position.
  void updatePosition(Duration mediaPosition) {
    final s = _store.state;
    final primaryOffset = s.primarySubtitleOffset;
    final secondaryOffset = s.secondarySubtitleOffset;
    final newPrimary = s.primaryCursor.current(mediaPosition);
    final newSecondary = s.secondaryCursor.current(
      mediaPosition + secondaryOffset - primaryOffset,
    );
    if (newPrimary != s.currentPrimaryCue ||
        newSecondary != s.currentSecondaryCue) {
      _store.update(
        (st) => st.copyWith(
          currentPrimaryCue: newPrimary,
          currentSecondaryCue: newSecondary,
        ),
      );
    }
  }

  void setPrimaryTrack(SubtitleTrack? track) =>
      _store.update((s) => s.copyWith(primaryTrack: track));

  void setSecondaryTrack(SubtitleTrack? track) =>
      _store.update((s) => s.copyWith(secondaryTrack: track));

  void setVisible(bool visible) =>
      _store.update((s) => s.copyWith(visible: visible));

  void setSecondaryVisible(bool visible) =>
      _store.update((s) => s.copyWith(secondaryVisible: visible));

  void setStatusStylesVisible(bool visible) =>
      _store.update((s) => s.copyWith(statusStylesVisible: visible));

  void setLoopCue(bool loop) => _store.update((s) => s.copyWith(loopCue: loop));

  void setPreset(String preset) =>
      _store.update((s) => s.copyWith(preset: preset));

  void setPrimaryFontSize(double size) =>
      _store.update((s) => s.copyWith(primaryFontSize: size));

  void setSecondaryFontSize(double size) =>
      _store.update((s) => s.copyWith(secondaryFontSize: size));

  void setPrimaryFontFamily(String family) =>
      _store.update((s) => s.copyWith(primaryFontFamily: family));

  void setSecondaryFontFamily(String family) =>
      _store.update((s) => s.copyWith(secondaryFontFamily: family));

  void setSelectedCue(Cue? cue) =>
      _store.update((s) => s.copyWith(selectedCue: cue));

  void movePosition(
    double dx,
    double dy,
    double viewportWidth,
    double viewportHeight,
  ) {
    _store.update(
      (s) => s.copyWith(
        positionX: (s.positionX + dx / viewportWidth).clamp(0.0, 1.0),
        positionY: (s.positionY + dy / viewportHeight).clamp(0.0, 1.0),
      ),
    );
  }

  void setPositionX(double x) =>
      _store.update((s) => s.copyWith(positionX: x.clamp(0.0, 1.0)));

  void setPositionY(double y) =>
      _store.update((s) => s.copyWith(positionY: y.clamp(0.0, 1.0)));

  void setBackgroundOpacity(double opacity) =>
      _store.update((s) => s.copyWith(backgroundOpacity: opacity));

  void setSpeechEnhancements({
    required Map<String, PronunciationAnalysis> pronunciationBySentence,
    required Map<String, List<WordTiming>> timingsBySentence,
    required List<PronunciationProvider> pronunciationProviders,
    Map<String, PhoneticAnalysis> phoneticAnalysisBySentence = const {},
    Map<String, SentenceChunkPartition> chunkPartitionsBySentence = const {},
    Map<String, List<SenseGroup>> senseGroupsBySentence = const {},
  }) => _store.update(
    (s) => s.copyWith(
      pronunciationBySentence: pronunciationBySentence,
      timingsBySentence: timingsBySentence,
      chunkPartitionsBySentence: chunkPartitionsBySentence,
      senseGroupsBySentence: senseGroupsBySentence,
      pronunciationProviders: pronunciationProviders,
      phoneticAnalysisBySentence: phoneticAnalysisBySentence,
    ),
  );

  void setSubtitleResources(List<SubtitleTrack> resources) =>
      _store.update((s) => s.copyWith(subtitleResources: resources));

  void setSubtitleResourceCapabilities(
    Map<String, SubtitleResourceCapabilities> capabilities,
  ) => _store.update(
    (s) => s.copyWith(subtitleResourceCapabilities: capabilities),
  );

  void setSentencePronunciation(
    String sentenceId,
    PronunciationAnalysis pronunciation,
  ) {
    final s = _store.state;
    final values = Map<String, PronunciationAnalysis>.from(
      s.pronunciationBySentence,
    );
    values[sentenceId] = pronunciation;
    _store.update((st) => st.copyWith(pronunciationBySentence: values));
  }

  void clearSpeechEnhancements() {
    _currentWordToken.value = null;
    _currentChunkIndex.value = null;
    _currentDetectedPhone.value = null;
    _store.update(
      (s) => s.copyWith(
        pronunciationBySentence: const {},
        timingsBySentence: const {},
        chunkPartitionsBySentence: const {},
        senseGroupsBySentence: const {},
        pronunciationProviders: const [],
        wordTimelineSummaries: const [],
        phoneTimelineSummaries: const [],
        chunkTimelineSummaries: const [],
        llTimelineDocument: null,
        timelineResourceError: null,
        phoneticAnalysisBySentence: const {},
        contentFit: null,
      ),
    );
  }

  void setTimelineResource({
    required List<WordTimelineSummary> summaries,
    required List<PhoneTimelineSummary> phoneSummaries,
    required List<ChunkTimelineSummary> chunkSummaries,
    required LLTimelineDocument? document,
    String? error,
  }) => _store.update(
    (s) => s.copyWith(
      wordTimelineSummaries: summaries,
      phoneTimelineSummaries: phoneSummaries,
      chunkTimelineSummaries: chunkSummaries,
      llTimelineDocument: document,
      timelineResourceError: error,
    ),
  );

  void setTimelineResourceError(String error) =>
      _store.update((s) => s.copyWith(timelineResourceError: error));

  ContentDifficultyProfile? get contentFit => _store.state.contentFit;

  void setContentFit(ContentDifficultyProfile? profile) =>
      _store.update((s) => s.copyWith(contentFit: profile));

  void clearTimelineResource() => _store.update(
    (s) => s.copyWith(
      wordTimelineSummaries: const [],
      phoneTimelineSummaries: const [],
      chunkTimelineSummaries: const [],
      llTimelineDocument: null,
      timelineResourceError: null,
    ),
  );

  void updateCurrentWord(
    Duration mediaPosition, {
    required bool enabled,
    bool? chunkEnabled,
  }) {
    final s = _store.state;
    final cue = s.currentPrimaryCue;
    final token = enabled && cue != null
        ? currentWordTokenIndex(
            s.timingsBySentence[cue.id] ?? const [],
            mediaPosition,
            offset: s.primarySubtitleOffset,
            displayGapTolerance: _wordHighlightGapTolerance,
          )
        : null;
    final chunk = (chunkEnabled ?? enabled) && cue != null
        ? currentChunkAtPosition(
            s.chunkPartitionsBySentence[cue.id],
            mediaPosition,
            offset: s.primarySubtitleOffset,
          )
        : null;
    _currentWordToken.value = token;
    _currentChunkIndex.value = chunk;
  }

  void updateCurrentDetectedPhone(
    Duration mediaPosition, {
    required bool enabled,
  }) {
    final s = _store.state;
    final cue = s.currentPrimaryCue;
    final analysis = !enabled || cue == null
        ? null
        : s.phoneticAnalysisBySentence[cue.id];
    final phone = currentDetectedPhoneAt(
      analysis?.detectedPhones ?? const [],
      mediaPosition,
      offset: s.primarySubtitleOffset,
    );
    final previous = _currentDetectedPhone.value;
    if (phone?.symbol != previous?.symbol ||
        phone?.start != previous?.start ||
        phone?.end != previous?.end) {
      _currentDetectedPhone.value = phone;
    }
  }

  /// Seek to the previous cue relative to the current one.
  Cue? previousCue() {
    final cue = _store.state.currentPrimaryCue;
    if (cue == null) return null;
    return _store.state.primaryCursor.previous(cue);
  }

  /// Seek to the next cue relative to the current one.
  Cue? nextCue() {
    return _store.state.primaryCursor.next(_store.state.currentPrimaryCue);
  }

  /// Binary search the transcript list to keep the active cue visible.
  int transcriptIndexFor(Cue? cue) {
    if (cue == null || _store.state.primaryTrack == null) return 0;
    final cues = _store.state.primaryTrack!.cues;
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
      _store.update((s) => s.copyWith(primarySubtitleOffset: offset));

  void setSecondarySubtitleOffset(Duration offset) =>
      _store.update((s) => s.copyWith(secondarySubtitleOffset: offset));

  void setCurrentPrimaryCue(Cue? cue) =>
      _store.update((s) => s.copyWith(currentPrimaryCue: cue));

  void setCurrentSecondaryCue(Cue? cue) =>
      _store.update((s) => s.copyWith(currentSecondaryCue: cue));

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
