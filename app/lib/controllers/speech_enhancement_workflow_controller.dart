import '../data/repositories/speech_enhancement_repository.dart';
import '../models/api_failure.dart';
import '../models/timeline.dart';
import '../models/types.dart';

class ExistingTimelineResourceState {
  ExistingTimelineResourceState({
    List<WordTimelineSummary> wordSummaries = const [],
    List<PhoneTimelineSummary> phoneSummaries = const [],
    this.document,
  }) : _wordSummaries = List.unmodifiable(wordSummaries),
       _phoneSummaries = List.unmodifiable(phoneSummaries);

  final List<WordTimelineSummary> _wordSummaries;
  List<WordTimelineSummary> get wordSummaries =>
      List.unmodifiable(_wordSummaries);
  final List<PhoneTimelineSummary> _phoneSummaries;
  List<PhoneTimelineSummary> get phoneSummaries =>
      List.unmodifiable(_phoneSummaries);
  final LLTimelineDocument? document;
}

class TimelineResourceLoadResult {
  TimelineResourceLoadResult({
    List<WordTimelineSummary> wordSummaries = const [],
    List<PhoneTimelineSummary> phoneSummaries = const [],
    this.document,
    this.error,
    List<ApiFailure> failures = const [],
    this.unavailable = false,
  }) : _wordSummaries = List.unmodifiable(wordSummaries),
       _phoneSummaries = List.unmodifiable(phoneSummaries),
       _failures = List.unmodifiable(failures);

  final List<WordTimelineSummary> _wordSummaries;
  List<WordTimelineSummary> get wordSummaries =>
      List.unmodifiable(_wordSummaries);
  final List<PhoneTimelineSummary> _phoneSummaries;
  List<PhoneTimelineSummary> get phoneSummaries =>
      List.unmodifiable(_phoneSummaries);
  final LLTimelineDocument? document;

  /// The named state, or null when nothing failed. One sentence — the four
  /// loaders' exceptions used to be joined into it with semicolons, which put
  /// up to four loopback URIs on a resource panel.
  final String? error;

  /// What each failed loader answered with, kept typed and off screen.
  final List<ApiFailure> _failures;
  List<ApiFailure> get failures => List.unmodifiable(_failures);
  final bool unavailable;
}

class SpeechEnhancementLoadResult {
  SpeechEnhancementLoadResult({
    required this.timeline,
    Map<String, List<WordTiming>> timingsBySentence = const {},
    Map<String, SentenceChunkPartition> chunkPartitionsBySentence = const {},
    Map<String, List<SenseGroup>> senseGroupsBySentence = const {},
    Map<String, PronunciationAnalysis> pronunciationBySentence = const {},
    List<PronunciationProvider> pronunciationProviders = const [],
    Map<String, PhoneticAnalysis> phoneticAnalysisBySentence = const {},
    List<ApiFailure> errors = const [],
  }) : _timingsBySentence = Map.unmodifiable({
         for (final entry in timingsBySentence.entries)
           entry.key: List<WordTiming>.unmodifiable(entry.value),
       }),
       _chunkPartitionsBySentence = Map.unmodifiable(chunkPartitionsBySentence),
       _senseGroupsBySentence = Map.unmodifiable({
         for (final entry in senseGroupsBySentence.entries)
           entry.key: List<SenseGroup>.unmodifiable(entry.value),
       }),
       _pronunciationBySentence = Map.unmodifiable(pronunciationBySentence),
       _pronunciationProviders = List.unmodifiable(pronunciationProviders),
       _phoneticAnalysisBySentence = Map.unmodifiable(
         phoneticAnalysisBySentence,
       ),
       _errors = List.unmodifiable(errors);

  final TimelineResourceLoadResult timeline;
  final Map<String, List<WordTiming>> _timingsBySentence;
  Map<String, List<WordTiming>> get timingsBySentence => Map.unmodifiable({
    for (final entry in _timingsBySentence.entries)
      entry.key: List<WordTiming>.unmodifiable(entry.value),
  });
  final Map<String, SentenceChunkPartition> _chunkPartitionsBySentence;
  Map<String, SentenceChunkPartition> get chunkPartitionsBySentence =>
      Map.unmodifiable(_chunkPartitionsBySentence);
  final Map<String, List<SenseGroup>> _senseGroupsBySentence;
  Map<String, List<SenseGroup>> get senseGroupsBySentence => Map.unmodifiable({
    for (final entry in _senseGroupsBySentence.entries)
      entry.key: List<SenseGroup>.unmodifiable(entry.value),
  });
  final Map<String, PronunciationAnalysis> _pronunciationBySentence;
  Map<String, PronunciationAnalysis> get pronunciationBySentence =>
      Map.unmodifiable(_pronunciationBySentence);
  final List<PronunciationProvider> _pronunciationProviders;
  List<PronunciationProvider> get pronunciationProviders =>
      List.unmodifiable(_pronunciationProviders);
  final Map<String, PhoneticAnalysis> _phoneticAnalysisBySentence;
  Map<String, PhoneticAnalysis> get phoneticAnalysisBySentence =>
      Map.unmodifiable(_phoneticAnalysisBySentence);

  /// Every optional loader that failed, as a typed failure rather than as a
  /// sentence. Callers report *that* some enhancements are missing; what the
  /// backend said about each one stays here.
  final List<ApiFailure> _errors;
  List<ApiFailure> get errors => List.unmodifiable(_errors);
}

class SpeechEnhancementWorkflowController {
  SpeechEnhancementWorkflowController({
    this.repository = const UnavailableSpeechEnhancementRepository(),
  });

  final SpeechEnhancementRepository repository;
  final Set<String> _senseGroupFallbackAttemptedTrackIds = {};

  Future<SpeechEnhancementLoadResult> loadSpeechEnhancements({
    required String trackId,
    required ExistingTimelineResourceState previousTimeline,
  }) async {
    final timeline = await loadTimelineResource(
      trackId: trackId,
      previous: previousTimeline,
    );
    final errors = <ApiFailure>[];
    final timings = await _loadOptionalResourceCapability(
      () => repository.wordTimings(trackId),
      errors,
    );
    final providers = await _loadOptionalResourceCapability(
      repository.pronunciationProviders,
      errors,
    );
    final soundPatterns = await _loadSoundPatternAnalyses(
      trackId,
      timeline.phoneSummaries,
      errors,
    );
    final partitions = await _loadChunkPartitions(trackId, errors);
    final senseGroups = await _loadSenseGroups(trackId, errors);
    final analyses = await _loadPronunciationEnhancements(trackId, errors);
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
    required String trackId,
    required ExistingTimelineResourceState previous,
  }) async {
    final errors = <ApiFailure>[];
    late List<WordTimelineSummary> summaries;
    late List<PhoneTimelineSummary> phoneSummaries;
    LLTimelineDocument? document;

    try {
      summaries = await repository.wordTimelineSummaries(trackId);
    } catch (error) {
      errors.add(repository.failureDetail(error));
      summaries = previous.wordSummaries;
    }

    try {
      phoneSummaries = await repository.phoneTimelineSummaries(trackId);
    } catch (error) {
      errors.add(repository.failureDetail(error));
      phoneSummaries = previous.phoneSummaries;
    }

    try {
      final exportedDocument = await repository.exportTimeline(trackId);
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
              prosodyAnalyses: exportedDocument.prosodyAnalyses,
              activeProsodyAnalysisId: exportedDocument.activeProsodyAnalysisId,
              rhythmFrames: exportedDocument.rhythmFrames,
              artifacts: preservedArtifacts,
            )
          : exportedDocument;
    } catch (error) {
      errors.add(repository.failureDetail(error));
      document = previous.document;
    }

    final hasTimelineData =
        summaries.isNotEmpty ||
        phoneSummaries.isNotEmpty ||
        document != null;
    if (!hasTimelineData && errors.length == 3) {
      return TimelineResourceLoadResult(
        wordSummaries: summaries,
        phoneSummaries: phoneSummaries,
        document: document,
        error: 'Timeline resource unavailable',
        failures: errors,
        unavailable: true,
      );
    }
    return TimelineResourceLoadResult(
      wordSummaries: summaries,
      phoneSummaries: phoneSummaries,
      document: document,
      error: errors.isEmpty ? null : 'Timeline resource refresh warning',
      failures: errors,
    );
  }

  Future<Map<String, PhoneticAnalysis>> _loadSoundPatternAnalyses(
    String trackId,
    List<PhoneTimelineSummary> phoneSummaries,
    List<ApiFailure> errors,
  ) async {
    final active = phoneSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    if (active != null) {
      try {
        final timeline = await repository.phoneTimeline(active.id);
        final sentenceId = timeline.sentenceId;
        if (sentenceId != null) {
          return {
            sentenceId: PhoneticAnalysis.fromJson(
              timeline.toSoundPatternJson(),
            ),
          };
        }
      } catch (error) {
        errors.add(repository.failureDetail(error));
      }
    }
    final phoneticAnalyses = await _loadOptionalResourceCapability(
      () => repository.phoneticAnalyses(trackId),
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
    String trackId,
    List<ApiFailure> errors,
  ) async {
    try {
      return await repository.pronunciationAnalyses(trackId);
    } catch (error) {
      errors.add(repository.failureDetail(error));
      return const [];
    }
  }

  Future<Map<String, SentenceChunkPartition>> _loadChunkPartitions(
    String trackId,
    List<ApiFailure> errors,
  ) async {
    // R5: the persisted ChunkTimeline family was retired. Chunk partitions
    // always come from the live Core partitioner, whose per-sentence spans
    // stay the product-facing chunk replay source.
    final partitions = await _loadOptionalResourceCapability(
      () => repository.chunkPartitions(trackId),
      errors,
    );
    return {
      for (final partition in partitions) partition.sentenceId: partition,
    };
  }

  Future<Map<String, List<SenseGroup>>> _loadSenseGroups(
    String trackId,
    List<ApiFailure> errors,
  ) async {
    late List<SenseGroupAnalysis> analyses;
    try {
      analyses = await repository.senseGroupAnalyses(trackId);
    } catch (error) {
      errors.add(repository.failureDetail(error));
      return const {};
    }

    final grouped = _activeSenseGroupsBySentence(analyses);
    if (grouped.isNotEmpty ||
        !_senseGroupFallbackAttemptedTrackIds.add(trackId)) {
      return grouped;
    }

    try {
      final generated = await repository.generateSenseGroups(trackId);
      await repository.activateSenseGroups(generated.id);
      return _activeSenseGroupsBySentence(
        await repository.senseGroupAnalyses(trackId),
      );
    } catch (error) {
      errors.add(repository.failureDetail(error));
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
      errors.add(repository.failureDetail(error));
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
