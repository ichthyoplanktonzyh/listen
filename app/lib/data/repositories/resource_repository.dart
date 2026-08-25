import '../../models/api_failure.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';
import '../../services/core_timeline_export.dart';

abstract interface class ResourceRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);
  Future<ContentDifficultyProfile> contentFit(String trackId);
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId);
  Future<List<WordTiming>> wordTimings(String trackId);
  Future<CoreTimelineExport> exportTimelineJson(String trackId);
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId);
  Future<void> archiveSubtitle(String trackId);
  Future<void> restoreSubtitle(String trackId);
  Future<void> deleteSubtitle(String trackId);
  Future<String> exportSubtitleSrt(String trackId);
  Future<LLTimelineDocument> exportTimeline(String trackId);
  Future<void> updateTrackLanguage(String trackId, String language);
  Future<void> activateWordTimeline(String timelineId);
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
  Future<CoreTimelineExport> exportTimelineJson(String trackId) async =>
      CoreTimelineExport(await _api.exportTrackLLTimelineJson(trackId));
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(String trackId) =>
      _api.trackPhoneTimelineSummaries(trackId);
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
  Future<void> activatePhoneTimeline(String timelineId) async =>
      _api.activatePhoneTimeline(timelineId);
  @override
  Future<void> archivePhoneTimeline(String timelineId) async =>
      _api.archivePhoneTimeline(timelineId);
  @override
  Future<void> deletePhoneTimeline(String timelineId) async =>
      _api.deletePhoneTimeline(timelineId);
}
