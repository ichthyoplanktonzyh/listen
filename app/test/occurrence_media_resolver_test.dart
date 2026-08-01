import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/data/repositories/occurrence_media_repository.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/occurrence_media_file_service.dart';

class _Repository implements OccurrenceMediaRepository {
  _Repository({
    required this.onRead,
    required this.onFingerprint,
    required this.onRegister,
  });

  final Future<MediaItem> Function(String) onRead;
  final Future<String> Function(String) onFingerprint;
  final Future<void> Function(String) onRegister;

  @override
  Future<MediaItem> readMedia(String mediaId) => onRead(mediaId);
  @override
  Future<String> fingerprintFile(String path) => onFingerprint(path);
  @override
  Future<void> registerMedia(String path) => onRegister(path);
}

class _FileService implements OccurrenceMediaFileService {
  _FileService({required this.onPick, required this.onExists});

  final Future<String?> Function(bool) onPick;
  final Future<bool> Function(String) onExists;

  @override
  Future<bool> exists(String path) => onExists(path);
  @override
  Future<String?> pickSourceMedia({required bool filterMediaExtensions}) =>
      onPick(filterMediaExtensions);
}

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
        repository: _Repository(
          onRead: (_) async => mediaAt('/linked/source.mp4'),
          onFingerprint: (_) async => throw StateError('not needed'),
          onRegister: (_) async => throw StateError('not needed'),
        ),
        fileService: _FileService(
          onPick: (_) async {
            pickerCalled = true;
            return null;
          },
          onExists: (path) async => path == '/linked/source.mp4',
        ),
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
      repository: _Repository(
        onRead: (_) async => throw StateError('no linked record'),
        onFingerprint: (_) async => 'different-fingerprint',
        onRegister: (_) async => registered = true,
      ),
      fileService: _FileService(
        onPick: (_) async => '/chosen/wrong.mp4',
        onExists: (_) async => false,
      ),
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
        repository: _Repository(
          onRead: (_) async => mediaAt('/missing/original.mp4'),
          onFingerprint: (_) async => 'expected-fingerprint',
          onRegister: (path) async => registeredPath = path,
        ),
        fileService: _FileService(
          onPick: (_) async => '/relocated/source.mp4',
          onExists: (path) async => path == '/relocated/source.mp4',
        ),
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
