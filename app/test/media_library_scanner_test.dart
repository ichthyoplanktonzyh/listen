import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/media_library_scanner.dart';

void main() {
  late Directory root;

  setUp(() {
    // Resolved because macOS hands out `/var/...` temp paths that the scanner
    // reports as `/private/var/...` once the OS walks them.
    root = Directory(
      Directory.systemTemp
          .createTempSync('media-library')
          .resolveSymbolicLinksSync(),
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File writeFile(String relativePath, {String contents = 'x'}) {
    final file = File('${root.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  test('keeps whitelisted containers and ignores everything else', () async {
    writeFile('talk.mp4');
    writeFile('lecture.mp3');
    writeFile('notes.txt');
    writeFile('cover.jpg');
    writeFile('archive.zip');
    final probe = _FakeProbe.audio();

    final report = await MediaLibraryScanner(
      probe,
    ).scan(directory: root.path).report;

    expect(report.status, MediaScanStatus.completed);
    expect(
      report.discovered.map((media) => media.fileName),
      unorderedEquals(<String>['lecture.mp3', 'talk.mp4']),
    );
    expect(
      report.discovered
          .firstWhere((media) => media.fileName == 'lecture.mp3')
          .kind,
      ScannedMediaKind.audio,
    );
    // Non-candidates are never probed, not even to be rejected.
    expect(probe.probedPaths.length, 2);
  });

  test('excludes files without an audio track', () async {
    writeFile('silent.mp4');
    final probe = _FakeProbe(
      (_) => const MediaProbeSuccess(hasAudioTrack: false),
    );

    final report = await MediaLibraryScanner(
      probe,
    ).scan(directory: root.path).report;

    expect(report.discovered, isEmpty);
    expect(report.skipped.single.reason, MediaScanSkipReason.noAudioTrack);
  });

  test(
    'skips known files whose stamp still matches, without probing',
    () async {
      final unchanged = writeFile('known.mp4');
      final changed = writeFile('edited.mp4');
      final probe = _FakeProbe.audio();

      final report = await MediaLibraryScanner(probe)
          .scan(
            directory: root.path,
            known: [
              KnownMediaStamp(
                path: unchanged.path,
                sizeBytes: unchanged.lengthSync(),
                modifiedAt: unchanged.lastModifiedSync(),
              ),
              KnownMediaStamp(
                path: changed.path,
                sizeBytes: changed.lengthSync() + 1,
                modifiedAt: changed.lastModifiedSync(),
              ),
            ],
          )
          .report;

      expect(report.unchangedPaths, [unchanged.path]);
      expect(report.discovered.single.path, changed.path);
      expect(probe.probedPaths, [changed.path]);
    },
  );

  test('reports sidecar subtitles as a first-class field', () async {
    writeFile('talk.mp4');
    writeFile('talk.srt');
    writeFile('talk.vtt');
    writeFile('other.ass');
    writeFile('bare.mp4');

    final report = await MediaLibraryScanner(
      _FakeProbe.audio(),
    ).scan(directory: root.path).report;

    final talk = report.discovered.firstWhere(
      (media) => media.fileName == 'talk.mp4',
    );
    expect(talk.hasSidecarSubtitles, isTrue);
    expect(
      talk.sidecarSubtitles.map((subtitle) => subtitle.format),
      containsAll(<SidecarSubtitleFormat>[
        SidecarSubtitleFormat.srt,
        SidecarSubtitleFormat.vtt,
      ]),
    );
    expect(
      report.discovered
          .firstWhere((media) => media.fileName == 'bare.mp4')
          .hasSidecarSubtitles,
      isFalse,
    );
  });

  test('pairs late-arriving subtitles with an unchanged media file', () async {
    final media = writeFile('talk.mp4');
    writeFile('talk.srt');

    final scan = MediaLibraryScanner(_FakeProbe.audio()).scan(
      directory: root.path,
      known: [
        KnownMediaStamp(
          path: media.path,
          sizeBytes: media.lengthSync(),
          modifiedAt: media.lastModifiedSync(),
        ),
      ],
    );
    final events = await scan.events.toList();

    final unchanged = events.whereType<MediaScanUnchanged>().single;
    expect(unchanged.path, media.path);
    expect(unchanged.sidecarSubtitles.single.format, SidecarSubtitleFormat.srt);
  });

  test('degrades on corrupt files instead of aborting the scan', () async {
    writeFile('corrupt.mp4');
    writeFile('good.mp4');
    final probe = _FakeProbe(
      (path) => path.endsWith('corrupt.mp4')
          ? const MediaProbeFailure()
          : const MediaProbeSuccess(hasAudioTrack: true),
    );

    final report = await MediaLibraryScanner(
      probe,
    ).scan(directory: root.path).report;

    expect(report.status, MediaScanStatus.completed);
    expect(report.discovered.single.fileName, 'good.mp4');
    expect(report.skipped.single.reason, MediaScanSkipReason.probeFailed);
  });

  test('treats a throwing probe as a skipped file, not a crash', () async {
    writeFile('broken.mp4');
    writeFile('good.mp4');
    final probe = _FakeProbe((path) {
      if (path.endsWith('broken.mp4')) throw const FileSystemException('nope');
      return const MediaProbeSuccess(hasAudioTrack: true);
    });

    final report = await MediaLibraryScanner(
      probe,
    ).scan(directory: root.path).report;

    expect(report.discovered.single.fileName, 'good.mp4');
    expect(report.skipped.single.reason, MediaScanSkipReason.probeFailed);
  });

  test('records an unreadable subfolder and keeps walking', () async {
    writeFile('reachable/good.mp4');
    final locked = Directory('${root.path}/locked')..createSync();
    File('${locked.path}/hidden.mp4').writeAsStringSync('x');
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['700', locked.path]));

    final report = await MediaLibraryScanner(
      _FakeProbe.audio(),
    ).scan(directory: root.path).report;

    expect(report.status, MediaScanStatus.completed);
    expect(report.discovered.single.fileName, 'good.mp4');
    expect(report.skipped.map((skip) => skip.path), contains(locked.path));
    expect(report.skipped.single.reason, MediaScanSkipReason.unreadable);
  }, skip: Platform.isWindows);

  test('skips symbolic links rather than following them', () async {
    writeFile('real/talk.mp4');
    Link('${root.path}/loop').createSync(root.path);
    Link('${root.path}/dangling.mp4').createSync('${root.path}/missing.mp4');

    final report = await MediaLibraryScanner(
      _FakeProbe.audio(),
    ).scan(directory: root.path).report;

    expect(report.status, MediaScanStatus.completed);
    expect(report.discovered.single.fileName, 'talk.mp4');
    expect(
      report.skipped.map((skip) => skip.reason),
      everyElement(MediaScanSkipReason.symbolicLink),
    );
    expect(report.skipped, hasLength(2));
  }, skip: Platform.isWindows);

  test('cancellation keeps results already produced and stops probing', () async {
    for (var index = 0; index < 12; index++) {
      writeFile('clip-$index.mp4');
    }
    final probe = _FakeProbe.audio();
    final scan = MediaLibraryScanner(probe).scan(directory: root.path);
    final events = <MediaScanEvent>[];
    var closed = false;
    scan.events.listen((event) {
      events.add(event);
      if (events.length == 3) scan.cancel();
    }, onDone: () => closed = true);

    final report = await scan.report;
    await Future<void>.delayed(Duration.zero);

    expect(report.status, MediaScanStatus.cancelled);
    expect(report.discovered, isNotEmpty);
    expect(report.discovered.length, lessThan(12));
    // At most the in-flight probe runs past the cancellation point; nothing
    // after it is started.
    expect(probe.probedPaths.length, lessThanOrEqualTo(events.length + 1));
    // The stream is closed, so nothing is left dangling behind a cancelled scan.
    expect(closed, isTrue);
  });

  test('reports a missing root as unavailable rather than empty', () async {
    final report = await MediaLibraryScanner(
      _FakeProbe.audio(),
    ).scan(directory: '${root.path}/does-not-exist').report;

    expect(report.status, MediaScanStatus.rootUnavailable);
    expect(report.discovered, isEmpty);
  });

  test(
    'emits duration when the probe reports one and null when it does not',
    () async {
      writeFile('timed.mp4');
      writeFile('untimed.mp4');
      final probe = _FakeProbe(
        (path) => path.endsWith('timed.mp4') && !path.endsWith('untimed.mp4')
            ? const MediaProbeSuccess(
                hasAudioTrack: true,
                duration: Duration(minutes: 3),
              )
            : const MediaProbeSuccess(hasAudioTrack: true),
      );

      final report = await MediaLibraryScanner(
        probe,
      ).scan(directory: root.path).report;

      expect(
        report.discovered
            .firstWhere((media) => media.fileName == 'timed.mp4')
            .duration,
        const Duration(minutes: 3),
      );
      expect(
        report.discovered
            .firstWhere((media) => media.fileName == 'untimed.mp4')
            .duration,
        isNull,
      );
    },
  );

  test('finds media in nested folders', () async {
    writeFile('a/b/c/deep.mp4');

    final report = await MediaLibraryScanner(
      _FakeProbe.audio(),
    ).scan(directory: root.path).report;

    expect(report.discovered.single.fileName, 'deep.mp4');
  });
}

class _FakeProbe implements MediaProbe {
  _FakeProbe(this._result);

  factory _FakeProbe.audio() =>
      _FakeProbe((_) => const MediaProbeSuccess(hasAudioTrack: true));

  final MediaProbeResult Function(String path) _result;
  final probedPaths = <String>[];

  @override
  Future<MediaProbeResult> probe(String path) async {
    probedPaths.add(path);
    // A real probe shells out; yielding keeps the scan interruptible mid-walk.
    await Future<void>.delayed(Duration.zero);
    return _result(path);
  }
}
