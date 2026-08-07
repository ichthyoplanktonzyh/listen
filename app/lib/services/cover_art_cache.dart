import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Cover art bytes, fetched once and kept on disk.
///
/// `Image.network` caches decoded bitmaps in memory and nothing else. Two
/// consequences were visible in discovery, and neither was fixed by bounding
/// the decode:
///
/// * Podcast artwork is large because Apple asks publishers for 3000×3000.
///   One measured NPR episode cover is 524 KB and takes about 3.6 s on a cold
///   link. A first screen of twenty distinct covers is roughly 10 MB, and none
///   of it survives a restart, so every launch pays for all of it again.
/// * The memory cache is keyed by decode size. A shelf card decodes at 168 pt
///   and the detail panel at 380 pt, so opening an episode misses the cache
///   entirely and downloads the same half-megabyte a second time — which is
///   why the panel's hero felt slower than the card it was opened from.
///
/// So the sharing happens at the byte layer, below the decode. Both sites keep
/// their own decode size — a single shared size would either look soft on the
/// hero or put twenty 5 MB bitmaps into a 100 MB cache — and share the
/// download. Decoding the same file twice costs milliseconds; fetching it
/// twice costs seconds.
class CoverArtCache {
  CoverArtCache({required Directory this._directory, HttpClient? client})
    : _client = client ?? HttpClient();

  /// The real per-user cache. Only the composition root builds this: a default
  /// reaching for `$HOME` would have every widget test write cover art into
  /// the developer's own support directory.
  factory CoverArtCache.forCurrentUser({String? home}) => CoverArtCache(
    directory: Directory(
      '${home ?? Platform.environment['HOME'] ?? ''}'
      '/Library/Application Support/listen/cover-art',
    ),
  );

  /// A cache that keeps nothing: every read goes to the network. The default,
  /// so that nothing acquires a disk footprint by accident.
  CoverArtCache.memoryOnly({HttpClient? client})
    : _directory = null,
      _client = client ?? HttpClient();

  /// The cache [CoverArtImage] reads through when it was not handed one.
  ///
  /// A mutable static is the smaller evil here: an [ImageProvider] is
  /// constructed deep inside `build`, where there is no seam to inject
  /// through, and threading a cache down every widget that draws a cover
  /// would put infrastructure into six presentation signatures.
  static CoverArtCache instance = CoverArtCache.memoryOnly();

  final Directory? _directory;
  final HttpClient _client;

  /// Downloads in progress, so the shelf card and the hero that opened from it
  /// wait on one request rather than starting two.
  final Map<String, Future<Uint8List>> _inFlight = {};

  File? _fileFor(String url) {
    final directory = _directory;
    if (directory == null) return null;
    final digest = sha256.convert(utf8.encode(url));
    return File('${directory.path}/$digest');
  }

  /// The bytes for [url], from disk when they are already there.
  ///
  /// [onProgress] reports download progress in bytes; the total is null when
  /// the host does not send a content length. A cached read reports nothing,
  /// because there is no waiting to describe.
  Future<Uint8List> bytesOf(
    String url, {
    void Function(int loaded, int? total)? onProgress,
  }) {
    final existing = _inFlight[url];
    if (existing != null) return existing;
    final pending = _read(url, onProgress);
    _inFlight[url] = pending;
    return pending.whenComplete(() => _inFlight.remove(url));
  }

  Future<Uint8List> _read(
    String url,
    void Function(int loaded, int? total)? onProgress,
  ) async {
    final file = _fileFor(url);
    if (file != null) {
      try {
        if (await file.exists()) return await file.readAsBytes();
      } on FileSystemException {
        // An unreadable cache entry is not a missing cover. Fall through to
        // the network rather than reporting artwork that does not exist.
      }
    }

    final bytes = await _download(url, onProgress);

    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      } on FileSystemException {
        // An unwritable cache directory costs this cover across restarts, not
        // this session's. Failing the image over it would be the larger harm.
      }
    }
    return bytes;
  }

  Future<Uint8List> _download(
    String url,
    void Function(int loaded, int? total)? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      // Drained so the connection can be reused; the body of a non-200 is of
      // no interest here.
      await response.drain<void>();
      throw HttpException(
        'The artwork host answered ${response.statusCode}.',
        uri: uri,
      );
    }

    final total = response.contentLength < 0 ? null : response.contentLength;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      onProgress?.call(builder.length, total);
    }
    return builder.takeBytes();
  }
}

/// Remote cover art read through a [CoverArtCache].
///
/// Equality is the URL alone. That is the point: wrapped in a `ResizeImage`,
/// two draw sizes stay two entries in the decoded-bitmap cache while sharing
/// one fetch underneath.
@immutable
class CoverArtImage extends ImageProvider<CoverArtImage> {
  const CoverArtImage(this.url, {this.cache});

  final String url;

  /// Injected only by tests; production reads [CoverArtCache.instance] at load
  /// time so that the composition root can install the disk-backed one after
  /// widgets have already been built.
  final CoverArtCache? cache;

  @override
  Future<CoverArtImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CoverArtImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CoverArtImage key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode, chunks),
      chunkEvents: chunks.stream,
      scale: 1,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadCodec(
    CoverArtImage key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      final bytes = await (key.cache ?? CoverArtCache.instance).bytesOf(
        key.url,
        onProgress: (loaded, total) {
          if (chunks.isClosed) return;
          chunks.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: loaded,
              expectedTotalBytes: total,
            ),
          );
        },
      );
      if (bytes.isEmpty) {
        throw StateError('The artwork host sent an empty body.');
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Same contract as NetworkImage: a failed load must not sit in the cache
      // as a permanently broken entry, and the eviction cannot happen during
      // the resolve that is still running.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      await chunks.close();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CoverArtImage && other.url == url && other.cache == cache;

  @override
  int get hashCode => Object.hash(url, cache);

  @override
  String toString() => 'CoverArtImage("$url")';
}
