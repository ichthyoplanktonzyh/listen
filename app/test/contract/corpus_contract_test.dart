import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// Committed fixture contract test for CorpusOccurrence DTOs (Phase 3.6
/// Slice 3). Validates that the Dart DTO shape matches the Rust API response
/// shape documented in contracts/openapi/v1.yaml (ADR 0014).
void main() {
  const fixture = {
    'id': 'corpus-occurrence-1',
    'language': 'en',
    'kind': 'chunk',
    'normalized_key': 'take care',
    'display_text': 'Take care',
    'media_id': 'media-1',
    'track_id': 'track-1',
    'sentence_id': 'sentence-1',
    'start_ms': 1200,
    'end_ms': 1800,
    'source_snapshot': 'Take care',
  };

  group('CorpusOccurrence', () {
    test('parses the wire shape', () {
      final occurrence = CorpusOccurrence.fromJson(fixture);
      expect(occurrence.id, 'corpus-occurrence-1');
      expect(occurrence.language, 'en');
      expect(occurrence.kind, 'chunk');
      expect(occurrence.normalizedKey, 'take care');
      expect(occurrence.displayText, 'Take care');
      expect(occurrence.mediaId, 'media-1');
      expect(occurrence.trackId, 'track-1');
      expect(occurrence.sentenceId, 'sentence-1');
      expect(occurrence.startMs, 1200);
      expect(occurrence.endMs, 1800);
      expect(occurrence.sourceSnapshot, 'Take care');
    });

    test('tolerates a corpus row that outlived its media record', () {
      final unlinked = Map<String, dynamic>.from(fixture)
        ..['media_id'] = null
        ..['track_id'] = null
        ..['sentence_id'] = null
        ..['normalized_key'] = null;
      final occurrence = CorpusOccurrence.fromJson(unlinked);
      expect(occurrence.mediaId, isNull);
      expect(occurrence.trackId, isNull);
      expect(occurrence.sentenceId, isNull);
      expect(occurrence.normalizedKey, isNull);
    });

    test('round-trips through toJson', () {
      final occurrence = CorpusOccurrence.fromJson(fixture);
      expect(occurrence.toJson(), fixture);
    });
  });
}
