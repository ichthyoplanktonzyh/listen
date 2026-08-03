import '../../models/api_failure.dart';
import '../../models/media_download.dart';
import '../../services/external_tools.dart';
import '../../services/media_import_file_service.dart';

abstract interface class MediaImportRepository {
  ApiFailure failureDetail(Object error);
  Future<String?> pickDownloadDirectory({required String confirmButtonText});
  Future<String> resolveOnlineMedia(String pageUrl);
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  );
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl);
  Future<ResolvedChannelDetails> resolveChannelDetails(String channelUrl);
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath);
  Future<int?> probeMediaDurationMs(String mediaPath);
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  );
}

final class LocalMediaImportRepository implements MediaImportRepository {
  const LocalMediaImportRepository(
    this._tools, [
    this._files = const LocalMediaImportFileService(),
    this._failureMapper,
  ]);

  final ExternalTools _tools;
  final MediaImportFileService _files;
  final ApiFailure Function(Object error)? _failureMapper;

  @override
  ApiFailure failureDetail(Object error) =>
      _failureMapper?.call(error) ??
      ApiFailure(message: 'The operation failed.', raw: error.toString());

  @override
  Future<String?> pickDownloadDirectory({required String confirmButtonText}) =>
      _files.pickDownloadDirectory(confirmButtonText: confirmButtonText);

  @override
  Future<String> resolveOnlineMedia(String pageUrl) =>
      _tools.resolveOnlineMedia(pageUrl);

  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) => _tools.downloadOnlineMedia(pageUrl, directory);

  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) =>
      _tools.resolveVideoDetails(pageUrl);

  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(String channelUrl) =>
      _tools.resolveChannelDetails(channelUrl);

  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) =>
      _tools.probeSubtitles(mediaPath);

  @override
  Future<int?> probeMediaDurationMs(String mediaPath) =>
      _tools.probeMediaDurationMs(mediaPath);

  @override
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) => _tools.extractTextSubtitle(mediaPath, subtitle);
}
