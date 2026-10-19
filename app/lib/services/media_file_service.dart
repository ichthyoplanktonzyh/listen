import 'dart:io';

abstract interface class MediaFileService {
  bool exists(String path);
  String basename(String path);

  /// Removes one media file, answering whether it is gone afterwards.
  ///
  /// A file that was already absent counts as removed: the caller asked for a
  /// state, not for an event, and reporting a failure over a file somebody
  /// else deleted first would send them looking for a problem that is not
  /// there. False means the file is still on disk — a permission or a busy
  /// volume — and the caller must not claim it was cleared.
  Future<bool> delete(String path);
}

class LocalMediaFileService implements MediaFileService {
  const LocalMediaFileService();

  @override
  bool exists(String path) => File(path).existsSync();
  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;

  @override
  Future<bool> delete(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return true;
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
