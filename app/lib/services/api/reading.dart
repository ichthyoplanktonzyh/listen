part of '../api_service.dart';

// Reading posture (Phase 3.13): per-track reading cursor.

extension ReadingApi on LocalApi {
  /// The saved reading cursor for [trackId], or null when never saved.
  Future<ReadingPositionView?> readingPosition(String trackId) async {
    final json = await _request(
      'GET',
      '/v1/reading/positions/${Uri.encodeComponent(trackId)}',
    );
    if (json == null) return null;
    return ReadingPositionView.fromJson(json as Map<String, dynamic>);
  }

  /// Upserts the reading cursor for [trackId]. The position is a cursor, not
  /// evidence — overwriting is intended.
  Future<ReadingPositionView> saveReadingPosition({
    required String trackId,
    String? mediaId,
    required String anchorCueId,
    required int paragraphIndex,
  }) async => ReadingPositionView.fromJson(
    (await _request(
          'PUT',
          '/v1/reading/positions/${Uri.encodeComponent(trackId)}',
          {
            'media_id': ?mediaId,
            'anchor_cue_id': anchorCueId,
            'paragraph_index': paragraphIndex,
          },
        ))
        as Map<String, dynamic>,
  );
}
