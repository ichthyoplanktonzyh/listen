import 'timeline.dart';

enum CapabilityReadinessState {
  available,
  generating,
  degraded,
  unavailable,
  unsupported,
  stale,
  error,
}

enum UserCapability {
  subtitles,
  wordSync,
  chunkReplay,
  listeningStructure,
  phoneEvidence,
}

class CapabilityReadiness {
  const CapabilityReadiness({
    required this.capability,
    required this.state,
    required this.detailKey,
    this.count,
    this.countLabelKey,
    this.technicalDetail,
  });

  final UserCapability capability;
  final CapabilityReadinessState state;
  final String detailKey;
  final int? count;
  final String? countLabelKey;
  final String? technicalDetail;

  String get titleKey => switch (capability) {
    UserCapability.subtitles => 'capabilitySubtitles',
    UserCapability.wordSync => 'capabilityWordSync',
    UserCapability.chunkReplay => 'capabilityChunkReplay',
    UserCapability.listeningStructure => 'capabilityListeningStructure',
    UserCapability.phoneEvidence => 'capabilityPhoneEvidence',
  };

  String get stateKey => switch (state) {
    CapabilityReadinessState.available => 'capabilityStateAvailable',
    CapabilityReadinessState.generating => 'capabilityStateGenerating',
    CapabilityReadinessState.degraded => 'capabilityStateDegraded',
    CapabilityReadinessState.unavailable => 'capabilityStateUnavailable',
    CapabilityReadinessState.unsupported => 'capabilityStateUnsupported',
    CapabilityReadinessState.stale => 'capabilityStateStale',
    CapabilityReadinessState.error => 'capabilityStateError',
  };
}

class CapabilityReadinessSnapshot {
  const CapabilityReadinessSnapshot({
    required this.subtitles,
    required this.wordSync,
    required this.chunkReplay,
    required this.listeningStructure,
    required this.phoneEvidence,
  });

  factory CapabilityReadinessSnapshot.fromResources({
    required SubtitleTrack? activeTrack,
    required LLTimelineDocument? document,
    required List<WordTimelineSummary> wordTimelineSummaries,
    required List<ChunkTimelineSummary> chunkTimelineSummaries,
    required List<PhoneTimelineSummary> phoneTimelineSummaries,
    int activeWordTimingCount = 0,
    String? timelineResourceError,
  }) {
    final activeWord = _firstActive(wordTimelineSummaries);
    final activeChunk = _firstActive(chunkTimelineSummaries);
    final activePhone = _firstActive(phoneTimelineSummaries);
    final activeFrames = _activeRhythmFrames(document);
    final hasTrack = activeTrack != null;
    final hasGeneratedWordTimings = activeWordTimingCount > 0;
    final hasWordSync =
        (activeWord != null && activeWord.wordCount > 0) ||
        hasGeneratedWordTimings;
    final wordSyncAudioBacked =
        _hasAudioBackedTiming(activeWord?.timingSources ?? const []) ||
        hasGeneratedWordTimings;
    final wordSyncEstimated =
        activeWord != null && hasWordSync && !wordSyncAudioBacked;
    final timelineError = timelineResourceError?.trim().isNotEmpty == true;

    final subtitles = hasTrack
        ? CapabilityReadiness(
            capability: UserCapability.subtitles,
            state: activeTrack.archived
                ? CapabilityReadinessState.stale
                : CapabilityReadinessState.available,
            detailKey: activeTrack.archived
                ? 'capSubtitlesArchived'
                : 'capSubtitlesAvailable',
            count: activeTrack.cues.length,
            countLabelKey: 'cues',
            technicalDetail: activeTrack.source,
          )
        : CapabilityReadiness(
            capability: UserCapability.subtitles,
            state: CapabilityReadinessState.unavailable,
            detailKey: 'capSubtitlesUnavailable',
          );

    final wordSync = _wordSyncReadiness(
      hasTrack: hasTrack,
      activeWord: activeWord,
      activeWordTimingCount: activeWordTimingCount,
      estimated: wordSyncEstimated,
      timelineError: timelineError,
    );
    final chunkReplay = _chunkReplayReadiness(
      hasTrack: hasTrack,
      hasWordSync: hasWordSync,
      activeChunk: activeChunk,
      timelineError: timelineError,
    );
    final listeningStructure = _listeningStructureReadiness(
      hasTrack: hasTrack,
      hasWordSync: hasWordSync,
      activeFrames: activeFrames,
      wordSyncAudioBacked: wordSyncAudioBacked,
      timelineError: timelineError,
    );
    final phoneEvidence = _phoneEvidenceReadiness(
      hasTrack: hasTrack,
      activePhone: activePhone,
      timelineError: timelineError,
    );

    return CapabilityReadinessSnapshot(
      subtitles: subtitles,
      wordSync: wordSync,
      chunkReplay: chunkReplay,
      listeningStructure: listeningStructure,
      phoneEvidence: phoneEvidence,
    );
  }

  final CapabilityReadiness subtitles;
  final CapabilityReadiness wordSync;
  final CapabilityReadiness chunkReplay;
  final CapabilityReadiness listeningStructure;
  final CapabilityReadiness phoneEvidence;

  List<CapabilityReadiness> get items => [
    subtitles,
    wordSync,
    chunkReplay,
    listeningStructure,
    phoneEvidence,
  ];

  List<CapabilityReadiness> get learningItems => [
    wordSync,
    chunkReplay,
    listeningStructure,
    phoneEvidence,
  ];
}

CapabilityReadiness _wordSyncReadiness({
  required bool hasTrack,
  required WordTimelineSummary? activeWord,
  required int activeWordTimingCount,
  required bool estimated,
  required bool timelineError,
}) {
  if (!hasTrack) {
    return const CapabilityReadiness(
      capability: UserCapability.wordSync,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capWordSyncUnavailableNoSubtitle',
    );
  }
  if (activeWord == null || activeWord.wordCount == 0) {
    if (activeWordTimingCount > 0) {
      return CapabilityReadiness(
        capability: UserCapability.wordSync,
        state: CapabilityReadinessState.available,
        detailKey: 'capWordSyncGeneratedTimings',
        count: activeWordTimingCount,
        countLabelKey: 'words',
        technicalDetail: 'generated word timings',
      );
    }
    return CapabilityReadiness(
      capability: UserCapability.wordSync,
      state: timelineError
          ? CapabilityReadinessState.error
          : CapabilityReadinessState.unavailable,
      detailKey: timelineError
          ? 'capTimelineResourceError'
          : 'capWordSyncUnavailable',
    );
  }
  return CapabilityReadiness(
    capability: UserCapability.wordSync,
    state: estimated
        ? CapabilityReadinessState.degraded
        : CapabilityReadinessState.available,
    detailKey: estimated ? 'capWordSyncEstimated' : 'capWordSyncAvailable',
    count: activeWord.wordCount,
    countLabelKey: 'words',
    technicalDetail: activeWord.timingSources.join(', '),
  );
}

CapabilityReadiness _chunkReplayReadiness({
  required bool hasTrack,
  required bool hasWordSync,
  required ChunkTimelineSummary? activeChunk,
  required bool timelineError,
}) {
  if (!hasTrack) {
    return const CapabilityReadiness(
      capability: UserCapability.chunkReplay,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capChunkReplayUnavailableNoSubtitle',
    );
  }
  if (!hasWordSync) {
    return const CapabilityReadiness(
      capability: UserCapability.chunkReplay,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capChunkReplayUnavailableNoWord',
    );
  }
  if (activeChunk == null || activeChunk.chunkCount == 0) {
    return CapabilityReadiness(
      capability: UserCapability.chunkReplay,
      state: timelineError
          ? CapabilityReadinessState.error
          : CapabilityReadinessState.unavailable,
      detailKey: timelineError
          ? 'capTimelineResourceError'
          : 'capChunkReplayUnavailable',
    );
  }
  return CapabilityReadiness(
    capability: UserCapability.chunkReplay,
    state: CapabilityReadinessState.available,
    detailKey: 'capChunkReplayAvailable',
    count: activeChunk.chunkCount,
    countLabelKey: 'chunks',
    technicalDetail: activeChunk.precision,
  );
}

CapabilityReadiness _listeningStructureReadiness({
  required bool hasTrack,
  required bool hasWordSync,
  required List<LLTimelineRhythmFrame> activeFrames,
  required bool wordSyncAudioBacked,
  required bool timelineError,
}) {
  if (!hasTrack) {
    return const CapabilityReadiness(
      capability: UserCapability.listeningStructure,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capListeningUnavailableNoSubtitle',
    );
  }
  if (!hasWordSync) {
    return const CapabilityReadiness(
      capability: UserCapability.listeningStructure,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capListeningUnavailableNoWord',
    );
  }
  if (activeFrames.isEmpty) {
    return CapabilityReadiness(
      capability: UserCapability.listeningStructure,
      state: timelineError
          ? CapabilityReadinessState.error
          : CapabilityReadinessState.unavailable,
      detailKey: timelineError
          ? 'capTimelineResourceError'
          : 'capListeningUnavailable',
    );
  }
  final hasAudioSupport =
      wordSyncAudioBacked &&
      activeFrames.any(
        (frame) => rhythmFrameHasAudioSupport(frame.rhythmFrame),
      );
  return CapabilityReadiness(
    capability: UserCapability.listeningStructure,
    state: hasAudioSupport
        ? CapabilityReadinessState.available
        : CapabilityReadinessState.degraded,
    detailKey: hasAudioSupport
        ? 'capListeningAvailable'
        : 'capListeningPredictedOnly',
    count: activeFrames.length,
    countLabelKey: 'frames',
    technicalDetail: activeFrames.first.rhythmFrame.generatedFrom,
  );
}

CapabilityReadiness _phoneEvidenceReadiness({
  required bool hasTrack,
  required PhoneTimelineSummary? activePhone,
  required bool timelineError,
}) {
  if (!hasTrack) {
    return const CapabilityReadiness(
      capability: UserCapability.phoneEvidence,
      state: CapabilityReadinessState.unavailable,
      detailKey: 'capPhoneEvidenceUnavailableNoSubtitle',
    );
  }
  if (activePhone == null || activePhone.phoneCount == 0) {
    return CapabilityReadiness(
      capability: UserCapability.phoneEvidence,
      state: timelineError
          ? CapabilityReadinessState.error
          : CapabilityReadinessState.unavailable,
      detailKey: timelineError
          ? 'capTimelineResourceError'
          : 'capPhoneEvidenceUnavailable',
    );
  }
  return CapabilityReadiness(
    capability: UserCapability.phoneEvidence,
    state: CapabilityReadinessState.available,
    detailKey: 'capPhoneEvidenceAvailable',
    count: activePhone.phoneCount,
    countLabelKey: 'phones',
    technicalDetail: activePhone.precision,
  );
}

T? _firstActive<T>(Iterable<T> values) {
  for (final value in values) {
    final active = switch (value) {
      WordTimelineSummary summary => summary.isActive,
      ChunkTimelineSummary summary => summary.isActive,
      PhoneTimelineSummary summary => summary.isActive,
      _ => false,
    };
    if (active) return value;
  }
  return null;
}

List<LLTimelineRhythmFrame> _activeRhythmFrames(LLTimelineDocument? document) {
  if (document == null || document.rhythmFrames.isEmpty) return const [];
  final active = document.rhythmFrames
      .where((frame) => frame.isActive)
      .toList(growable: false);
  return active.isEmpty ? document.rhythmFrames : active;
}

bool _hasAudioBackedTiming(List<String> timingSources) => timingSources.any(
  (source) =>
      source == 'forced_aligned' ||
      source == 'asr_aligned' ||
      source == 'asr_reported' ||
      source == 'user_adjusted',
);

/// Whether a [RhythmFrame] carries at least one audio-backed signal source
/// (timing/energy/pitch/phone_segmental). Used both by listening-structure
/// readiness and by the overlay to flag text-predicted-only frames honestly.
bool rhythmFrameHasAudioSupport(RhythmFrame frame) =>
    _hasAudioSource(frame.quality.prominenceSources) ||
    _hasAudioSource(frame.quality.boundarySources) ||
    frame.informationAnchors.any((value) => value.isAudioSupported) ||
    frame.stressAnchors.any((value) => value.isAudioSupported) ||
    frame.nuclei.any((value) => _hasAudioSource(value.cues)) ||
    frame.weakGroups.any((value) => value.isAudioSupported) ||
    frame.compressionSpans.any((value) => value.isAudioSupported) ||
    frame.phraseBoundaries.any((value) => value.isAudioSupported) ||
    frame.connectedSpeechRefs.any(
      (value) => _hasAudioSource(value.signalSources),
    ) ||
    frame.listeningHotspots.any((value) => value.isAudioSupported);

/// C is the observed audible structure, not a fallback presentation of A/B.
/// Both the loaded sentence resource and the frame itself must carry phone
/// evidence before the player may render the actual view.
bool canDisplayActualRhythmFrame(
  RhythmFrame? frame, {
  required bool hasPhoneEvidence,
}) =>
    frame != null &&
    hasPhoneEvidence &&
    frame.quality.phoneEvidenceCoverage > 0;

bool _hasAudioSource(List<String> values) => values.any(
  (value) =>
      value == 'timing' ||
      value == 'energy' ||
      value == 'pitch' ||
      value == 'phone_segmental',
);
