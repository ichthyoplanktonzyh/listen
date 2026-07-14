part of '../api_service.dart';

// Media registration, library/triage, playback progress, languages.
// Split out of api_service.dart (mechanical decomposition).

extension MediaApi on LocalApi {
  Future<Map<String, dynamic>> registerMedia(String path) async {
    final fingerprint = await fingerprintFile(path);
    return (await _request('POST', '/v1/media', {
          'path': path,
          'fingerprint': fingerprint.toString(),
          'title': path.split(Platform.pathSeparator).last,
          'kind': LocalApi._isAudio(path) ? 'audio' : 'video',
        }))
        as Map<String, dynamic>;
  }

  Future<String> fingerprintFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<Map<String, dynamic>> readMedia(String mediaId) async =>
      (await _request('GET', '/v1/media/${Uri.encodeComponent(mediaId)}'))
          as Map<String, dynamic>;

  /// Media library for triage (Phase 3.5): every registered media with
  /// cached fit facts, user triage intent, and familiar-material mark.
  Future<List<dynamic>> listMediaLibrary() async =>
      (await _request('GET', '/v1/media')) as List<dynamic>;

  /// Stores (or clears, with null) the explicit triage intent for one media
  /// and returns the refreshed library entry.
  Future<MediaLibraryEntry> setMediaTriageIntent(
    String mediaId,
    String? intent,
  ) async =>
      MediaLibraryEntry.fromJson((await _request(
            'PUT',
            '/v1/media/${Uri.encodeComponent(mediaId)}/triage-intent',
            {'intent': intent},
          )) as Map<String, dynamic>);

  Future<void> setMediaAvailability(String mediaId, String availability) async {
    await _request('PUT', '/v1/media/$mediaId/availability', {
      'availability': availability,
    });
  }

  Future<List<String>> listLanguages() async =>
      ((await _request('GET', '/v1/languages')) as List<dynamic>)
          .cast<String>();

  Future<LanguageProfile> lookupLanguageProfile(String code) async =>
      LanguageProfile.fromJson(
        (await _request(
              'GET',
              '/v1/languages/${Uri.encodeComponent(code)}/profile',
            ))
            as Map<String, dynamic>,
      );

  Future<void> saveProgress(String mediaId, Duration position) async {
    await _request('PUT', '/v1/media/$mediaId/progress', {
      'position_ms': position.inMilliseconds,
    });
  }

  Future<Duration?> readProgress(String mediaId) async {
    final value =
        (await _request('GET', '/v1/media/$mediaId/progress'))
            as Map<String, dynamic>;
    final milliseconds = value['position_ms'] as int?;
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }
}
