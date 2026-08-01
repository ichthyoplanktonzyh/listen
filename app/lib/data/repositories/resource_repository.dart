import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

abstract interface class ResourceRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);
  Future<ContentDifficultyProfile> contentFit(String trackId);
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId);
  Future<List<WordTiming>> wordTimings(String trackId);
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId);
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(String trackId);
  Future<void> archiveSubtitle(String trackId);
  Future<void> restoreSubtitle(String trackId);
  Future<void> deleteSubtitle(String trackId);
  Future<String> exportSubtitleSrt(String trackId);
  Future<LLTimelineDocument> exportTimeline(String trackId);
  Future<void> updateTrackLanguage(String trackId, String language);
  Future<void> activateWordTimeline(String timelineId);
  Future<void> generateChunkTimeline(String trackId);
  Future<void> activateChunkTimeline(String timelineId);
  Future<void> archiveChunkTimeline(String timelineId);
  Future<void> deleteChunkTimeline(String timelineId);
  Future<void> activatePhoneTimeline(String timelineId);
  Future<void> archivePhoneTimeline(String timelineId);
  Future<void> deletePhoneTimeline(String timelineId);
}

class LocalResourceRepository implements ResourceRepository {
  LocalResourceRepository(this._getApi);
  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Resource API is unavailable'));
  @override
  bool get isAvailable => _getApi() != null;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) =>
      _api.trackContentFit(trackId);
  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) =>
      _api.mediaSubtitles(mediaId);
  @override
  Future<List<WordTiming>> wordTimings(String trackId) =>
      _api.trackWordTimings(trackId);
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId) =>
      _api.trackPhoneTimelineSummaries(trackId);
  @override
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(String trackId) =>
      _api.trackChunkTimelineSummaries(trackId);
  @override
  Future<void> archiveSubtitle(String trackId) => _api.archiveSubtitle(trackId);
  @override
  Future<void> restoreSubtitle(String trackId) => _api.restoreSubtitle(trackId);
  @override
  Future<void> deleteSubtitle(String trackId) => _api.deleteSubtitle(trackId);
  @override
  Future<String> exportSubtitleSrt(String trackId) =>
      _api.exportSubtitleSrt(trackId);
  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) =>
      _api.exportTrackLLTimeline(trackId);
  @override
  Future<void> updateTrackLanguage(String trackId, String language) =>
      _api.updateTrackLanguage(trackId, language);
  @override
  Future<void> activateWordTimeline(String timelineId) async =>
      _api.activateWordTimeline(timelineId);
  @override
  Future<void> generateChunkTimeline(String trackId) async =>
      _api.generateChunkTimeline(trackId, status: 'active');
  @override
  Future<void> activateChunkTimeline(String timelineId) async =>
      _api.activateChunkTimeline(timelineId);
  @override
  Future<void> archiveChunkTimeline(String timelineId) async =>
      _api.archiveChunkTimeline(timelineId);
  @override
  Future<void> deleteChunkTimeline(String timelineId) async =>
      _api.deleteChunkTimeline(timelineId);
  @override
  Future<void> activatePhoneTimeline(String timelineId) async =>
      _api.activatePhoneTimeline(timelineId);
  @override
  Future<void> archivePhoneTimeline(String timelineId) async =>
      _api.archivePhoneTimeline(timelineId);
  @override
  Future<void> deletePhoneTimeline(String timelineId) async =>
      _api.deletePhoneTimeline(timelineId);
}
