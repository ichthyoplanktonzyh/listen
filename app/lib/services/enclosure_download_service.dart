import 'dart:async';
import 'dart:io';

import '../models/media_download.dart';

/// Fetches a podcast enclosure over plain HTTP.
///
/// This is the whole podcast acquisition path. An `<enclosure>` is a URL the
/// publisher put in the feed so that clients would fetch it, so there is no
/// extractor, no external binary, and nothing to keep working against a site
/// that would rather we did not — the reasons the YouTube path needs yt-dlp do
/// not apply here.
///
/// It implements the same [MediaDownloadHandle] the yt-dlp path already
/// returns, so the download state machine, cancellation, retry and failure
/// presentation above it are untouched.
class EnclosureDownloadService {
  EnclosureDownloadService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  /// Starts fetching [url] into [directory].
  ///
  /// [expectedBytes] is the feed's advertised `enclosure length`, used only
  /// when the response omits `Content-Length`. It is a fallback for the
  /// progress fraction, never a check on what arrived: hosts that assemble
  /// audio per request routinely send a different number of bytes than the
  /// feed advertises.
  EnclosureDownload start(String url, String directory, {int? expectedBytes}) =>
      EnclosureDownload._(_clientFactory(), url, directory, expectedBytes);
}

class EnclosureDownload implements MediaDownloadHandle {
  EnclosureDownload._(
    this._client,
    this._url,
    this._directory,
    this._expectedBytes,
  ) {
    unawaited(_run());
  }

  final HttpClient _client;
  final String _url;
  final String _directory;
  final int? _expectedBytes;

  final _progress = StreamController<double>.broadcast();
  final _result = Completer<String?>();

  bool _cancelled = false;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _body;
  File? _partial;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<String?> get completed => _result.future;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    unawaited(_subscription?.cancel());
    // Cancelling the subscription means neither onDone nor onError will ever
    // fire, so the body future has to be released here or `_run` waits on it
    // forever and never closes its sink.
    if (_body?.isCompleted == false) _body!.complete();
    _client.close(force: true);
    _finish(error: const EnclosureDownloadError('Download cancelled.'));
  }

  Future<void> _run() async {
    try {
      final uri = Uri.parse(_url);
      if (!uri.isScheme('http') && !uri.isScheme('https')) {
        throw EnclosureDownloadError(
          'The feed gave an enclosure address this app will not fetch: '
          '${uri.scheme.isEmpty ? 'no scheme' : uri.scheme}.',
        );
      }

      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (_cancelled) return;

      // A 200 body is the media. Anything else — an error page, a login wall,
      // a "removed" notice — would otherwise land on disk as a media file and
      // fail much later as a corrupt import.
      if (response.statusCode != HttpStatus.ok) {
        throw EnclosureDownloadError(
          'The host answered ${response.statusCode} instead of sending the '
          'episode.',
        );
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : (_expectedBytes ?? 0);

      final target = await _reserveTarget(
        response.headers.contentType?.mimeType,
      );
      final partial = File('${target.path}.part');
      _partial = partial;
      final sink = partial.openWrite();

      var received = 0;
      final done = Completer<void>();
      _body = done;
      _subscription = response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _progress.add((received / total).clamp(0.0, 1.0));
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error) {
          if (!done.isCompleted) done.completeError(error);
        },
        cancelOnError: true,
      );

      try {
        await done.future;
      } finally {
        await sink.close();
      }
      if (_cancelled) {
        await _discardPartial();
        return;
      }

      if (received == 0) {
        throw const EnclosureDownloadError('The host sent an empty episode.');
      }

      await partial.rename(target.path);
      _partial = null;
      _progress.add(1);
      _finish(path: target.path);
    } catch (error) {
      if (_cancelled) return;
      await _discardPartial();
      _finish(
        error: error is EnclosureDownloadError
            ? error
            // Transport, DNS, TLS and timeout failures all land here. They get
            // one named state; the exception itself rides along as a
            // diagnostic rather than becoming the sentence shown to the
            // learner.
            : const EnclosureDownloadError(
                'The episode could not be fetched from its host.',
              ).withCause(error),
      );
    } finally {
      _client.close();
    }
  }

  /// Picks a free path so a second download of the same episode cannot
  /// truncate the first one's bytes while it is still being read.
  Future<File> _reserveTarget(String? mimeType) async {
    final base = _fileNameFor(Uri.parse(_url), mimeType);
    final dot = base.lastIndexOf('.');
    final stem = dot <= 0 ? base : base.substring(0, dot);
    final extension = dot <= 0 ? '' : base.substring(dot);

    var candidate = File('$_directory/$base');
    var index = 2;
    while (await candidate.exists()) {
      candidate = File('$_directory/$stem ($index)$extension');
      index++;
    }
    return candidate;
  }

  Future<void> _discardPartial() async {
    final partial = _partial;
    _partial = null;
    if (partial == null) return;
    try {
      if (await partial.exists()) await partial.delete();
    } on FileSystemException {
      // A leftover .part is inert; failing the download over it would replace
      // the real reason with a cleanup error.
    }
  }

  void _finish({String? path, EnclosureDownloadError? error}) {
    if (_result.isCompleted) return;
    if (error != null) {
      _result.completeError(error);
    } else {
      _result.complete(path);
    }
    if (!_progress.isClosed) unawaited(_progress.close());
  }
}

/// Derives a readable file name from the enclosure URL.
///
/// Enclosure URLs routinely carry tracking prefixes and query strings, so the
/// last path segment is used and the query is dropped. When that segment gives
/// no usable name or extension, the response's media type fills in — a file
/// with no extension is one ffprobe and the player both have to guess about.
String _fileNameFor(Uri uri, String? mimeType) {
  final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  final raw = segments.isEmpty ? '' : Uri.decodeComponent(segments.last);
  final sanitized = raw
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')
      .trim();

  final name = sanitized.isEmpty ? 'episode' : sanitized;
  if (name.contains('.') && !name.endsWith('.')) return name;
  return '$name${_extensionFor(mimeType)}';
}

String _extensionFor(String? mimeType) => switch (mimeType) {
  'audio/mpeg' || 'audio/mp3' => '.mp3',
  'audio/mp4' || 'audio/x-m4a' => '.m4a',
  'audio/aac' => '.aac',
  'audio/ogg' || 'audio/vorbis' => '.ogg',
  'audio/opus' => '.opus',
  'audio/wav' || 'audio/x-wav' => '.wav',
  'audio/flac' || 'audio/x-flac' => '.flac',
  'video/mp4' => '.mp4',
  'video/quicktime' => '.mov',
  // An unrecognised type gets no extension rather than a guessed `.mp3`.
  // ffprobe and the player both sniff the container; a wrong extension would
  // outlive this download and mislabel the file everywhere it is shown.
  _ => '',
};

class EnclosureDownloadError implements Exception {
  const EnclosureDownloadError(this.message, {this.cause});

  /// The named state, written to be spoken to the learner.
  final String message;

  /// The underlying exception, when there was one. Diagnostics only: it
  /// reaches the failure's raw field through [toString] and must not be
  /// rendered as prose.
  final Object? cause;

  EnclosureDownloadError withCause(Object cause) =>
      EnclosureDownloadError(message, cause: cause);

  @override
  String toString() => cause == null ? message : '$message [$cause]';
}
