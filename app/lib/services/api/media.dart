part of '../api_service.dart';

// Media registration, library/triage, playback progress, languages.
// Split out of api_service.dart (mechanical decomposition).

extension MediaApi on LocalApi {
  /// Registers (or re-registers, by fingerprint identity) one media path.
  ///
  /// [retain] is the library-membership flag: `true` is an explicit
  /// Keep (Personal Library), `false` is Temporary Material — opening a file,
  /// scanning a folder, or adopting a download, none of which imply Personal
  /// Library membership on their own.
  ///
  /// [title] overrides the default (derived from the file name). A managed
  /// store keeps content-addressed file names (a SHA-256 digest), which would
  /// make a poor library title, so the Keep flow passes the original title.
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
    String? title,
    String? kind,
  }) async {
    final fingerprint = await fingerprintFile(path);
    return MediaItem.fromJson(
      (await _request('POST', '/v1/media', {
            'path': path,
            'fingerprint': fingerprint.toString(),
            'title': title ?? path.split(Platform.pathSeparator).last,
            'kind': kind ?? (LocalApi._isAudio(path) ? 'audio' : 'video'),
            'duration_ms': ?durationMs,
            'retain': retain,
          }))
          as Map<String, dynamic>,
    );
  }

  /// Adds one media to the Personal Library without changing its path (Core
  /// library-membership). The media must already be registered.
  Future<MediaItem> retainMedia(String mediaId) async => MediaItem.fromJson(
    (await _request(
          'PUT',
          '/v1/media/${Uri.encodeComponent(mediaId)}/library-membership',
        ))
        as Map<String, dynamic>,
  );

  /// Removes one media from the Personal Library. Membership only: the media
  /// record, its files, and learning state are untouched.
  Future<MediaItem> unretainMedia(String mediaId) async => MediaItem.fromJson(
    (await _request(
          'DELETE',
          '/v1/media/${Uri.encodeComponent(mediaId)}/library-membership',
        ))
        as Map<String, dynamic>,
  );

  Future<String> fingerprintFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<MediaItem> readMedia(String mediaId) async => MediaItem.fromJson(
    (await _request('GET', '/v1/media/${Uri.encodeComponent(mediaId)}'))
        as Map<String, dynamic>,
  );

  /// Media library for triage: every registered media with
  /// cached fit facts, user triage intent, and familiar-material mark.
  Future<List<MediaLibraryEntry>> listMediaLibrary() async =>
      ((await _request('GET', '/v1/media')) as List<dynamic>)
          .map(
            (value) => MediaLibraryEntry.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);

  /// Stores (or clears, with null) the explicit triage intent for one media
  /// and returns the refreshed library entry.
  Future<MediaLibraryEntry> setMediaTriageIntent(
    String mediaId,
    String? intent,
  ) async => MediaLibraryEntry.fromJson(
    (await _request(
          'PUT',
          '/v1/media/${Uri.encodeComponent(mediaId)}/triage-intent',
          {'intent': intent},
        ))
        as Map<String, dynamic>,
  );

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
