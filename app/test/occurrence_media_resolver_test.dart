import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/models/types.dart';

MediaItem mediaAt(String path) => MediaItem(
  id: 'media-1',
  path: path,
  fingerprint: 'expected-fingerprint',
  title: 'Source',
  kind: 'video',
  durationMs: 1000,
  availability: 'available',
  createdAtMs: 1,
  updatedAtMs: 1,
);

Map<String, dynamic> occurrence({String? mediaId}) {
  final linked = mediaId == null
      ? const <String, dynamic>{}
      : <String, dynamic>{'media_id': mediaId};
  return {'media_fingerprint_snapshot': 'expected-fingerprint', ...linked};
}

void main() {
  test(
    'uses an existing linked media path without asking for a file',
    () async {
      var pickerCalled = false;
      final resolver = OccurrenceMediaResolver(
        readMedia: (_) async => mediaAt('/linked/source.mp4'),
        fingerprintFile: (_) async => throw StateError('not needed'),
        registerMedia: (_) async => throw StateError('not needed'),
        pickFile: (_) async {
          pickerCalled = true;
          return null;
        },
        fileExists: (path) async => path == '/linked/source.mp4',
      );

      final result = await resolver.resolve(
        occurrence(mediaId: 'linked-media'),
        currentMediaFingerprint: 'another-media',
        currentMediaPath: '/current.mp4',
      );

      expect(result, isA<ResolvedOccurrenceMedia>());
      final resolved = result as ResolvedOccurrenceMedia;
      expect(resolved.path, '/linked/source.mp4');
      expect(resolved.usesCurrentMedia, isFalse);
      expect(pickerCalled, isFalse);
    },
  );

  test('rejects a user-selected file with a different fingerprint', () async {
    var registered = false;
    final resolver = OccurrenceMediaResolver(
      readMedia: (_) async => throw StateError('no linked record'),
      fingerprintFile: (_) async => 'different-fingerprint',
      registerMedia: (_) async => registered = true,
      pickFile: (_) async => XFile('/chosen/wrong.mp4'),
      fileExists: (_) async => false,
    );

    final result = await resolver.resolve(
      occurrence(),
      currentMediaFingerprint: null,
      currentMediaPath: null,
      filterMediaExtensions: true,
    );

    expect(result, isA<UnresolvedOccurrenceMedia>());
    expect(
      (result as UnresolvedOccurrenceMedia).failure,
      OccurrenceMediaResolutionFailure.fingerprintMismatch,
    );
    expect(registered, isFalse);
  });

  test(
    'recovers from a missing linked file by locating and registering it',
    () async {
      var registeredPath = '';
      final resolver = OccurrenceMediaResolver(
        readMedia: (_) async => mediaAt('/missing/original.mp4'),
        fingerprintFile: (_) async => 'expected-fingerprint',
        registerMedia: (path) async => registeredPath = path,
        pickFile: (_) async => XFile('/relocated/source.mp4'),
        fileExists: (path) async => path == '/relocated/source.mp4',
      );

      final result = await resolver.resolve(
        occurrence(mediaId: 'linked-media'),
        currentMediaFingerprint: 'another-media',
        currentMediaPath: '/current.mp4',
        filterMediaExtensions: true,
      );

      expect(result, isA<ResolvedOccurrenceMedia>());
      expect((result as ResolvedOccurrenceMedia).path, '/relocated/source.mp4');
      expect(registeredPath, '/relocated/source.mp4');
    },
  );
}
