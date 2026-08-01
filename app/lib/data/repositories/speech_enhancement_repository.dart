import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

/// Data boundary for timeline, pronunciation, chunking and sense-group reads.
abstract interface class SpeechEnhancementRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);

  Future<List<WordTimelineSummary>> wordTimelineSummaries(String trackId);
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId);
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(String trackId);
  Future<LLTimelineDocument> exportTimeline(String trackId);
  Future<List<WordTiming>> wordTimings(String trackId);
  Future<List<PronunciationProvider>> pronunciationProviders();
  Future<PhoneTimeline> phoneTimeline(String timelineId);
  Future<List<PhoneticAnalysis>> phoneticAnalyses(String trackId);
  Future<List<PronunciationAnalysis>> pronunciationAnalyses(String trackId);
  Future<ChunkTimeline> chunkTimeline(String timelineId);
  Future<List<SentenceChunkPartition>> chunkPartitions(String trackId);
  Future<List<SenseGroupAnalysis>> senseGroupAnalyses(String trackId);
  Future<SenseGroupAnalysis> generateSenseGroups(String trackId);
  Future<void> activateSenseGroups(String analysisId);
}

class UnavailableSpeechEnhancementRepository
    implements SpeechEnhancementRepository {
  const UnavailableSpeechEnhancementRepository();

  Never _unavailable() =>
      throw StateError('Speech enhancement repository is unavailable');

  @override
  bool get isAvailable => false;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<void> activateSenseGroups(String analysisId) => _unavailable();
  @override
  Future<ChunkTimeline> chunkTimeline(String timelineId) => _unavailable();
  @override
  Future<List<SentenceChunkPartition>> chunkPartitions(String trackId) =>
      _unavailable();
  @override
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(String trackId) =>
      _unavailable();
  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) => _unavailable();
  @override
  Future<SenseGroupAnalysis> generateSenseGroups(String trackId) =>
      _unavailable();
  @override
  Future<PhoneTimeline> phoneTimeline(String timelineId) => _unavailable();
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId) =>
      _unavailable();
  @override
  Future<List<PhoneticAnalysis>> phoneticAnalyses(String trackId) =>
      _unavailable();
  @override
  Future<List<PronunciationAnalysis>> pronunciationAnalyses(String trackId) =>
      _unavailable();
  @override
  Future<List<PronunciationProvider>> pronunciationProviders() =>
      _unavailable();
  @override
  Future<List<SenseGroupAnalysis>> senseGroupAnalyses(String trackId) =>
      _unavailable();
  @override
  Future<List<WordTimelineSummary>> wordTimelineSummaries(String trackId) =>
      _unavailable();
  @override
  Future<List<WordTiming>> wordTimings(String trackId) => _unavailable();
}

class LocalSpeechEnhancementRepository implements SpeechEnhancementRepository {
  LocalSpeechEnhancementRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Speech enhancement API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<List<WordTimelineSummary>> wordTimelineSummaries(String trackId) =>
      _api.trackWordTimelineSummaries(trackId);

  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId) =>
      _api.trackPhoneTimelineSummaries(trackId);

  @override
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(String trackId) =>
      _api.trackChunkTimelineSummaries(trackId);

  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) =>
      _api.exportTrackLLTimeline(trackId);

  @override
  Future<List<WordTiming>> wordTimings(String trackId) =>
      _api.trackWordTimings(trackId);

  @override
  Future<List<PronunciationProvider>> pronunciationProviders() =>
      _api.pronunciationProviders();

  @override
  Future<PhoneTimeline> phoneTimeline(String timelineId) =>
      _api.phoneTimeline(timelineId);

  @override
  Future<List<PhoneticAnalysis>> phoneticAnalyses(String trackId) =>
      _api.trackPhoneticAnalyses(trackId);

  @override
  Future<List<PronunciationAnalysis>> pronunciationAnalyses(String trackId) =>
      _api.trackPronunciation(trackId);

  @override
  Future<ChunkTimeline> chunkTimeline(String timelineId) =>
      _api.chunkTimeline(timelineId);

  @override
  Future<List<SentenceChunkPartition>> chunkPartitions(String trackId) =>
      _api.trackChunkPartitions(trackId);

  @override
  Future<List<SenseGroupAnalysis>> senseGroupAnalyses(String trackId) =>
      _api.trackSenseGroupAnalyses(trackId);

  @override
  Future<SenseGroupAnalysis> generateSenseGroups(String trackId) =>
      _api.generateSenseGroupAnalysis(trackId);

  @override
  Future<void> activateSenseGroups(String analysisId) async {
    await _api.activateSenseGroupAnalysis(analysisId);
  }
}
