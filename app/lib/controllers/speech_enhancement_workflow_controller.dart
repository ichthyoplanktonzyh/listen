import '../models/api_failure.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../services/api_service.dart';

class ExistingTimelineResourceState {
  const ExistingTimelineResourceState({
    this.wordSummaries = const [],
    this.phoneSummaries = const [],
    this.chunkSummaries = const [],
    this.document,
  });

  final List<WordTimelineSummary> wordSummaries;
  final List<PhoneTimelineSummary> phoneSummaries;
  final List<ChunkTimelineSummary> chunkSummaries;
  final LLTimelineDocument? document;
}

class TimelineResourceLoadResult {
  const TimelineResourceLoadResult({
    this.wordSummaries = const [],
    this.phoneSummaries = const [],
    this.chunkSummaries = const [],
    this.document,
    this.error,
    this.failures = const [],
    this.unavailable = false,
  });

  final List<WordTimelineSummary> wordSummaries;
  final List<PhoneTimelineSummary> phoneSummaries;
  final List<ChunkTimelineSummary> chunkSummaries;
  final LLTimelineDocument? document;

  /// The named state, or null when nothing failed. One sentence — the four
  /// loaders' exceptions used to be joined into it with semicolons, which put
  /// up to four loopback URIs on a resource panel.
  final String? error;

  /// What each failed loader answered with, kept typed and off screen.
  final List<ApiFailure> failures;
  final bool unavailable;
}

class SpeechEnhancementLoadResult {
  const SpeechEnhancementLoadResult({
    required this.timeline,
    this.timingsBySentence = const {},
    this.chunkPartitionsBySentence = const {},
    this.senseGroupsBySentence = const {},
    this.pronunciationBySentence = const {},
    this.pronunciationProviders = const [],
    this.phoneticAnalysisBySentence = const {},
    this.errors = const [],
  });

  final TimelineResourceLoadResult timeline;
  final Map<String, List<WordTiming>> timingsBySentence;
  final Map<String, SentenceChunkPartition> chunkPartitionsBySentence;
  final Map<String, List<SenseGroup>> senseGroupsBySentence;
  final Map<String, PronunciationAnalysis> pronunciationBySentence;
  final List<PronunciationProvider> pronunciationProviders;
  final Map<String, PhoneticAnalysis> phoneticAnalysisBySentence;

  /// Every optional loader that failed, as a typed failure rather than as a
  /// sentence. Callers report *that* some enhancements are missing; what the
  /// backend said about each one stays here.
  final List<ApiFailure> errors;
}

class SpeechEnhancementWorkflowController {
  final Set<String> _senseGroupFallbackAttemptedTrackIds = {};

  Future<SpeechEnhancementLoadResult> loadSpeechEnhancements({
    required LocalApi service,
    required String trackId,
    required ExistingTimelineResourceState previousTimeline,
  }) async {
    final timeline = await loadTimelineResource(
      service: service,
      trackId: trackId,
      previous: previousTimeline,
    );
    final errors = <ApiFailure>[];
    final timings = await _loadOptionalResourceCapability(
      () => service.trackWordTimings(trackId),
      errors,
    );
    final providers = await _loadOptionalResourceCapability(
      service.pronunciationProviders,
      errors,
    );
    final soundPatterns = await _loadSoundPatternAnalyses(
      service,
      trackId,
      timeline.phoneSummaries,
      errors,
    );
    final partitions = await _loadChunkPartitions(
      service,
      trackId,
      timeline.chunkSummaries,
      errors,
    );
    final senseGroups = await _loadSenseGroups(service, trackId, errors);
    final analyses = await _loadPronunciationEnhancements(
      service,
      trackId,
      errors,
    );
    return SpeechEnhancementLoadResult(
      timeline: timeline,
      timingsBySentence: _groupWordTimings(timings),
      chunkPartitionsBySentence: partitions,
      senseGroupsBySentence: senseGroups,
      pronunciationBySentence: {
        for (final analysis in analyses) analysis.sentenceId: analysis,
      },
      pronunciationProviders: providers,
      phoneticAnalysisBySentence: soundPatterns,
      errors: errors,
    );
  }

  Future<TimelineResourceLoadResult> loadTimelineResource({
    required LocalApi service,
    required String trackId,
    required ExistingTimelineResourceState previous,
  }) async {
    final errors = <ApiFailure>[];
    late List<WordTimelineSummary> summaries;
    late List<PhoneTimelineSummary> phoneSummaries;
    late List<ChunkTimelineSummary> chunkSummaries;
    LLTimelineDocument? document;

    try {
      summaries = await service.trackWordTimelineSummaries(trackId);
    } catch (error) {
      errors.add(describeApiFailure(error));
      summaries = previous.wordSummaries;
    }

    try {
      phoneSummaries = await service.trackPhoneTimelineSummaries(trackId);
    } catch (error) {
      errors.add(describeApiFailure(error));
      phoneSummaries = previous.phoneSummaries;
    }

    try {
      chunkSummaries = await service.trackChunkTimelineSummaries(trackId);
    } catch (error) {
      errors.add(describeApiFailure(error));
      chunkSummaries = previous.chunkSummaries;
    }

    try {
      final exportedDocument = await service.exportTrackLLTimeline(trackId);
      final preservedArtifacts = previous.document?.artifacts ?? const [];
      // The export endpoint derives fresh rhythm frames from the current word
      // timeline. An older imported document may still carry artifacts that
      // are not re-emitted by that endpoint, but it must never replace the
      // freshly exported document wholesale: doing so discards the derived
      // rhythm frames and makes A/B appear unavailable after transcription.
      document =
          exportedDocument.artifacts.isEmpty && preservedArtifacts.isNotEmpty
          ? LLTimelineDocument(
              schema: exportedDocument.schema,
              metadata: exportedDocument.metadata,
              activeWordTimelineId: exportedDocument.activeWordTimelineId,
              activePhoneTimelineId: exportedDocument.activePhoneTimelineId,
              activeChunkTimelineId: exportedDocument.activeChunkTimelineId,
              rhythmFrames: exportedDocument.rhythmFrames,
              artifacts: preservedArtifacts,
            )
          : exportedDocument;
    } catch (error) {
      errors.add(describeApiFailure(error));
      document = previous.document;
    }

    final hasTimelineData =
        summaries.isNotEmpty ||
        phoneSummaries.isNotEmpty ||
        chunkSummaries.isNotEmpty ||
        document != null;
    if (!hasTimelineData && errors.length == 4) {
      return TimelineResourceLoadResult(
        wordSummaries: summaries,
        phoneSummaries: phoneSummaries,
        chunkSummaries: chunkSummaries,
        document: document,
        error: 'Timeline resource unavailable',
        failures: errors,
        unavailable: true,
      );
    }
    return TimelineResourceLoadResult(
      wordSummaries: summaries,
      phoneSummaries: phoneSummaries,
      chunkSummaries: chunkSummaries,
      document: document,
      error: errors.isEmpty ? null : 'Timeline resource refresh warning',
      failures: errors,
    );
  }

  Future<Map<String, PhoneticAnalysis>> _loadSoundPatternAnalyses(
    LocalApi service,
    String trackId,
    List<PhoneTimelineSummary> phoneSummaries,
    List<ApiFailure> errors,
  ) async {
    final active = phoneSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    if (active != null) {
      try {
        final timeline = await service.phoneTimeline(active.id);
        final sentenceId = timeline.sentenceId;
        if (sentenceId != null) {
          return {
            sentenceId: PhoneticAnalysis.fromJson(
              timeline.toSoundPatternJson(),
            ),
          };
        }
      } catch (error) {
        errors.add(describeApiFailure(error));
      }
    }
    final phoneticAnalyses = await _loadOptionalResourceCapability(
      () => service.trackPhoneticAnalyses(trackId),
      errors,
    );
    final latest = <String, PhoneticAnalysis>{};
    for (final analysis in phoneticAnalyses) {
      final sentenceId = analysis.sentenceId;
      if (sentenceId != null) latest.putIfAbsent(sentenceId, () => analysis);
    }
    return latest;
  }

  Future<List<PronunciationAnalysis>> _loadPronunciationEnhancements(
    LocalApi service,
    String trackId,
    List<ApiFailure> errors,
  ) async {
    try {
      return await service.trackPronunciation(trackId);
    } catch (error) {
      errors.add(describeApiFailure(error));
      return const [];
    }
  }

  Future<Map<String, SentenceChunkPartition>> _loadChunkPartitions(
    LocalApi service,
    String trackId,
    List<ChunkTimelineSummary> chunkSummaries,
    List<ApiFailure> errors,
  ) async {
    final active = chunkSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    if (active != null) {
      try {
        return chunkPartitionsFromTimeline(
          await service.chunkTimeline(active.id),
        );
      } catch (error) {
        errors.add(describeApiFailure(error));
      }
    }
    final partitions = await _loadOptionalResourceCapability(
      () => service.trackChunkPartitions(trackId),
      errors,
    );
    return {
      for (final partition in partitions) partition.sentenceId: partition,
    };
  }

  Future<Map<String, List<SenseGroup>>> _loadSenseGroups(
    LocalApi service,
    String trackId,
    List<ApiFailure> errors,
  ) async {
    late List<SenseGroupAnalysis> analyses;
    try {
      analyses = await service.trackSenseGroupAnalyses(trackId);
    } catch (error) {
      errors.add(describeApiFailure(error));
      return const {};
    }

    final grouped = _activeSenseGroupsBySentence(analyses);
    if (grouped.isNotEmpty ||
        !_senseGroupFallbackAttemptedTrackIds.add(trackId)) {
      return grouped;
    }

    try {
      final generated = await service.generateSenseGroupAnalysis(trackId);
      await service.activateSenseGroupAnalysis(generated.id);
      return _activeSenseGroupsBySentence(
        await service.trackSenseGroupAnalyses(trackId),
      );
    } catch (error) {
      errors.add(describeApiFailure(error));
      return const {};
    }
  }

  Map<String, List<SenseGroup>> _activeSenseGroupsBySentence(
    List<SenseGroupAnalysis> analyses,
  ) {
    final active = analyses.where((analysis) => analysis.isActive).firstOrNull;
    if (active == null) return const {};
    final grouped = <String, List<SenseGroup>>{};
    for (final group in active.groups) {
      grouped.putIfAbsent(group.sentenceId, () => []).add(group);
    }
    return grouped;
  }

  Future<List<T>> _loadOptionalResourceCapability<T>(
    Future<List<T>> Function() loader,
    List<ApiFailure> errors,
  ) async {
    try {
      return await loader();
    } catch (error) {
      errors.add(describeApiFailure(error));
      return const [];
    }
  }

  Map<String, List<WordTiming>> _groupWordTimings(List<WordTiming> timings) {
    final grouped = <String, List<WordTiming>>{};
    for (final value in timings) {
      grouped.putIfAbsent(value.sentenceId, () => []).add(value);
    }
    for (final values in grouped.values) {
      values.sort(
        (a, b) => a.start == b.start
            ? a.tokenIndex.compareTo(b.tokenIndex)
            : a.start.compareTo(b.start),
      );
    }
    return grouped;
  }
}
