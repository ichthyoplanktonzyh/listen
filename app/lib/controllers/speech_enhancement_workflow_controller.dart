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
    this.unavailable = false,
  });

  final List<WordTimelineSummary> wordSummaries;
  final List<PhoneTimelineSummary> phoneSummaries;
  final List<ChunkTimelineSummary> chunkSummaries;
  final LLTimelineDocument? document;
  final String? error;
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
  final List<String> errors;
}

class SpeechEnhancementWorkflowController {
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
    final errors = <String>[];
    final timings = await _loadOptionalResourceCapability(
      () => service.trackWordTimings(trackId),
      'word timing',
      errors,
    );
    final providers = await _loadOptionalResourceCapability(
      service.pronunciationProviders,
      'pronunciation provider',
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
      pronunciationBySentence: Map<String, PronunciationAnalysis>.fromEntries(
        analyses.map((value) {
          final analysis = PronunciationAnalysis.fromJson(value);
          return MapEntry(analysis.sentenceId, analysis);
        }),
      ),
      pronunciationProviders: providers
          .map(PronunciationProvider.fromJson)
          .toList(growable: false),
      phoneticAnalysisBySentence: soundPatterns,
      errors: errors,
    );
  }

  Future<TimelineResourceLoadResult> loadTimelineResource({
    required LocalApi service,
    required String trackId,
    required ExistingTimelineResourceState previous,
  }) async {
    final errors = <String>[];
    late List<WordTimelineSummary> summaries;
    late List<PhoneTimelineSummary> phoneSummaries;
    late List<ChunkTimelineSummary> chunkSummaries;
    LLTimelineDocument? document;

    try {
      final values = await service.trackWordTimelineSummaries(trackId);
      summaries = values
          .map((raw) => WordTimelineSummary.fromJson(raw))
          .toList(growable: false);
    } catch (error) {
      errors.add('summary: $error');
      summaries = previous.wordSummaries;
    }

    try {
      final values = await service.trackPhoneTimelineSummaries(trackId);
      phoneSummaries = values
          .map((raw) => PhoneTimelineSummary.fromJson(raw))
          .toList(growable: false);
    } catch (error) {
      errors.add('phone summary: $error');
      phoneSummaries = previous.phoneSummaries;
    }

    try {
      final values = await service.trackChunkTimelineSummaries(trackId);
      chunkSummaries = values
          .map((raw) => ChunkTimelineSummary.fromJson(raw))
          .toList(growable: false);
    } catch (error) {
      errors.add('chunk summary: $error');
      chunkSummaries = previous.chunkSummaries;
    }

    try {
      final value = await service.exportTrackLLTimeline(trackId);
      final exportedDocument = LLTimelineDocument.fromJson(value);
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
      errors.add('export: $error');
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
        error: 'Timeline resource unavailable: ${errors.join('; ')}',
        unavailable: true,
      );
    }
    return TimelineResourceLoadResult(
      wordSummaries: summaries,
      phoneSummaries: phoneSummaries,
      chunkSummaries: chunkSummaries,
      document: document,
      error: errors.isEmpty
          ? null
          : 'Timeline resource refresh warning: ${errors.join('; ')}',
    );
  }

  Future<Map<String, PhoneticAnalysis>> _loadSoundPatternAnalyses(
    LocalApi service,
    String trackId,
    List<PhoneTimelineSummary> phoneSummaries,
    List<String> errors,
  ) async {
    final active = phoneSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    if (active != null) {
      try {
        final timeline = PhoneTimeline.fromJson(
          await service.phoneTimeline(active.id),
        );
        final sentenceId = timeline.sentenceId;
        if (sentenceId != null) {
          return {
            sentenceId: PhoneticAnalysis.fromJson(
              timeline.toSoundPatternJson(),
            ),
          };
        }
      } catch (error) {
        errors.add('phone timeline: $error');
      }
    }
    final phoneticAnalyses = await _loadOptionalResourceCapability(
      () => service.trackPhoneticAnalyses(trackId),
      'phone',
      errors,
    );
    final latest = latestPhoneticAnalysesBySentence(phoneticAnalyses);
    return latest.map(
      (sentenceId, value) =>
          MapEntry(sentenceId, PhoneticAnalysis.fromJson(value)),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPronunciationEnhancements(
    LocalApi service,
    String trackId,
    List<String> errors,
  ) async {
    try {
      return await service.trackPronunciation(trackId);
    } catch (error) {
      errors.add('pronunciation: $error');
      return const [];
    }
  }

  Future<Map<String, SentenceChunkPartition>> _loadChunkPartitions(
    LocalApi service,
    String trackId,
    List<ChunkTimelineSummary> chunkSummaries,
    List<String> errors,
  ) async {
    final active = chunkSummaries
        .where((summary) => summary.isActive)
        .firstOrNull;
    if (active != null) {
      try {
        return chunkPartitionsFromTimeline(
          ChunkTimeline.fromJson(await service.chunkTimeline(active.id)),
        );
      } catch (error) {
        errors.add('chunk timeline: $error');
      }
    }
    final partitions = await _loadOptionalResourceCapability(
      () => service.trackChunkPartitions(trackId),
      'chunk',
      errors,
    );
    return Map<String, SentenceChunkPartition>.fromEntries(
      partitions.map((raw) {
        final partition = SentenceChunkPartition.fromJson(raw);
        return MapEntry(partition.sentenceId, partition);
      }),
    );
  }

  Future<Map<String, List<SenseGroup>>> _loadSenseGroups(
    LocalApi service,
    String trackId,
    List<String> errors,
  ) async {
    try {
      final rawAnalyses = await service.trackSenseGroupAnalyses(trackId);
      final analyses = rawAnalyses
          .map(SenseGroupAnalysis.fromJson)
          .toList(growable: false);
      final active = analyses.where((a) => a.isActive).firstOrNull;
      if (active == null) return const {};
      final grouped = <String, List<SenseGroup>>{};
      for (final group in active.groups) {
        grouped.putIfAbsent(group.sentenceId, () => []).add(group);
      }
      return grouped;
    } catch (error) {
      errors.add('sense groups: $error');
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> _loadOptionalResourceCapability(
    Future<List<Map<String, dynamic>>> Function() loader,
    String label,
    List<String> errors,
  ) async {
    try {
      return await loader();
    } catch (error) {
      errors.add('$label: $error');
      return const [];
    }
  }

  Map<String, List<WordTiming>> _groupWordTimings(
    List<Map<String, dynamic>> timings,
  ) {
    final grouped = <String, List<WordTiming>>{};
    for (final raw in timings) {
      final value = WordTiming.fromJson(raw);
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
