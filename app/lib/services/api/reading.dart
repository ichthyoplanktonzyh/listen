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

  /// Records one explicit reading mark ("understood / didn't understand
  /// while reading") as a reading-channel observation. Assistance honesty:
  /// [translationVisible] reflects whether the paragraph translation was
  /// shown at marking time.
  Future<void> recordReadingMarking({
    required String lexicalEntryId,
    String? sentenceId,
    required String surfaceForm,
    String? mediaId,
    required bool translationVisible,
    required bool understood,
  }) async {
    await _request('POST', '/v1/reading/markings', {
      'lexical_entry_id': lexicalEntryId,
      'sentence_id': ?sentenceId,
      'surface_form': surfaceForm,
      'media_id': ?mediaId,
      'translation_visible': translationVisible,
      'understood': understood,
    });
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
