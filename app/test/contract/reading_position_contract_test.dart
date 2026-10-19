import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/reading.dart';

/// Committed fixture contract test for the Phase 3.13 reading cursor DTO.
/// Pins the Dart shape to `/v1/reading/positions/{track_id}` in
/// contracts/openapi/v1.yaml (schema `ReadingPosition`).
void main() {
  group('ReadingPositionView', () {
    test('parses a full position', () {
      final view = ReadingPositionView.fromJson(const {
        'track_id': 'track-1',
        'media_id': 'media-1',
        'anchor_cue_id': 'cue-a',
        'paragraph_index': 3,
        'updated_at_ms': 1800000000000,
      });
      expect(view.trackId, 'track-1');
      expect(view.mediaId, 'media-1');
      expect(view.anchorCueId, 'cue-a');
      expect(view.paragraphIndex, 3);
      expect(view.updatedAtMs, 1800000000000);
    });

    test('media_id is nullable (media may be deleted later)', () {
      final view = ReadingPositionView.fromJson(const {
        'track_id': 'track-1',
        'media_id': null,
        'anchor_cue_id': 'cue-b',
        'paragraph_index': 0,
        'updated_at_ms': 5,
      });
      expect(view.mediaId, isNull);
    });
  });
}
