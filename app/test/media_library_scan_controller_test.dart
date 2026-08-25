import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/media_library_scan_controller.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/saved_vocabulary_count.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/media_library_scanner.dart';
import 'package:llplayer_next/settings.dart';

/// Core, reduced to what a scan asks of it: does it answer, does it accept a
/// path, and how many round trips did that take.
class _FakeLibrary implements MediaLibraryRepository {
  _FakeLibrary({this.available = true});

  bool available;
  Duration registerLatency = Duration.zero;
  final refused = <String>{};
  final registeredPaths = <String>[];
  final registeredDurations = <String, int?>{};
  final registeredRetains = <String, bool>{};
  int registerCalls = 0;
  int listCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  ApiFailure failureDetail(Object error) =>
      const ApiFailure(raw: 'fake', message: 'core refused the media');

  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) async {
    registerCalls++;
    if (registerLatency > Duration.zero) {
      await Future<void>.delayed(registerLatency);
    }
    if (refused.contains(path)) throw StateError('refused');
    registeredPaths.add(path);
    registeredDurations[path] = durationMs;
    registeredRetains[path] = retain;
    return MediaItem(
      id: path,
      path: path,
      fingerprint: 'fp',
      title: path,
      kind: 'video',
      durationMs: durationMs,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
  }

  @override
  Future<MediaItem> readMedia(String mediaId) async =>
      MediaItem.fromJson({});
  @override
  Future<MediaItem?> findRegisteredMedia(String mediaId) async => null;
  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() async {
    listCalls++;
    return const <MediaLibraryEntry>[];
  }

  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) => throw UnimplementedError();

  @override
  Future<MediaLibraryEntry> setTriageIntent(String mediaId, String? intent) =>
      throw UnimplementedError();
}

class _CountingProbe implements MediaProbe {
  int calls = 0;

  @override
  Future<MediaProbeResult> probe(String path) async {
    calls++;
    return const MediaProbeSuccess(
      hasAudioTrack: true,
      duration: Duration(minutes: 4),
    );
  }
}

Future<KnownMediaStamp?> _readStamp(String path) async {
  final stat = await File(path).stat();
  if (stat.type == FileSystemEntityType.notFound) return null;
  return KnownMediaStamp(
    path: path,
    sizeBytes: stat.size,
    modifiedAt: stat.modified,
  );
}

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('media-library'));
  tearDown(() => folder.deleteSync(recursive: true));

  String write(String name, {String body = 'media'}) {
    final file = File('${folder.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(body);
    return file.path;
  }

  MediaLibraryScanController controller({
    required _FakeLibrary library,
    MediaProbe? probe,
    ManagedStoreLocation? folderState,
    List<String>? Function()? registeredPaths,
    int refreshEvery = 25,
    void Function()? onRefreshLibrary,
  }) => MediaLibraryScanController(
    scanner: MediaLibraryScanner(probe ?? _CountingProbe()),
    repository: library,
    resolveFolder: () async =>
        folderState ?? (path: folder.path, state: StorageLocationState.ready),
    registeredPaths: registeredPaths ?? () => library.registeredPaths,
    refreshLibrary: () async {
      onRefreshLibrary?.call();
      await library.listMediaLibrary();
    },
    readStamp: _readStamp,
    refreshEvery: refreshEvery,
  );

  test('the default store and a missing custom folder are two different '
      'answers', () async {
    final library = _FakeLibrary();
    final defaultProbe = _CountingProbe();
    final missingProbe = _CountingProbe();

    // No custom location: the app-managed default store is a real, scannable
    // location, never a "no store" story.
    write('talk.mp4');
    final appManaged = controller(
      library: library,
      probe: defaultProbe,
      folderState: (path: folder.path, state: StorageLocationState.appManaged),
    );
    await appManaged.enterLibrary();
    expect(appManaged.state.status, MediaLibraryScanStatus.completed);
    expect(library.registeredPaths, hasLength(1));

    final missing = controller(
      library: library,
      probe: missingProbe,
      folderState: (
        path: '/volumes/gone/media',
        state: StorageLocationState.missing,
      ),
    );
    await missing.enterLibrary();
    expect(missing.state.status, MediaLibraryScanStatus.folderMissing);
    // The remembered path is what makes "remount the drive" actionable.
    expect(missing.state.folderPath, '/volumes/gone/media');
    expect(missingProbe.calls, 0);
  });

  test('scan registration is discovery and never silently retains', () async {
    final path = write('discovery.mp4');
    final library = _FakeLibrary();
    final scan = controller(
      library: library,
      registeredPaths: () => const <String>[],
    );

    await scan.enterLibrary();

    expect(scan.state.status, MediaLibraryScanStatus.completed);
    expect(library.registeredRetains[path], isFalse);
  });

  test('an unreachable core leaves the library unknown, never empty', () async {
    write('talk.mp4');
    final library = _FakeLibrary(available: false);
    final probe = _CountingProbe();
    final scan = controller(library: library, probe: probe);

    await scan.enterLibrary();

    expect(scan.state.status, MediaLibraryScanStatus.coreUnavailable);
    expect(scan.state.libraryContentsKnown, isFalse);
    expect(library.registerCalls, 0);
    expect(probe.calls, 0);
  });

  test(
    'a completed walk registers what is new and reports the library as known',
    () async {
      final first = write('one.mp4');
      final second = write('two.mp3');
      final library = _FakeLibrary();
      var refreshes = 0;
      final scan = controller(
        library: library,
        registeredPaths: () => const <String>[],
        onRefreshLibrary: () => refreshes++,
      );

      await scan.enterLibrary();

      expect(scan.state.status, MediaLibraryScanStatus.completed);
      expect(scan.state.libraryContentsKnown, isTrue);
      expect(scan.state.registered, 2);
      expect(library.registeredPaths, containsAll(<String>[first, second]));
      // The probed duration travels with the registration; the library row must
      // not have to invent one.
      expect(library.registeredDurations[first], 240000);
      expect(refreshes, 1);
    },
  );

  test('files Core already holds are never probed again', () async {
    final path = write('known.mp4');
    final library = _FakeLibrary();
    final probe = _CountingProbe();
    final scan = controller(
      library: library,
      probe: probe,
      // A fresh session: the stamps can only come from Core's paths plus one
      // stat each, which is what keeps the probe out of an unchanged file.
      registeredPaths: () => <String>[path],
    );

    await scan.enterLibrary();

    expect(probe.calls, 0);
    expect(library.registerCalls, 0);
    expect(scan.state.unchanged, 1);
    expect(scan.state.discovered, 0);
    expect(scan.state.status, MediaLibraryScanStatus.completed);

    // A file that actually changed is not unchanged: the stamp stops matching
    // and the expensive layer runs again.
    File(path).writeAsStringSync('a much longer body than before');
    await scan.refresh();
    expect(probe.calls, 1);
    expect(scan.state.discovered, 1);
  });

  test('sidecar subtitles are reported as a fact about the folder', () async {
    final path = write('talk.mp4');
    write('talk.srt', body: 'subtitle');
    final library = _FakeLibrary();
    final scan = controller(library: library);

    await scan.enterLibrary();

    expect(scan.state.sidecarSubtitlePaths, contains(path));
  });

  test('one refused file neither stops the scan nor disappears', () async {
    final good = write('good.mp4');
    final bad = write('bad.mp4');
    final library = _FakeLibrary()..refused.add(bad);
    final scan = controller(library: library);

    await scan.enterLibrary();

    expect(scan.state.status, MediaLibraryScanStatus.completed);
    expect(scan.state.discovered, 2);
    expect(scan.state.registered, 1);
    expect(library.registeredPaths, <String>[good]);
    expect(scan.state.registrationFailures.single.fileName, 'bad.mp4');
    expect(
      scan.state.registrationFailures.single.failure.message,
      'core refused the media',
    );

    // Retry takes only the refused file, not another walk of the folder.
    library.refused.clear();
    await scan.retryFailedRegistrations();
    expect(scan.state.registrationFailures, isEmpty);
    expect(scan.state.registered, 2);
    expect(library.registeredPaths, containsAll(<String>[good, bad]));
  });

  test(
    'leaving the surface stops the walk and keeps the partial harvest',
    () async {
      for (var index = 0; index < 40; index++) {
        write('media-$index.mp4');
      }
      final library = _FakeLibrary()
        ..registerLatency = const Duration(milliseconds: 2);
      final scan = controller(
        library: library,
        registeredPaths: () => const <String>[],
      );

      final running = scan.enterLibrary();
      await Future<void>.delayed(const Duration(milliseconds: 12));
      scan.leaveLibrary();
      final registeredAtCancel = library.registerCalls;
      await running;

      expect(scan.state.status, MediaLibraryScanStatus.cancelled);
      expect(registeredAtCancel, lessThan(40));
      // Cancellation is prompt: no further round trips after the user left.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(library.registerCalls, registeredAtCancel);
      expect(scan.state.registered, greaterThan(0));
    },
  );

  test('the first scan of a large folder costs one round trip per file', () async {
    const fileCount = 300;
    for (var index = 0; index < fileCount; index++) {
      write('media-$index.mp4');
    }
    final library = _FakeLibrary();
    final scan = controller(
      library: library,
      registeredPaths: () => const <String>[],
    );

    // Proves the walk yields between files: a periodic timer keeps firing, so
    // the UI isolate is never held for the length of the scan.
    var ticks = 0;
    var notifies = 0;
    scan.addListener(() => notifies++);
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final started = DateTime.now();
    await scan.enterLibrary();
    final elapsed = DateTime.now().difference(started);
    timer.cancel();

    expect(scan.state.registered, fileCount);
    // One `registerMedia` per file — the number a batch endpoint would replace.
    expect(library.registerCalls, fileCount);
    // Plus one library reload per `refreshEvery` registrations, so the surface
    // fills as the walk proceeds instead of at the very end.
    expect(library.listCalls, fileCount ~/ 25);
    expect(ticks, greaterThan(0));
    // One state notification per file, not one per scan event.
    expect(notifies, lessThanOrEqualTo(fileCount + 10));
    // Client-side overhead only (the fake answers immediately): the real cost
    // is fileCount × the core's own round trip.
    expect(elapsed, lessThan(const Duration(seconds: 20)));

    // The second visit costs nothing but stats: every file is unchanged.
    await scan.refresh();
    expect(library.registerCalls, fileCount);
    expect(scan.state.unchanged, fileCount);
  });
}
