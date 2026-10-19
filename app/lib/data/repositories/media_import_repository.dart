import '../../models/api_failure.dart';
import '../../models/media_download.dart';
import '../../services/enclosure_download_service.dart';
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

  /// Fetches a publisher-provided media URL directly.
  ///
  /// Separate from [downloadOnlineMedia] because it is a different capability,
  /// not a different implementation of one: no external tool, no page to
  /// extract from, and a policy that stands on its own. [expectedBytes] is the
  /// size the feed advertised, used only for progress when the response omits
  /// `Content-Length`.
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  });

  /// Fetches a document item's page, for the article acquisition path.
  ///
  /// A feed that offers an article link grants fetching the page; the bytes
  /// land in [directory] and the returned path is taken in through the same
  /// document intake a local file would travel. Null when the fetch was
  /// cancelled.
  Future<String?> downloadArticle(String articleUrl, String directory);

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
  LocalMediaImportRepository(
    this._tools, [
    this._files = const LocalMediaImportFileService(),
    this._failureMapper,
    EnclosureDownloadService? enclosures,
  ]) : _enclosures = enclosures ?? EnclosureDownloadService();

  final ExternalTools _tools;
  final MediaImportFileService _files;
  final ApiFailure Function(Object error)? _failureMapper;
  final EnclosureDownloadService _enclosures;

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
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  }) async =>
      _enclosures.start(mediaUrl, directory, expectedBytes: expectedBytes);

  @override
  Future<String?> downloadArticle(String articleUrl, String directory) =>
      _enclosures.start(articleUrl, directory).completed;

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
