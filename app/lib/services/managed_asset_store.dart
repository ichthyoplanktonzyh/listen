import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The managed asset store cannot be reached right now — a remembered custom
/// location is not on disk (unmounted drive, renamed folder). Typed so the UI
/// can name the cause without rendering raw errors: nothing here is transport
/// text, and membership decisions never depend on it.
final class ManagedStoreUnavailable implements Exception {
  const ManagedStoreUnavailable();
}

/// A source or store entry could not safely be copied. Deliberately carries no
/// platform error or path: callers can show an honest, localized failure
/// without leaking local filesystem details into UI state.
final class ManagedStoreCopyFailed implements Exception {
  const ManagedStoreCopyFailed();
}

/// Outcome of bringing one source file into the managed store.
final class ManagedAssetCopy {
  const ManagedAssetCopy({
    required this.path,
    required this.createdNew,
    required this.mediaKind,
  });

  /// The store path of the managed copy (a fresh one, or the pre-existing
  /// deduplication target).
  final String path;

  /// True only when this call created the copy. Only then may a caller that
  /// fails downstream remove it — a pre-existing target is shared and must
  /// never be deleted by a caller that merely deduplicated onto it.
  final bool createdNew;

  /// The source's media classification is carried separately because managed
  /// filenames deliberately have no extension. Core receives this value when
  /// rebinding the already-open material, so audio does not become video just
  /// because its verified store name is digest-only.
  final String mediaKind;
}

/// The filesystem half of retention: copy a source file into the managed
/// store, content-addressed by SHA-256, and delete managed copies.
///
/// The service knows nothing about Core, membership, or the UI. Registration
/// and the retention decision belong to the caller; this service only makes
/// the copy honest:
///
/// * the original is never touched;
/// * the copy is verified byte-for-byte (streaming SHA-256 of source and
///   staged copy must agree) before it is renamed into place atomically;
/// * identical content maps to the same path, so repeated Keeps of the same
///   bytes deduplicate instead of duplicating;
/// * a staged copy is removed whether the copy or the rename fails.
abstract interface class ManagedAssetStoreService {
  Future<ManagedAssetCopy> copyIntoStore({
    required String sourcePath,
    String? mediaKind,
  });

  /// Copies in-memory bytes (e.g. a picked document) into the store with the
  /// same verification and deduplication as [copyIntoStore]. The bytes are
  /// staged through a temporary file so every verification path stays
  /// streaming; [mediaKind] is explicit because there is no source path to
  /// derive it from.
  Future<ManagedAssetCopy> copyBytesIntoStore({
    required List<int> bytes,
    required String mediaKind,
  });

  /// Whether [path] already lives inside the store.
  ///
  /// The store owns this answer because it owns the root. A caller that
  /// reassembled the root from settings would be re-deriving a fact the
  /// service already holds — and would need the file system to do it.
  bool contains(String path);

  /// Reads a store copy back for direct rendering, or null when the file is
  /// missing, unreadable, or outside the managed root. Callers treat null as
  /// an unavailable Source Asset fact, never a crash.
  Future<List<int>?> readBytes(String path);

  Future<void> deleteStoreCopy(String path);
}

/// Content-addressed store implementation.
///
/// Final filenames are exactly the lowercase SHA-256 digest — no source name
/// or extension. That is the deterministic extension policy: identical bytes
/// deduplicate even when source filenames/extensions disagree, and arbitrary
/// source-name characters never become a managed path component. The
/// source-derived media kind travels in [ManagedAssetCopy] instead.
///
/// The root is resolved lazily through [resolveRoot] so the same instance
/// follows a settings change without a rebuild. A null root means the store
/// is unavailable and every operation throws [ManagedStoreUnavailable].
final class LocalManagedAssetStoreService implements ManagedAssetStoreService {
  LocalManagedAssetStoreService({
    required this.resolveRoot,
    this.temporaryDirectoryName = '.staging',
  });

  /// Current store root, or null when unavailable (custom location missing).
  final String? Function() resolveRoot;

  /// Name of the staging directory kept inside the store root. Staged copies
  /// live beside their target so the final rename stays on one filesystem.
  final String temporaryDirectoryName;

  /// Serializes duplicate Keep operations inside this app process. A final
  /// rename is still the publication boundary, while serialization gives the
  /// two callers honest ownership: exactly one owns a fresh copy and only it
  /// may roll it back if Core rejects the following registration.
  final Map<String, Future<void>> _copyTails = {};

  /// The app-managed default store under macOS Application Support. Used when
  /// no custom location has been chosen; owned and created by the app.
  static String defaultPathFor(String appSupportPath) =>
      '$appSupportPath${Platform.pathSeparator}managed-assets';

  String? get _root {
    final root = resolveRoot();
    return (root == null || root.isEmpty) ? null : root;
  }

  @override
  Future<ManagedAssetCopy> copyIntoStore({
    required String sourcePath,
    String? mediaKind,
  }) async {
    try {
      final root = _root;
      if (root == null) throw const ManagedStoreUnavailable();
      final rootDirectory = Directory(root);
      // The store is created on demand — including the default app-managed
      // store, which does not exist before the first Keep. A root that cannot
      // be created (unmounted drive, missing permissions) is an unavailable
      // store, never a raw filesystem error.
      if (!await rootDirectory.exists()) {
        await rootDirectory.create(recursive: true);
      }
      final resolvedRoot = await rootDirectory.resolveSymbolicLinks();
      if (await FileSystemEntity.type(resolvedRoot, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const ManagedStoreUnavailable();
      }

      final source = File(sourcePath);
      if (!await source.exists()) throw const ManagedStoreCopyFailed();
      final digest = await _hashFile(source);
      final kind = mediaKind ?? _mediaKind(sourcePath);
      return _serializeCopy(
        digest,
        () => _copyVerified(
          source: source,
          digest: digest,
          mediaKind: kind,
          resolvedRoot: resolvedRoot,
        ),
      );
    } on FileSystemException {
      // A configured root is unavailable; the caller must not render a raw
      // OS message or guess that membership changed.
      throw const ManagedStoreUnavailable();
    }
  }

  @override
  Future<ManagedAssetCopy> copyBytesIntoStore({
    required List<int> bytes,
    required String mediaKind,
  }) async {
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'listen-managed-${_randomSuffix()}',
    );
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      return await copyIntoStore(sourcePath: tempFile.path, mediaKind: mediaKind);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Best effort: a stale system-temp file is harmless and never part
          // of the managed store.
        }
      }
    }
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final root = _root;
    if (root == null) return null;
    String resolvedRoot;
    try {
      resolvedRoot = await Directory(root).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
    try {
      if (!await _isManagedCopyAt(path, resolvedRoot)) return null;
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<ManagedAssetCopy> _copyVerified({
    required File source,
    required String digest,
    required String mediaKind,
    required String resolvedRoot,
  }) async {
    try {
      final targetPath = '$resolvedRoot${Platform.pathSeparator}$digest';
      if (await _isVerifiedManagedFile(targetPath, digest)) {
        return ManagedAssetCopy(
          path: targetPath,
          createdNew: false,
          mediaKind: mediaKind,
        );
      }
      if (await FileSystemEntity.type(targetPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        // A directory, symlink, or a mismatching regular file is never a
        // dedupe target and must never be overwritten or followed.
        throw const ManagedStoreCopyFailed();
      }

      final stagingPath =
          '$resolvedRoot${Platform.pathSeparator}$temporaryDirectoryName';
      final stagingType = await FileSystemEntity.type(
        stagingPath,
        followLinks: false,
      );
      if (stagingType == FileSystemEntityType.notFound) {
        await Directory(stagingPath).create(recursive: true);
      } else if (stagingType != FileSystemEntityType.directory) {
        throw const ManagedStoreCopyFailed();
      }
      final staging = Directory(stagingPath);
      if (await staging.resolveSymbolicLinks() != stagingPath) {
        throw const ManagedStoreCopyFailed();
      }
      final tempPath =
          '${staging.path}${Platform.pathSeparator}'
          '$digest.part-${_randomSuffix()}';
      try {
        if (await FileSystemEntity.type(tempPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const ManagedStoreCopyFailed();
        }
        await source.copy(tempPath);
        // Verify the copy byte-for-byte: the digest of the staged copy must
        // equal the digest of the original before anything is renamed into
        // place. Both hashes are streaming (SHA-256 over chunked reads), so
        // memory stays flat even for long media files.
        final copiedDigest = await _hashFile(File(tempPath));
        if (copiedDigest != digest) {
          throw const FileSystemException(
            'managed copy failed SHA-256 verification',
          );
        }
        try {
          await File(tempPath).rename(targetPath);
        } on FileSystemException {
          // An external process may publish the same digest while this process
          // is copying. It is a dedupe success only if it is a verified regular
          // file inside this resolved root — never a directory or symlink.
          if (await _isVerifiedManagedFile(targetPath, digest)) {
            return ManagedAssetCopy(
              path: targetPath,
              createdNew: false,
              mediaKind: mediaKind,
            );
          }
          rethrow;
        }
        return ManagedAssetCopy(
          path: targetPath,
          createdNew: true,
          mediaKind: mediaKind,
        );
      } finally {
        // Whatever happened, a staged copy must not linger in the store.
        if (await File(tempPath).exists()) {
          try {
            await File(tempPath).delete();
          } on FileSystemException {
            // Best effort: the store stays usable even if a stale staging file
            // survives; it is never treated as a library row.
          }
        }
      }
    } on ManagedStoreCopyFailed {
      rethrow;
    } on FileSystemException {
      throw const ManagedStoreCopyFailed();
    }
  }

  /// A plain prefix test is exact here because the store is flat and
  /// content-addressed: every managed file is `<root>/<sha256>`, so nothing
  /// below the root can be anything but a store entry.
  @override
  bool contains(String path) {
    final root = _root;
    if (root == null) return false;
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return path.startsWith(prefix);
  }

  @override
  Future<void> deleteStoreCopy(String path) async {
    final root = _root;
    if (root == null) return;
    String resolvedRoot;
    try {
      resolvedRoot = await Directory(root).resolveSymbolicLinks();
    } on FileSystemException {
      return;
    }
    final file = File(path);
    try {
      if (!await _isManagedCopyAt(file.path, resolvedRoot)) return;
      await file.delete();
    } on FileSystemException {
      // Rollback is best effort. A failed cleanup must not turn a safe Keep
      // failure into a path-bearing UI error.
    }
  }

  /// Streaming copy that hashes the destination as it writes; the returned
  /// digest must equal the source digest for the copy to be trusted.
  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<ManagedAssetCopy> _serializeCopy(
    String key,
    Future<ManagedAssetCopy> Function() action,
  ) async {
    final previous = _copyTails[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final tail = previous.then((_) => gate.future, onError: (_) => gate.future);
    _copyTails[key] = tail;
    try {
      await previous;
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_copyTails[key], tail)) _copyTails.remove(key);
    }
  }

  Future<bool> _isVerifiedManagedFile(String path, String digest) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    return await _hashFile(File(path)) == digest;
  }

  Future<bool> _isManagedCopyAt(String path, String resolvedRoot) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final resolvedPath = await File(path).resolveSymbolicLinks();
    if (!_isWithin(resolvedPath, resolvedRoot)) return false;
    final name = File(resolvedPath).uri.pathSegments.last;
    final match = RegExp(r'^([a-f0-9]{64})$').firstMatch(name);
    return match != null &&
        await _hashFile(File(resolvedPath)) == match.group(1);
  }

  static bool _isWithin(String path, String root) {
    final normalizedRoot = _normalize(root);
    final normalizedPath = _normalize(path);
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot${Platform.pathSeparator}');
  }

  static String _normalize(String path) {
    final normalized = Uri.file(
      path,
      windows: Platform.isWindows,
    ).normalizePath().toFilePath(windows: Platform.isWindows);
    return normalized.endsWith(Platform.pathSeparator)
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}

String _mediaKind(String path) {
  final lower = path.toLowerCase();
  return const [
        '.m4a',
        '.mp3',
        '.wav',
        '.flac',
        '.aac',
        '.ogg',
      ].any(lower.endsWith)
      ? 'audio'
      : 'video';
}

String _randomSuffix() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

final _random = Random();
