import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/models/types.dart';

/// Phase 3.13 GUI QA regression: the reading-posture replay chips ("听整段"
/// and per-sentence chips) and the listening-check play button build a slice
/// occurrence for the *currently loaded* media via
/// [currentMediaSliceOccurrence]. That occurrence must resolve to the current
/// media path without a file picker; the original bug was a hand-rolled map
/// missing `media_fingerprint_snapshot`, which the shared resolver rejects
/// before even trying the linked-media route.
void main() {
  OccurrenceMediaResolver resolver({
    required void Function() onPicker,
  }) => OccurrenceMediaResolver(
    readMedia: (_) async => MediaItem(
      id: 'media-1',
      path: '/library/cnn10.mp4',
      fingerprint: 'fp-current',
      title: 'CNN10',
      kind: 'video',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
    fingerprintFile: (_) async => 'fp-current',
    registerMedia: (_) async {},
    pickFile: (_) async {
      onPicker();
      return null;
    },
    fileExists: (path) async =>
        path == '/library/cnn10.mp4' || path == '/current/cnn10.mp4',
  );

  Map<String, dynamic> readingOccurrence({required String? fingerprint}) =>
      currentMediaSliceOccurrence(
        mediaId: 'media-1',
        trackId: 'track-1',
        sentenceId: 'cue-12',
        textSnapshot: 'And that is why the sky looks blue.',
        startMs: 15000,
        endMs: 22000,
        mediaFingerprint: fingerprint,
      );

  test('reading replay occurrence resolves to the current media', () async {
    var pickerCalled = false;

    final result = await resolver(onPicker: () => pickerCalled = true).resolve(
      readingOccurrence(fingerprint: 'fp-current'),
      currentMediaFingerprint: 'fp-current',
      currentMediaPath: '/current/cnn10.mp4',
      filterMediaExtensions: true,
    );

    expect(
      result,
      isA<ResolvedOccurrenceMedia>(),
      reason:
          'Reading replay over the loaded media must play without recovery: '
          '$result',
    );
    expect((result as ResolvedOccurrenceMedia).usesCurrentMedia, isTrue);
    expect(pickerCalled, isFalse);
    expect(result.path, '/current/cnn10.mp4');
  });

  test('slice range carries the timing snapshot through unchanged', () {
    final occurrence = readingOccurrence(fingerprint: 'fp-current');
    expect(occurrence['start_ms_snapshot'], 15000);
    expect(occurrence['end_ms_snapshot'], 22000);
    expect(occurrence['sentence_id'], 'cue-12');
  });

  test('missing player fingerprint degrades to an explicit failure', () async {
    var pickerCalled = false;

    final result = await resolver(onPicker: () => pickerCalled = true).resolve(
      readingOccurrence(fingerprint: null),
      currentMediaFingerprint: null,
      currentMediaPath: '/current/cnn10.mp4',
      filterMediaExtensions: true,
    );

    expect(result, isA<UnresolvedOccurrenceMedia>());
    expect(
      (result as UnresolvedOccurrenceMedia).failure,
      OccurrenceMediaResolutionFailure.invalidSnapshot,
    );
    expect(pickerCalled, isFalse);
  });
}
