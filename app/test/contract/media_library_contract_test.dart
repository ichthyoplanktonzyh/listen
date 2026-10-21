import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

/// The listening media-library contract retains media identity and explicit
/// learner triage facts.
void main() {
  const fixture = {
    'media': {
      'id': 'media-1',
      'path': '/tmp/library.mp4',
      'fingerprint': 'library-fp',
      'title': 'Library',
      'kind': 'video',
      'duration': 90000,
      'availability': 'available',
      'retained_at_ms': null,
      'created_at_ms': 1700000000000,
      'updated_at_ms': 1700000001000,
    },
    'primary_track_id': 'track-1',
    'triage_intent': 'pin_intensive',
  };

  test('parses the media-library wire shape', () {
    final entry = MediaLibraryEntry.fromJson(fixture);

    expect(entry.media.id, 'media-1');
    expect(entry.media.title, 'Library');
    expect(entry.media.kind, 'video');
    expect(entry.media.durationMs, 90000);
    expect(entry.primaryTrackId, 'track-1');
    expect(entry.triageIntent, 'pin_intensive');
  });

  test('tolerates absent optional media and learner triage details', () {
    final entry = MediaLibraryEntry.fromJson({
      ...fixture,
      'media': {...(fixture['media']! as Map), 'duration': null},
      'primary_track_id': null,
      'triage_intent': null,
    });

    expect(entry.media.durationMs, isNull);
    expect(entry.primaryTrackId, isNull);
    expect(entry.triageIntent, isNull);
  });

  test('round-trips through toJson', () {
    final entry = MediaLibraryEntry.fromJson(fixture);

    expect(MediaLibraryEntry.fromJson(entry.toJson()).toJson(), fixture);
  });
}
