import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';

/// The managed store is the filesystem half of retention. These tests pin the
/// honesty rules: the original is never touched, the copy is verified
/// byte-for-byte, identical content deduplicates to one file, staged copies
/// never linger, and an unavailable store is a typed state, not an exception
/// the UI could print.
void main() {
  late Directory store;
  late Directory sources;
  late LocalManagedAssetStoreService service;

  setUp(() {
    store = Directory.systemTemp.createTempSync('managed-assets-store');
    sources = Directory.systemTemp.createTempSync('managed-assets-sources');
    service = LocalManagedAssetStoreService(resolveRoot: () => store.path);
  });

  tearDown(() {
    store.deleteSync(recursive: true);
    sources.deleteSync(recursive: true);
  });

  String writeSource(String name, {List<int> bytes = const [1, 2, 3, 4]}) {
    final file = File('${sources.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  List<String> stagingFiles() {
    final staging = Directory('${store.path}${Platform.pathSeparator}.staging');
    if (!staging.existsSync()) return const [];
    return staging.listSync().map((e) => e.path).toList();
  }

  test(
    'copies the source into the store, preserving bytes and the original',
    () async {
      final sourcePath = writeSource('talk.mp3', bytes: [9, 8, 7, 6, 5]);

      final copy = await service.copyIntoStore(sourcePath: sourcePath);
      final resolvedStore = await store.resolveSymbolicLinks();

      expect(copy.createdNew, isTrue);
      expect(copy.path, startsWith('$resolvedStore${Platform.pathSeparator}'));
      expect(copy.mediaKind, 'audio');
      expect(File(copy.path).readAsBytesSync(), [9, 8, 7, 6, 5]);
      // The original is untouched.
      expect(File(sourcePath).readAsBytesSync(), [9, 8, 7, 6, 5]);
      // The stored name is only the content digest: source extensions never
      // decide identity or introduce unsafe filename characters.
      final digest = sha256.convert([9, 8, 7, 6, 5]).toString();
      expect(copy.path, '$resolvedStore${Platform.pathSeparator}$digest');
    },
  );

  test('deduplicates deterministically by digest', () async {
    final first = writeSource('one.mp4');
    final second = writeSource('two.mp4');

    final firstCopy = await service.copyIntoStore(sourcePath: first);
    final secondCopy = await service.copyIntoStore(sourcePath: second);

    // Same bytes, same store path — one file, two names resolved to it.
    expect(secondCopy.path, firstCopy.path);
    expect(firstCopy.createdNew, isTrue);
    expect(secondCopy.createdNew, isFalse);
    final files = store
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.contains('.staging'))
        .toList();
    expect(files, hasLength(1));
  });

  test(
    'deduplicates identical bytes across extensions and unusual filenames',
    () async {
      final first = writeSource('ordinary.mp3', bytes: [8, 6, 7, 5, 3, 0, 9]);
      final second = writeSource(
        'unusual name [draft] ★.MP4',
        bytes: [8, 6, 7, 5, 3, 0, 9],
      );

      final firstCopy = await service.copyIntoStore(sourcePath: first);
      final secondCopy = await service.copyIntoStore(sourcePath: second);

      expect(secondCopy.path, firstCopy.path);
      expect(
        File(firstCopy.path).uri.pathSegments.last,
        sha256.convert([8, 6, 7, 5, 3, 0, 9]).toString(),
      );
      // The managed name is digest-only, but the caller can retain the source
      // classification separately for the Core registration.
      expect(firstCopy.mediaKind, 'audio');
      expect(secondCopy.mediaKind, 'video');
    },
  );

  test(
    'a different digest is a different file, even for the same name',
    () async {
      final path = writeSource('same.mp3', bytes: [1]);
      final other = writeSource('other.mp3', bytes: [2]);

      final firstCopy = await service.copyIntoStore(sourcePath: path);
      final secondCopy = await service.copyIntoStore(sourcePath: other);

      expect(firstCopy.path, isNot(secondCopy.path));
      expect(firstCopy.createdNew, isTrue);
      expect(secondCopy.createdNew, isTrue);
    },
  );

  test('staged copies are cleaned after a successful keep', () async {
    final sourcePath = writeSource('clean.mp4', bytes: [1, 2, 3]);

    await service.copyIntoStore(sourcePath: sourcePath);

    expect(stagingFiles(), isEmpty);
  });

  test(
    'a directory at a managed target fails closed and cleans staging',
    () async {
      final sourcePath = writeSource('landed.mp4', bytes: [4, 4, 4]);
      // A directory/symlink/non-regular target is never a deduplication target.
      // The store must not follow or overwrite it, and must not leave staging
      // debris behind.
      final digest = sha256.convert([4, 4, 4]).toString();
      Directory('${store.path}${Platform.pathSeparator}$digest').createSync();

      await expectLater(
        service.copyIntoStore(sourcePath: sourcePath),
        throwsA(isA<ManagedStoreCopyFailed>()),
      );
      expect(stagingFiles(), isEmpty);
    },
  );

  test(
    'concurrent identical keeps publish one copy with one rollback owner',
    () async {
      final sourcePath = writeSource('same.mp3', bytes: [5, 4, 3, 2, 1]);

      final copies = await Future.wait([
        service.copyIntoStore(sourcePath: sourcePath),
        service.copyIntoStore(sourcePath: sourcePath),
      ]);

      expect(copies.map((copy) => copy.path).toSet(), hasLength(1));
      expect(copies.where((copy) => copy.createdNew), hasLength(1));
      expect(copies.where((copy) => !copy.createdNew), hasLength(1));
    },
  );

  test('an unavailable store root is a typed state', () async {
    final unavailable = LocalManagedAssetStoreService(resolveRoot: () => null);
    final sourcePath = writeSource('gone.mp4');

    await expectLater(
      unavailable.copyIntoStore(sourcePath: sourcePath),
      throwsA(isA<ManagedStoreUnavailable>()),
    );
  });

  test('a missing custom location resolves to an unavailable store', () async {
    final unavailable = LocalManagedAssetStoreService(
      resolveRoot: () => '/volumes/not-connected/media',
    );
    final sourcePath = writeSource('gone.mp4');

    await expectLater(
      unavailable.copyIntoStore(sourcePath: sourcePath),
      throwsA(isA<ManagedStoreUnavailable>()),
    );
  });

  test('deleteStoreCopy removes a managed copy', () async {
    final sourcePath = writeSource('delete-me.mp4');
    final copy = await service.copyIntoStore(sourcePath: sourcePath);

    await service.deleteStoreCopy(copy.path);

    expect(File(copy.path).existsSync(), isFalse);
  });

  test('deleteStoreCopy refuses paths outside the store', () async {
    final outside = File('${sources.path}${Platform.pathSeparator}outside.mp4')
      ..writeAsBytesSync([1]);

    await service.deleteStoreCopy(outside.path);

    expect(outside.existsSync(), isTrue);
  });

  test(
    'deleteStoreCopy refuses a normalized traversal outside the store',
    () async {
      final outside = File(
        '${store.path}${Platform.pathSeparator}..${Platform.pathSeparator}'
        '${sources.path.split(Platform.pathSeparator).last}'
        '${Platform.pathSeparator}outside.mp4',
      )..writeAsBytesSync([1]);

      await service.deleteStoreCopy(outside.path);

      expect(outside.existsSync(), isTrue);
    },
  );

  test(
    'deleteStoreCopy refuses a symlink even when it is inside the store',
    () async {
      if (Platform.isWindows) return;
      final outside = File(
        '${sources.path}${Platform.pathSeparator}outside.mp4',
      )..writeAsBytesSync([1]);
      final link = Link(
        '${store.path}${Platform.pathSeparator}'
        '${sha256.convert([1])}',
      );
      await link.create(outside.path);

      await service.deleteStoreCopy(link.path);

      expect(await link.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    },
  );
}
