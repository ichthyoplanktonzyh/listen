part of '../api_service.dart';

// Subtitle/LLTimeline import-export, track lifecycle, OpenSubtitles.
// Split out of api_service.dart (mechanical decomposition).

extension SubtitlesApi on LocalApi {
  /// Imports a subtitle file. When [language] is null the core detects the
  /// learning language from the subtitle script (so a Chinese subtitle is
  /// segmented as Chinese), instead of assuming English.
  Future<Map<String, dynamic>> importSubtitle(
    String mediaId,
    String path, {
    String? language,
  }) async =>
      (await _request('POST', '/v1/media/$mediaId/subtitles', {
            'path': path,
            'language': ?language,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> mediaSubtitles(String mediaId) async =>
      ((await _request('GET', '/v1/media/$mediaId/subtitles')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> importLLTimeline(
    Map<String, dynamic> document,
  ) async =>
      (await _request('POST', '/v1/lltimeline/import', document))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> importLLTimelineForMedia(
    String mediaId,
    Map<String, dynamic> document, {
    bool allowMismatch = false,
  }) async =>
      (await _request(
            'POST',
            '/v1/media/$mediaId/lltimeline/import?allow_mismatch=$allowMismatch',
            document,
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> readSubtitle(String trackId) async =>
      (await _request('GET', '/v1/subtitles/${Uri.encodeComponent(trackId)}'))
          as Map<String, dynamic>;

  /// Dual-dimension content fit for the track's media (ADR 0018). Served
  /// from the backend cache; safe to call on every resource refresh.
  Future<ContentDifficultyProfile> trackContentFit(String trackId) async =>
      ContentDifficultyProfile.fromJson((await _request(
            'GET',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/content-fit',
          )) as Map<String, dynamic>);

  Future<List<Map<String, dynamic>>> coldStartWords(
    String trackId, {
    int limit = 20,
  }) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/cold-start-words?limit=$limit',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> archiveSubtitle(String trackId) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> restoreSubtitle(String trackId) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/restore',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deleteSubtitle(String trackId) async =>
      (await _request(
            'DELETE',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> exportTrackLLTimeline(String trackId) async =>
      (await _request(
            'GET',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/lltimeline/export',
          ))
          as Map<String, dynamic>;

  Future<String> exportSubtitleSrt(String trackId) async {
    final request = await _client.getUrl(
      Uri.parse(
        '$baseUrl/v1/subtitles/${Uri.encodeComponent(trackId)}/export?format=srt',
      ),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(text);
    }
    return text;
  }

  Future<void> updateTrackLanguage(String trackId, String language) async {
    await _request('PATCH', '/v1/subtitles/$trackId/language', {
      'language': language,
    });
  }

  Future<List<Map<String, dynamic>>> searchOpenSubtitles({
    required String apiKey,
    String? query,
    String? moviehash,
    String language = 'en',
  }) async =>
      ((await _request('POST', '/v1/subtitle-search', {
                'provider': 'opensubtitles',
                'api_key': apiKey,
                'language': language,
                if (query != null && query.isNotEmpty) 'query': query,
                if (moviehash != null && moviehash.isNotEmpty)
                  'moviehash': moviehash,
              }))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<String> openSubtitlesMovieHash(String path) =>
      computeOpenSubtitlesMovieHash(path);

  Future<String> downloadOpenSubtitle({
    required String apiKey,
    required int fileId,
  }) async {
    final request = await _client.postUrl(
      Uri.parse('$baseUrl/v1/subtitle-search/download'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(
      jsonEncode({
        'provider': 'opensubtitles',
        'api_key': apiKey,
        'file_id': fileId,
      }),
    );
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      [],
      (all, next) => all..addAll(next),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(utf8.decode(bytes));
    }
    final directory = Directory.systemTemp.createTempSync(
      'llplayernext-subtitle-',
    );
    final path = '${directory.path}/opensubtitles-$fileId.srt';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
