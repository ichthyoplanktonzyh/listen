import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/scanned_media.dart';

export '../models/scanned_media.dart';

/// What the medium-cost identification layer is allowed to learn about a file.
sealed class MediaProbeResult {
  const MediaProbeResult();
}

class MediaProbeSuccess extends MediaProbeResult {
  const MediaProbeSuccess({required this.hasAudioTrack, this.duration});

  final bool hasAudioTrack;

  /// `null` when the container reports no usable duration; the file may still
  /// be perfectly playable, so this is not a failure.
  final Duration? duration;
}

/// The file could not be parsed — corrupt, truncated, or unreadable.
class MediaProbeFailure extends MediaProbeResult {
  const MediaProbeFailure();
}

/// The medium-cost layer of identification, injected so the scanner can be
/// tested without ffprobe on the machine or a real media file on disk.
abstract interface class MediaProbe {
  Future<MediaProbeResult> probe(String path);
}

/// Scans a media-library folder for learnable files.
///
/// The service knows nothing about the backend, repositories, or the UI: it
/// turns a folder plus a set of already-known stamps into candidate media.
/// Fingerprinting is deliberately absent — that is the expensive layer and it
/// belongs to registration, not to a walk that runs on every app start.
class MediaLibraryScanner {
  const MediaLibraryScanner(this._probe);

  final MediaProbe _probe;

  /// Starts a scan and returns a live handle. Work begins immediately and
  /// events buffer until someone listens, so a slow subscriber cannot stall the
  /// walk and a caller that leaves the screen can simply cancel.
  MediaLibraryScan scan({
    required String directory,
    Iterable<KnownMediaStamp> known = const <KnownMediaStamp>[],
  }) {
    return MediaLibraryScan._(directory, _probe, known);
  }
}

/// A running scan: incremental events, a terminal report, and cancellation.
class MediaLibraryScan {
  MediaLibraryScan._(this._root, this._probe, Iterable<KnownMediaStamp> known)
    : _known = {for (final stamp in known) stamp.path: stamp} {
    unawaited(_run());
  }

  final String _root;
  final MediaProbe _probe;
  final Map<String, KnownMediaStamp> _known;
  final _events = StreamController<MediaScanEvent>();
  final _report = Completer<MediaScanReport>();
  final _discovered = <ScannedMedia>[];
  final _unchangedPaths = <String>[];
  final _skipped = <MediaScanSkipped>[];
  bool _cancelled = false;

  /// Results as they are found, closed when the scan reaches a terminal state.
  Stream<MediaScanEvent> get events => _events.stream;

  /// Terminal summary, including everything emitted before a cancellation.
  Future<MediaScanReport> get report => _report.future;

  /// Stops the walk at the next checkpoint. Already emitted results stand.
  void cancel() => _cancelled = true;

  Future<void> _run() async {
    final root = Directory(_root);
    if (!await _exists(root)) {
      await _finish(MediaScanStatus.rootUnavailable);
      return;
    }
    // An explicit queue instead of `Directory.list(recursive: true)`: a single
    // unreadable subfolder must skip that subfolder, not abort the scan.
    final pending = <String>[_root];
    while (pending.isNotEmpty) {
      if (_cancelled) {
        await _finish(MediaScanStatus.cancelled);
        return;
      }
      final current = pending.removeAt(0);
      final entries = await _list(current);
      if (entries == null) {
        _emit(
          MediaScanSkipped(
            path: current,
            reason: MediaScanSkipReason.unreadable,
          ),
        );
        continue;
      }
      pending.addAll(entries.directories);
      for (final link in entries.links) {
        _emit(
          MediaScanSkipped(
            path: link,
            reason: MediaScanSkipReason.symbolicLink,
          ),
        );
      }
      for (final candidate in entries.mediaFiles) {
        if (_cancelled) {
          await _finish(MediaScanStatus.cancelled);
          return;
        }
        await _inspect(candidate, entries.subtitlesByStem);
      }
    }
    await _finish(
      _cancelled ? MediaScanStatus.cancelled : MediaScanStatus.completed,
    );
  }

  Future<void> _inspect(
    _MediaCandidate candidate,
    Map<String, List<SidecarSubtitle>> subtitlesByStem,
  ) async {
    final path = candidate.file.path;
    final FileStat stat;
    try {
      stat = await candidate.file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        _emit(
          MediaScanSkipped(path: path, reason: MediaScanSkipReason.unreadable),
        );
        return;
      }
    } on FileSystemException {
      _emit(
        MediaScanSkipped(path: path, reason: MediaScanSkipReason.unreadable),
      );
      return;
    }
    final sidecars =
        subtitlesByStem[_stem(_fileName(path)).toLowerCase()] ??
        const <SidecarSubtitle>[];

    final stamp = _known[path];
    if (stamp != null &&
        stamp.matches(sizeBytes: stat.size, modifiedAt: stat.modified)) {
      _unchangedPaths.add(path);
      _emit(MediaScanUnchanged(path: path, sidecarSubtitles: sidecars));
      return;
    }

    final MediaProbeResult result;
    try {
      result = await _probe.probe(path);
    } catch (_) {
      // A probe implementation shells out; any failure it raises means the same
      // thing here as a reported failure — this file cannot be identified.
      _emit(
        MediaScanSkipped(path: path, reason: MediaScanSkipReason.probeFailed),
      );
      return;
    }
    if (_cancelled) return;
    switch (result) {
      case MediaProbeFailure():
        _emit(
          MediaScanSkipped(path: path, reason: MediaScanSkipReason.probeFailed),
        );
      case MediaProbeSuccess(hasAudioTrack: false):
        _emit(
          MediaScanSkipped(
            path: path,
            reason: MediaScanSkipReason.noAudioTrack,
          ),
        );
      case MediaProbeSuccess(:final duration):
        final media = ScannedMedia(
          path: path,
          fileName: _fileName(path),
          kind: candidate.kind,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
          duration: duration,
          sidecarSubtitles: List.unmodifiable(sidecars),
        );
        _discovered.add(media);
        _emit(MediaScanDiscovered(media));
    }
  }

  Future<_DirectoryEntries?> _list(String path) async {
    final directories = <String>[];
    final links = <String>[];
    final mediaFiles = <_MediaCandidate>[];
    final subtitlesByStem = <String, List<SidecarSubtitle>>{};
    try {
      await for (final entity in Directory(
        path,
      ).list(followLinks: false, recursive: false)) {
        if (entity is Link) {
          links.add(entity.path);
        } else if (entity is Directory) {
          directories.add(entity.path);
        } else if (entity is File) {
          final extension = _extension(entity.path);
          final kind = _kindFor(extension);
          if (kind != null) {
            mediaFiles.add(_MediaCandidate(file: entity, kind: kind));
            continue;
          }
          final format = _subtitleFormats[extension];
          if (format != null) {
            subtitlesByStem
                .putIfAbsent(
                  _stem(_fileName(entity.path)).toLowerCase(),
                  () => <SidecarSubtitle>[],
                )
                .add(SidecarSubtitle(path: entity.path, format: format));
          }
        }
      }
    } on FileSystemException {
      return null;
    }
    // Stable order keeps incremental output reproducible across runs.
    directories.sort();
    links.sort();
    mediaFiles.sort((a, b) => a.file.path.compareTo(b.file.path));
    for (final entry in subtitlesByStem.values) {
      entry.sort((a, b) => a.path.compareTo(b.path));
    }
    return _DirectoryEntries(
      directories: directories,
      links: links,
      mediaFiles: mediaFiles,
      subtitlesByStem: subtitlesByStem,
    );
  }

  void _emit(MediaScanEvent event) {
    if (_events.isClosed) return;
    if (event is MediaScanSkipped) _skipped.add(event);
    _events.add(event);
  }

  Future<void> _finish(MediaScanStatus status) async {
    if (_report.isCompleted) return;
    _report.complete(
      MediaScanReport(
        status: status,
        discovered: _discovered,
        unchangedPaths: _unchangedPaths,
        skipped: _skipped,
      ),
    );
    await _events.close();
  }

  Future<bool> _exists(Directory directory) async {
    try {
      return await directory.exists();
    } on FileSystemException {
      return false;
    }
  }
}

class _DirectoryEntries {
  const _DirectoryEntries({
    required this.directories,
    required this.links,
    required this.mediaFiles,
    required this.subtitlesByStem,
  });

  final List<String> directories;
  final List<String> links;
  final List<_MediaCandidate> mediaFiles;
  final Map<String, List<SidecarSubtitle>> subtitlesByStem;
}

class _MediaCandidate {
  const _MediaCandidate({required this.file, required this.kind});

  final File file;
  final ScannedMediaKind kind;
}

/// ffprobe-backed probe: one invocation reports both the stream types and the
/// container duration, so the medium-cost layer costs exactly one process.
class FfprobeMediaProbe implements MediaProbe {
  const FfprobeMediaProbe({this.ffprobePath = ''});

  /// The path configured in Settings, when there is one.
  final String ffprobePath;

  @override
  Future<MediaProbeResult> probe(String path) async {
    final executable = await _resolve();
    if (executable == null) return const MediaProbeFailure();
    final process = await Process.start(executable, [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_type:format=duration',
      '-of',
      'json',
      path,
    ]);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrDrain = process.stderr.drain<void>();
    final timer = Timer(
      const Duration(seconds: 20),
      () => process.kill(ProcessSignal.sigkill),
    );
    final exitCode = await process.exitCode;
    timer.cancel();
    final output = await stdoutFuture;
    await stderrDrain;
    if (exitCode != 0) return const MediaProbeFailure();
    try {
      final decoded = jsonDecode(output) as Map<String, dynamic>;
      final streams = decoded['streams'] as List<dynamic>? ?? const <dynamic>[];
      final hasAudioTrack = streams.any(
        (stream) =>
            ((stream as Map<String, dynamic>)['codec_type'] as String?) ==
            'audio',
      );
      final format = decoded['format'] as Map<String, dynamic>?;
      // ffprobe emits the duration as a string ("400.660317"); tolerate a
      // numeric value as well.
      final rawDuration = format?['duration'];
      final seconds = switch (rawDuration) {
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      };
      return MediaProbeSuccess(
        hasAudioTrack: hasAudioTrack,
        duration: seconds == null
            ? null
            : Duration(milliseconds: (seconds * 1000).round()),
      );
    } on FormatException {
      return const MediaProbeFailure();
    } on TypeError {
      return const MediaProbeFailure();
    }
  }

  /// Mirrors the lookup order the rest of the app uses for bundled tools, so a
  /// path configured in Settings behaves the same here.
  Future<String?> _resolve() async {
    if (ffprobePath.isNotEmpty && await File(ffprobePath).exists()) {
      return ffprobePath;
    }
    for (final candidate in [
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/runtime/ffprobe',
      '/opt/homebrew/bin/ffprobe',
      '/usr/local/bin/ffprobe',
      '/usr/bin/ffprobe',
    ]) {
      if (await File(candidate).exists()) return candidate;
    }
    final result = await Process.run('/usr/bin/which', ['ffprobe']);
    final resolved = (result.stdout as String).trim();
    if (result.exitCode == 0 && resolved.isNotEmpty) return resolved;
    return null;
  }
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;

String _stem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

String _extension(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

ScannedMediaKind? _kindFor(String extension) {
  if (_audioExtensions.contains(extension)) return ScannedMediaKind.audio;
  if (_videoExtensions.contains(extension)) return ScannedMediaKind.video;
  return null;
}

/// Container whitelist. Extensions are a claim, not proof — the probe still has
/// to find an audio track before anything here becomes a result.
const _audioExtensions = {
  'aac',
  'aif',
  'aiff',
  'flac',
  'm4a',
  'm4b',
  'mp3',
  'oga',
  'ogg',
  'opus',
  'wav',
  'wma',
};

const _videoExtensions = {
  '3gp',
  'avi',
  'flv',
  'm2ts',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'mpeg',
  'mpg',
  'ts',
  'webm',
  'wmv',
};

const _subtitleFormats = {
  'srt': SidecarSubtitleFormat.srt,
  'vtt': SidecarSubtitleFormat.vtt,
  'ass': SidecarSubtitleFormat.ass,
};
